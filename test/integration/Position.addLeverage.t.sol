// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import {
    Assets,
    AAVE_ORACLE,
    CONTRACT_DEPLOYER,
    DAI,
    FEE_COLLECTOR,
    TEST_CLIENT,
    TEST_POOL_FEE,
    USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionAddLeverageTest is Test, TokenUtils, DebtUtils {
    /* solhint-disable func-name-mixedcase */

    struct TestPosition {
        address addr;
        address cToken;
        address dToken;
        address bToken;
    }

    struct ContractBalances {
        uint256 preBToken;
        uint256 postBToken;
        uint256 preVDToken;
        uint256 postVDToken;
        uint256 preAToken;
        uint256 postAToken;
    }

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    address public positionAddr;
    uint256 public mainnetFork;
    address public owner = address(this);

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        deployCodeTo("FeeCollector.sol", abi.encode(CONTRACT_DEPLOYER), FEE_COLLECTOR);

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER);

        // Deploy and store all possible positions where cToken and bToken are the same
        for (uint256 i; i < supportedAssets.length; i++) {
            address cToken = supportedAssets[i];
            for (uint256 j; j < supportedAssets.length; j++) {
                if (j != i) {
                    address dToken = supportedAssets[j];
                    address bToken = cToken;
                    // Exclude positions with no pool
                    bool poolExists = !((dToken == USDC && bToken == DAI) || (dToken == DAI && bToken == USDC));
                    if (poolExists) {
                        positionAddr = positionFactory.createPosition(cToken, dToken, bToken);
                        TestPosition memory newPosition =
                            TestPosition({ addr: positionAddr, cToken: cToken, dToken: dToken, bToken: bToken });
                        positions.push(newPosition);
                    }
                }
            }
        }

        // Mock AaveOracle
        for (uint256 i; i < supportedAssets.length; i++) {
            vm.mockCall(
                AAVE_ORACLE,
                abi.encodeWithSelector(IAaveOracle(AAVE_ORACLE).getAssetPrice.selector, supportedAssets[i]),
                abi.encode(assets.prices(supportedAssets[i]))
            );
        }
    }

    /// @dev
    // - The active fork should be the forked network created in the setup
    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - The Position contract's bToken balance after adding leverage should equal bAmt (from swap).
    // - The Position contract's aToken balance should increase by its bToken balance before adding leverage.
    // - The Position contract's variable debt token balance should increase by dAmt (from borrow).
    // - The above should be true for a large range of LTVs and cAmts.
    function testFuzz_AddLeverage(uint256 _ltv, uint256 _cAmt) public {
        // Setup
        ContractBalances memory contractBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;
            address cToken = positions[i].cToken;
            address bToken = cToken;

            // Bound fuzzed variables
            _ltv = bound(_ltv, 1, 60);
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Fund owner with collateral
            _fund(owner, cToken, _cAmt);

            // Approve position to spend collateral
            IERC20(cToken).approve(addr, _cAmt);

            // Add initial short position
            IPosition(addr).add(_cAmt, 50, 0, TEST_POOL_FEE, TEST_CLIENT);

            // Pre-act balances
            contractBalances.preBToken = IERC20(bToken).balanceOf(addr);
            contractBalances.preVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.preAToken = _getATokenBalance(addr, positions[i].cToken);

            // Act
            vm.recordLogs();
            IPosition(addr).addLeverage(_ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

            // Retrieve bAmt and dAmt from AddLeverage event
            VmSafe.Log[] memory entries = vm.getRecordedLogs();
            bytes memory addLeverageEvent = entries[entries.length - 1].data;
            uint256 cAmt;
            uint256 dAmt;
            uint256 bAmt;
            assembly {
                cAmt := mload(add(addLeverageEvent, 0x20))
                dAmt := mload(add(addLeverageEvent, 0x40))
                bAmt := mload(add(addLeverageEvent, 0x60))
            }

            // Post-act balances
            contractBalances.postBToken = IERC20(bToken).balanceOf(addr);
            contractBalances.postVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.postAToken = _getATokenBalance(addr, positions[i].cToken);

            // Assertions
            assertEq(contractBalances.postBToken, bAmt);
            assertApproxEqAbs(contractBalances.postAToken, contractBalances.preAToken + cAmt, 1);
            assertApproxEqAbs(contractBalances.postVDToken, contractBalances.preVDToken + dAmt, 1);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }
}

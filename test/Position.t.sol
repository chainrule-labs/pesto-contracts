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
    PROFIT_PERCENT,
    SWAP_ROUTER,
    USDC,
    WBTC,
    WETH
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/services/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/services/utils/DebtUtils.t.sol";
import { MockUniswapGains } from "test/mocks/MockUniswap.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionTest is Test, TokenUtils, DebtUtils {
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

    struct UserBalances {
        uint256 preBToken;
        uint256 postBToken;
        uint256 preCToken;
        uint256 postCToken;
    }

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    address public positionAddr;
    uint256 public mainnetFork;

    // Events
    event Short(uint256 cAmt, uint256 dAmt, uint256 bAmt);

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory();

        // Deploy and store all possible positions
        for (uint256 i; i < supportedAssets.length; i++) {
            address cToken = supportedAssets[i];
            for (uint256 j; j < supportedAssets.length; j++) {
                if (j != i) {
                    address dToken = supportedAssets[j];
                    for (uint256 k; k < supportedAssets.length; k++) {
                        address bToken = supportedAssets[k];
                        // Exclude positions with no pool
                        bool poolExists = !((dToken == USDC && bToken == DAI) || (dToken == DAI && bToken == USDC));
                        if (k != j && poolExists) {
                            positionAddr = positionFactory.createPosition(cToken, dToken, bToken);
                            TestPosition memory newPosition =
                                TestPosition({ addr: positionAddr, cToken: cToken, dToken: dToken, bToken: bToken });
                            positions.push(newPosition);
                        }
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

    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - User's cToken balance should decrease by collateral amount supplied.
    // - Position's bToken balance should increase by amount receieved from swap.
    // - The above should be true for a wide range of LTVs.
    // - The above should be true for a wide range of collateral amounts.
    // - The above should be true for all supported tokens.

    function testFuzz_Short(uint256 _ltv, uint256 _cAmt) public {
        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;
            address cToken = positions[i].cToken;
            address bToken = positions[i].bToken;

            // Bound fuzzed variables
            _ltv = bound(_ltv, 1, 60);
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Fund user with collateral
            _fund(address(this), cToken, _cAmt);

            // Approve position to spend collateral
            IERC20(cToken).approve(addr, _cAmt);

            // Pre-act balances
            uint256 colPreBal = IERC20(cToken).balanceOf(address(this));
            uint256 basePreBal = IERC20(cToken).balanceOf(addr);

            // Act
            vm.recordLogs();
            IPosition(addr).short(_cAmt, _ltv, 0, 3000);
            VmSafe.Log[] memory entries = vm.getRecordedLogs();

            // Post-act balances
            uint256 colPostBal = IERC20(cToken).balanceOf(address(this));
            uint256 basePostBal = IERC20(bToken).balanceOf(addr);
            bytes memory shortEvent = entries[entries.length - 1].data;
            uint256 bAmt;

            assembly {
                let startPos := sub(mload(shortEvent), 32)
                bAmt := mload(add(shortEvent, add(0x20, startPos)))
            }

            // Assertions
            assertEq(colPostBal, colPreBal - _cAmt);
            assertEq(basePostBal, basePreBal + bAmt);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - Position contract's bToken balance should go to 0.
    // - Position contract's debt on Aave should go to 0.
    // - User's cToken balance should increase by the amount of collateral withdrawn.
    // - User's bToken balance should increase by the position's gains amount.
    // - The above should be true for all supported tokens.

    function test_CloseWithGains() public {
        ContractBalances memory contractBalances;
        UserBalances memory userBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;

            // Setup: open short position
            uint256 cAmt = assets.maxCAmts(positions[i].cToken);
            uint256 ltv = 50;
            _fund(address(this), positions[i].cToken, cAmt);
            IERC20(positions[i].cToken).approve(addr, cAmt);
            IPosition(addr).short(cAmt, ltv, 0, 3000);

            // Get pre-act balances
            contractBalances.preBToken = IERC20(positions[i].bToken).balanceOf(addr);
            contractBalances.preVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.preAToken = _getATokenBalance(addr, positions[i].cToken);
            userBalances.preBToken = IERC20(positions[i].bToken).balanceOf(address(this));
            userBalances.preCToken = IERC20(positions[i].cToken).balanceOf(address(this));

            // Assertions
            assertEq(userBalances.preBToken, 0);
            assertNotEq(contractBalances.preBToken, 0);
            assertNotEq(contractBalances.preVDToken, 0);

            // Mock Uniswap to ensure position gains
            _fund(SWAP_ROUTER, positions[i].dToken, contractBalances.preVDToken);
            bytes memory code = address(new MockUniswapGains()).code;
            vm.etch(SWAP_ROUTER, code);

            // Act
            /// @dev start event recorder
            vm.recordLogs();
            IPosition(addr).close(3000, true, 0, 10);
            VmSafe.Log[] memory entries = vm.getRecordedLogs();

            // Get post-act balances
            contractBalances.postBToken = IERC20(positions[i].bToken).balanceOf(addr);
            contractBalances.postVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.postAToken = _getATokenBalance(addr, positions[i].cToken);
            userBalances.postBToken = IERC20(positions[i].bToken).balanceOf(address(this));
            userBalances.postCToken = IERC20(positions[i].cToken).balanceOf(address(this));

            bytes memory closeEvent = entries[entries.length - 1].data;
            uint256 gains;

            assembly {
                gains := mload(add(closeEvent, 0x20))
            }

            // Assertions:
            assertEq(contractBalances.postBToken, 0);
            assertEq(contractBalances.postVDToken, 0);
            assertEq(contractBalances.postAToken, 0);
            assertApproxEqAbs(gains, contractBalances.preBToken * PROFIT_PERCENT / 100, 1);

            if (positions[i].bToken == positions[i].cToken) {
                /// @dev In this case, bToken and cToken balances will increase by the same amount (gains + collateral withdrawn)
                assertEq(userBalances.postBToken, userBalances.preBToken + gains + contractBalances.preAToken);
                assertEq(userBalances.postCToken, userBalances.postBToken);
            } else {
                assertEq(userBalances.postBToken, userBalances.preBToken + gains);
                assertEq(userBalances.postCToken, userBalances.preCToken + contractBalances.preAToken);
            }

            // Revert to snapshot
            vm.revertTo(id);
        }
    }
}

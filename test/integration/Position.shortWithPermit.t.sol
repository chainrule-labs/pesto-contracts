// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import {
    Assets, AAVE_ORACLE, CONTRACT_DEPLOYER, DAI, FEE_COLLECTOR, TEST_CLIENT, USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionShortPermitTest is Test, TokenUtils, DebtUtils {
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
        uint256 preDToken;
        uint256 postDToken;
    }

    struct OwnerBalances {
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
    VmSafe.Wallet public wallet;
    address public positionAddr;
    uint256 public mainnetFork;
    address public owner;

    // Events
    event Short(uint256 cAmt, uint256 dAmt, uint256 bAmt);

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

        // Set contract owner
        wallet = vm.createWallet(uint256(keccak256(abi.encodePacked(uint256(1)))));
        owner = wallet.addr;

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
                            vm.prank(owner);
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

    /// @dev
    // - Owner's cToken balance should decrease by collateral amount supplied.
    // - Position's bToken balance should increase by amount receieved from swap.
    // - The above should be true for a wide range of LTVs.
    // - The above should be true for a wide range of collateral amounts.
    // - The above should be true for all supported tokens.
    // - The act should be accomplished without a separate approve tx.
    function testFuzz_ShortWithPermit(uint256 _ltv, uint256 _cAmt) public {
        ContractBalances memory contractBalances;
        OwnerBalances memory ownerBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address cToken = positions[i].cToken;
            address bToken = positions[i].bToken;

            // Bound fuzzed variables
            _ltv = bound(_ltv, 1, 60);
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Fund owner with collateral
            _fund(owner, cToken, _cAmt);

            // Get permit
            uint256 permitTimestamp = block.timestamp + 1000;
            (uint8 v, bytes32 r, bytes32 s) = _getPermit(cToken, wallet, positions[i].addr, _cAmt, permitTimestamp);

            // Pre-act balances
            contractBalances.preBToken = IERC20(bToken).balanceOf(positions[i].addr);
            ownerBalances.preCToken = IERC20(cToken).balanceOf(owner);

            // Act
            vm.recordLogs();
            vm.prank(owner);
            IPosition(positions[i].addr).addWithPermit(_cAmt, _ltv, 0, 3000, TEST_CLIENT, permitTimestamp, v, r, s);
            VmSafe.Log[] memory entries = vm.getRecordedLogs();

            // Post-act balances
            contractBalances.postBToken = IERC20(bToken).balanceOf(positions[i].addr);
            ownerBalances.postCToken = IERC20(cToken).balanceOf(owner);
            bytes memory shortEvent = entries[entries.length - 1].data;
            uint256 bAmt;

            assembly {
                let startPos := sub(mload(shortEvent), 32)
                bAmt := mload(add(shortEvent, add(0x20, startPos)))
            }

            // Assertions
            assertEq(ownerBalances.postCToken, ownerBalances.preCToken - _cAmt);
            assertEq(contractBalances.postBToken, contractBalances.preBToken + bAmt);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }
}

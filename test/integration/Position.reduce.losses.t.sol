// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

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
    PROTOCOL_FEE_RATE,
    REPAY_PERCENT,
    SWAP_ROUTER,
    TEST_CLIENT,
    TEST_LTV,
    TEST_POOL_FEE,
    USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { MockUniswapLosses } from "test/mocks/MockUniswap.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionReduceLossesTest is Test, TokenUtils, DebtUtils {
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
        uint256 preCAToken;
        uint256 postCAToken;
        uint256 preBAToken;
        uint256 postBAToken;
        uint256 preDToken;
        uint256 postDToken;
    }

    struct OwnerBalances {
        uint256 preBToken;
        uint256 postBToken;
        uint256 preCToken;
        uint256 postCToken;
    }

    struct SnapShots {
        uint256 id1;
        uint256 id2;
    }

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    address public positionAddr;
    address public owner = address(this);

    function setUp() public {
        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        deployCodeTo("FeeCollector.sol", abi.encode(CONTRACT_DEPLOYER, PROTOCOL_FEE_RATE), FEE_COLLECTOR);

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER);

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

    /// @dev Tests that the reduce function works when the position has losses and collateral token and base token are different.
    /// @notice Test strategy:
    // - 1. Open a position.
    // - 2. Mock Uniswap to ensure position losses.
    // - 3. Using screenshot, obtain max withdrawable collateral amount after withdrawing all B_TOKEN and partially repaying debt.
    // - 4. Reduce the position.

    /// @notice assertions.
    // - Position contract's (bToken) AToken balance should go to 0 (full withdraw).
    // - Position contract's (cToken) AToken balance should decrease by the amount withdrawn.
    // - Position contract's dToken balance should be 0; no gains, so all was used for swap.
    // - Position contract's debt on Aave should decrease by repayment (amount received from the swap).
    // - Position contract's debt should be greater than 0 after reduction.
    // - Owner's cToken balance should increase by the amount of collateral withdrawn.
    // - Owner's bToken balance should not increase; no gains.
    // - Position contract's gains should be 0.
    // - The above should be true for all supported tokens.
    function test_ReduceExactInputDiffCAndB(uint256 withdrawCAmt) public {
        // Setup
        ContractBalances memory contractBalances;
        OwnerBalances memory ownerBalances;
        TestPosition memory p;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken != p.bToken) {
                // Setup: open position
                _fund(owner, p.cToken, assets.maxCAmts(p.cToken));
                IERC20(p.cToken).approve(p.addr, assets.maxCAmts(p.cToken));
                IPosition(p.addr).add(assets.maxCAmts(p.cToken), TEST_LTV, 0, TEST_POOL_FEE, TEST_CLIENT);

                // Get pre-act balances
                contractBalances.preBToken = IERC20(p.bToken).balanceOf(p.addr);
                contractBalances.preDToken = IERC20(p.dToken).balanceOf(p.addr);
                contractBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.preBAToken = _getATokenBalance(p.addr, p.bToken);
                ownerBalances.preBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.preCToken = IERC20(p.cToken).balanceOf(owner);

                // Assertions
                assertEq(ownerBalances.preBToken, 0);
                assertEq(contractBalances.preDToken, 0);
                assertEq(contractBalances.preBToken, 0);
                assertNotEq(contractBalances.preVDToken, 0);
                assertNotEq(contractBalances.preCAToken, 0);
                assertNotEq(contractBalances.preBAToken, 0);

                // Mock Uniswap to ensure position losses
                uint256 dAmtOut = contractBalances.preVDToken * REPAY_PERCENT / 100;
                _fund(SWAP_ROUTER, p.dToken, dAmtOut);
                bytes memory code = address(new MockUniswapLosses()).code;
                vm.etch(SWAP_ROUTER, code);

                // Withdraw B_TOKEN and make repayment manually to get exact withdrawCAmt
                uint256 repayID = vm.snapshot();
                IPosition(p.addr).withdraw(p.bToken, contractBalances.preBAToken, owner);
                _fund(owner, p.dToken, dAmtOut);
                IERC20(p.dToken).approve(p.addr, dAmtOut);
                IPosition(p.addr).repay(dAmtOut);
                uint256 maxCTokenWithdrawal = _getMaxWithdrawAmt(p.addr, p.cToken, assets.decimals(p.cToken));
                vm.revertTo(repayID);

                // Bound fuzzed variables
                withdrawCAmt = bound(withdrawCAmt, 1, maxCTokenWithdrawal);

                // Act
                /// @dev start event recorder
                vm.recordLogs();
                IPosition(p.addr).reduce(TEST_POOL_FEE, false, 0, withdrawCAmt, contractBalances.preBAToken);
                VmSafe.Log[] memory entries = vm.getRecordedLogs();

                // Get post-act balances
                contractBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                contractBalances.postDToken = IERC20(p.dToken).balanceOf(p.addr);
                contractBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                ownerBalances.postBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.postCToken = IERC20(p.cToken).balanceOf(owner);

                bytes memory reduceEvent = entries[entries.length - 1].data;
                uint256 gains;

                assembly {
                    gains := mload(add(reduceEvent, 0x20))
                }

                // Assertions
                assertApproxEqAbs(contractBalances.postBAToken, 0, 1);
                assertApproxEqAbs(contractBalances.postCAToken, contractBalances.preCAToken - withdrawCAmt, 1);
                assertApproxEqAbs(contractBalances.postVDToken, contractBalances.preVDToken - dAmtOut, 1);
                assertGt(contractBalances.postVDToken, 0);
                assertEq(contractBalances.postDToken, 0);
                uint256 withdrawAmt = contractBalances.preCAToken - contractBalances.postCAToken;
                assertApproxEqAbs(ownerBalances.postCToken, ownerBalances.preCToken + withdrawAmt, 1);
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken);
                assertEq(gains, 0);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }

    /// @dev Tests that the reduce function works when the position has losses and collateral token and base token are the same.
    /// @notice Test strategy:
    // - 1. Open a position.
    // - 2. Mock Uniswap to ensure position losses.
    // - 3. Using screenshot, obtain max withdrawable collateral amount after withdrawing all B_TOKEN and partially repaying debt.
    // - 4. Reduce the position.

    /// @notice Assertions:
    // - Position contract's (bToken) AToken balance should decrease by the amount withdrawn.
    // - Position contract's (cToken) AToken balance should decrease by the amount withdrawn.
    // - Position contract's dToken balance should be 0; no gains, so all was used for swap.
    // - Position contract's debt on Aave should decrease by repayment (amount received from the swap).
    // - Position contract's debt should be greater than 0 after reduction.
    // - Position contract's gains should be 0.
    // - Owner's cToken balance should increase by the amount of collateral withdrawn.
    // - Owner's bToken balance should increase by the amount of collateral withdrawn.
    // - The above should be true for all supported tokens.
    function test_ReduceExactInputSameCAndB(uint256 withdrawCAmt) public {
        // Setup
        ContractBalances memory contractBalances;
        OwnerBalances memory ownerBalances;
        TestPosition memory p;
        SnapShots memory snapshots;

        // Take snapshot
        snapshots.id1 = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken == p.bToken) {
                /// @dev start event recorder
                vm.recordLogs();
                // Setup: open position
                _fund(owner, p.cToken, assets.maxCAmts(p.cToken));
                IERC20(p.cToken).approve(p.addr, assets.maxCAmts(p.cToken));
                IPosition(p.addr).add(assets.maxCAmts(p.cToken), TEST_LTV, 0, TEST_POOL_FEE, TEST_CLIENT);
                VmSafe.Log[] memory entries = vm.getRecordedLogs();

                // Extract amount of base token added to Aave
                bytes memory addEvent = entries[entries.length - 1].data;
                uint256 suppliedBAmt;
                assembly {
                    suppliedBAmt := mload(add(addEvent, 0x60))
                }

                // Get pre-act balances
                contractBalances.preBToken = IERC20(p.bToken).balanceOf(p.addr);
                contractBalances.preDToken = IERC20(p.dToken).balanceOf(p.addr);
                contractBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.preBAToken = _getATokenBalance(p.addr, p.bToken);
                ownerBalances.preBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.preCToken = IERC20(p.cToken).balanceOf(owner);

                // Assertions
                assertEq(ownerBalances.preBToken, 0);
                assertEq(contractBalances.preDToken, 0);
                assertEq(contractBalances.preBToken, 0);
                assertNotEq(contractBalances.preVDToken, 0);
                assertNotEq(contractBalances.preCAToken, 0);
                assertNotEq(contractBalances.preBAToken, 0);
                assertEq(ownerBalances.preBToken, ownerBalances.preCToken);

                // Mock Uniswap to ensure position losses
                uint256 dAmtOut = contractBalances.preVDToken * REPAY_PERCENT / 100;
                _fund(SWAP_ROUTER, p.dToken, dAmtOut);
                vm.etch(SWAP_ROUTER, address(new MockUniswapLosses()).code);

                // Withdraw B_TOKEN and make repayment manually to get exact withdrawCAmt
                snapshots.id2 = vm.snapshot();
                IPosition(p.addr).withdraw(p.bToken, suppliedBAmt, owner);
                _fund(owner, p.dToken, dAmtOut);
                IERC20(p.dToken).approve(p.addr, dAmtOut);
                IPosition(p.addr).repay(dAmtOut);
                uint256 maxCTokenWithdrawal = _getMaxWithdrawAmt(p.addr, p.cToken, assets.decimals(p.cToken));
                vm.revertTo(snapshots.id2);

                // Bound fuzzed variables
                withdrawCAmt = bound(withdrawCAmt, 1, maxCTokenWithdrawal);

                // Act
                IPosition(p.addr).reduce(TEST_POOL_FEE, false, 0, withdrawCAmt, suppliedBAmt);
                entries = vm.getRecordedLogs();

                // Get post-act balances
                contractBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                contractBalances.postDToken = IERC20(p.dToken).balanceOf(p.addr);
                contractBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                ownerBalances.postBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.postCToken = IERC20(p.cToken).balanceOf(owner);

                bytes memory reduceEvent = entries[entries.length - 1].data;
                uint256 gains;

                assembly {
                    gains := mload(add(reduceEvent, 0x20))
                }

                // Assertions
                assertApproxEqAbs(
                    contractBalances.postBAToken, contractBalances.preBAToken - suppliedBAmt - withdrawCAmt, 1
                );
                assertApproxEqAbs(
                    contractBalances.postCAToken, contractBalances.preBAToken - suppliedBAmt - withdrawCAmt, 1
                );
                assertEq(contractBalances.postDToken, 0);
                assertApproxEqAbs(contractBalances.postVDToken, contractBalances.preVDToken - dAmtOut, 1);
                assertGt(contractBalances.postVDToken, 0);
                assertEq(gains, 0);
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken + withdrawCAmt);
                assertEq(ownerBalances.postCToken, ownerBalances.postBToken);

                // Revert to snapshot
                vm.revertTo(snapshots.id1);
            }
        }
    }
}

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
    SWAP_ROUTER,
    TEST_CLIENT,
    TEST_LTV,
    TEST_POOL_FEE,
    USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { MockUniswapDirectSwap } from "test/mocks/MockUniswap.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionCloseGainsTest is Test, TokenUtils, DebtUtils {
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

    struct RepayData {
        uint256 debtInB;
        uint256 repayAmtUSD;
        uint256 repayAmtInDToken;
        uint256 maxWithdrawBAmt;
        uint256 maxWithdrawCAmt;
        uint256 bATokenAfterRepay;
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
        deployCodeTo("FeeCollector.sol", abi.encode(CONTRACT_DEPLOYER), FEE_COLLECTOR);

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

    /// @dev: Simulates close where not all B_TOKEN is withdrawn and swapped for D_TOKEN,
    //        where D_TOKEN amount is less than total debt.
    // - Position contract's (bToken) AToken balance should decrease by _withdrawBAmt.
    // - Position contract's (cToken) AToken balance should decrease by _withdrawCAmt.
    // - Position contract's dToken balance should be 0.
    ///  @notice if B_TOKEN withdraw value <= debt value, dAmtOut == debt repayment, so dToken balance == 0.
    // - Position contract's bToken balance should remain 0.
    // - Position contract's debt on Aave should decrease by amount repaid.
    // - Owner's cToken balance should increase by _withdrawCAmt.
    // - Owner's bToken balance should stay the same.
    // - Gains should be 0 because if there are any, they are unrealized.
    // - The above should be true for all supported tokens.
    function testFuzz_ClosePartialExactInputDiffCAndB(uint256 _withdrawBAmt, uint256 _withdrawCAmt) public {
        // Setup
        ContractBalances memory contractBalances;
        OwnerBalances memory ownerBalances;
        TestPosition memory p;
        RepayData memory repayData;

        // Take snapshot
        uint256 id = vm.snapshot();
        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken != p.bToken) {
                // Add to position
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

                // Calculate debt in terms of bToken and bound fuzzed _withdrawBAmt variable
                repayData.debtInB = _getDebtInB(p.addr, p.bToken, assets.decimals(p.bToken));
                repayData.maxWithdrawBAmt =
                    repayData.debtInB <= contractBalances.preBAToken ? repayData.debtInB : contractBalances.preBAToken;
                _withdrawBAmt = bound(_withdrawBAmt, assets.minCAmts(p.bToken), repayData.maxWithdrawBAmt);

                // Calculate repay amount and bound fuzzed _withdrawCAmt variable
                uint256 repayID = vm.snapshot();
                repayData.repayAmtUSD = (_withdrawBAmt * assets.prices(p.bToken)) / (10 ** assets.decimals(p.bToken));
                repayData.repayAmtInDToken =
                    ((repayData.repayAmtUSD * (10 ** assets.decimals(p.dToken))) / assets.prices(p.dToken));
                IPosition(p.addr).withdraw(p.bToken, _withdrawBAmt, owner);
                _fund(owner, p.dToken, repayData.repayAmtInDToken);
                IERC20(p.dToken).approve(p.addr, repayData.repayAmtInDToken);
                IPosition(p.addr).repay(repayData.repayAmtInDToken);
                repayData.bATokenAfterRepay = contractBalances.preBAToken - _withdrawBAmt;
                repayData.maxWithdrawCAmt = _getMaxWithdrawCAmtAfterPartialRepay(
                    p.addr,
                    p.cToken,
                    p.bToken,
                    assets.decimals(p.cToken),
                    assets.decimals(p.bToken),
                    repayData.bATokenAfterRepay
                );
                vm.revertTo(repayID);
                _withdrawCAmt = bound(_withdrawCAmt, assets.minCAmts(p.cToken), repayData.maxWithdrawCAmt);

                // Mock Uniswap
                _fund(SWAP_ROUTER, p.dToken, repayData.repayAmtInDToken);
                bytes memory code = address(new MockUniswapDirectSwap()).code;
                vm.etch(SWAP_ROUTER, code);

                // Act
                /// @dev start event recorder
                vm.recordLogs();
                IPosition(p.addr).close(TEST_POOL_FEE, false, 0, _withdrawCAmt, _withdrawBAmt);
                VmSafe.Log[] memory entries = vm.getRecordedLogs();

                // Get post-act balances
                contractBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                contractBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                contractBalances.postDToken = IERC20(p.dToken).balanceOf(p.addr);
                ownerBalances.postBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.postCToken = IERC20(p.cToken).balanceOf(owner);

                bytes memory closeEvent = entries[entries.length - 1].data;
                uint256 gains;

                assembly {
                    gains := mload(add(closeEvent, 0x20))
                }

                // Assertions:
                assertEq(contractBalances.postDToken, 0);
                assertEq(contractBalances.postBToken, 0);
                assertApproxEqAbs(
                    contractBalances.postVDToken, contractBalances.preVDToken - repayData.repayAmtInDToken, 1
                );
                assertApproxEqAbs(contractBalances.postCAToken, contractBalances.preCAToken - _withdrawCAmt, 1);
                assertApproxEqAbs(contractBalances.postBAToken, contractBalances.preBAToken - _withdrawBAmt, 1);
                assertEq(gains, 0);
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken);
                assertEq(ownerBalances.postCToken, ownerBalances.preCToken + _withdrawCAmt);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }

    /// @dev: Simulates close where not all B_TOKEN is withdrawn and swapped for D_TOKEN,
    //        where D_TOKEN amount is less than total debt.
    // - Position contract's (cToken) AToken balance should decrease by (_withdrawCAmt + _withdrawBAmt).
    // - Position contract's (bToken) AToken balance should should equal its (cToken) AToken balance.
    // - Position contract's dToken balance should be 0.
    ///  @notice if B_TOKEN withdraw value <= debt value, dAmtOut == debt repayment, so dToken balance == 0.
    // - Position contract's bToken balance should remain 0.
    // - Position contract's debt on Aave should decrease by amount repaid.
    // - Owner's cToken balance should increase by _withdrawCAmt.
    // - Owner's bToken balance should equal owner's cToken balance.
    // - Gains should be 0 because if there are any, they are unrealized.
    // - The above should be true for all supported tokens.
    function testFuzz_ClosePartialExactInputSameCAndB(uint256 _withdrawBAmt, uint256 _withdrawCAmt) public {
        // Setup
        ContractBalances memory contractBalances;
        OwnerBalances memory ownerBalances;
        TestPosition memory p;
        RepayData memory repayData;

        // Take snapshot
        uint256 id = vm.snapshot();
        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken == p.bToken) {
                // Add to position
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

                // Calculate debt in terms of bToken and bound fuzzed _withdrawBAmt variable
                repayData.debtInB = _getDebtInB(p.addr, p.bToken, assets.decimals(p.bToken));
                repayData.maxWithdrawBAmt =
                    repayData.debtInB <= contractBalances.preBAToken ? repayData.debtInB : contractBalances.preBAToken;
                _withdrawBAmt = bound(_withdrawBAmt, assets.minCAmts(p.bToken), repayData.maxWithdrawBAmt);

                // Calculate repay amount and bound fuzzed _withdrawCAmt variable
                uint256 repayID = vm.snapshot();
                repayData.repayAmtUSD = (_withdrawBAmt * assets.prices(p.bToken)) / (10 ** assets.decimals(p.bToken));
                repayData.repayAmtInDToken =
                    ((repayData.repayAmtUSD * (10 ** assets.decimals(p.dToken))) / assets.prices(p.dToken));
                IPosition(p.addr).withdraw(p.bToken, _withdrawBAmt, owner);
                _fund(owner, p.dToken, repayData.repayAmtInDToken);
                IERC20(p.dToken).approve(p.addr, repayData.repayAmtInDToken);
                IPosition(p.addr).repay(repayData.repayAmtInDToken);
                repayData.bATokenAfterRepay = contractBalances.preBAToken - _withdrawBAmt;
                repayData.maxWithdrawCAmt = contractBalances.preBAToken - repayData.bATokenAfterRepay;
                vm.revertTo(repayID);
                _withdrawCAmt = bound(_withdrawCAmt, assets.minCAmts(p.cToken), repayData.maxWithdrawCAmt);

                // Mock Uniswap
                _fund(SWAP_ROUTER, p.dToken, repayData.repayAmtInDToken);
                bytes memory code = address(new MockUniswapDirectSwap()).code;
                vm.etch(SWAP_ROUTER, code);

                // Act
                /// @dev start event recorder
                vm.recordLogs();
                IPosition(p.addr).close(TEST_POOL_FEE, false, 0, _withdrawCAmt, _withdrawBAmt);
                VmSafe.Log[] memory entries = vm.getRecordedLogs();

                // Get post-act balances
                contractBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                contractBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                contractBalances.postDToken = IERC20(p.dToken).balanceOf(p.addr);
                ownerBalances.postBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.postCToken = IERC20(p.cToken).balanceOf(owner);

                bytes memory closeEvent = entries[entries.length - 1].data;
                uint256 gains;

                assembly {
                    gains := mload(add(closeEvent, 0x20))
                }

                // Assertions:
                assertEq(contractBalances.postDToken, 0);
                assertEq(contractBalances.postBToken, 0);
                assertApproxEqAbs(
                    contractBalances.postVDToken, contractBalances.preVDToken - repayData.repayAmtInDToken, 1
                );
                assertApproxEqAbs(
                    contractBalances.postCAToken, contractBalances.preCAToken - _withdrawCAmt - _withdrawBAmt, 1
                );
                assertEq(contractBalances.postBAToken, contractBalances.postCAToken);
                assertEq(gains, 0);
                assertEq(ownerBalances.postBToken, ownerBalances.postCToken);
                assertEq(ownerBalances.postCToken, ownerBalances.preCToken + _withdrawCAmt);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }
}

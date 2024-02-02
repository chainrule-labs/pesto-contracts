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
    PROFIT_PERCENT,
    REPAY_PERCENT,
    SWAP_ROUTER,
    TEST_CLIENT,
    TEST_POOL_FEE,
    USDC,
    WITHDRAW_BUFFER
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { MockUniswapGains, MockUniswapLosses } from "test/mocks/MockUniswap.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionCloseTest is Test, TokenUtils, DebtUtils {
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

    /// @dev
    // - Position contract's bToken balance should go to 0.
    // - Position contract's debt on Aave should go to 0.
    // - Owner's cToken balance should increase by the amount of collateral withdrawn.
    // - Owner's bToken balance should increase by the position's gains amount.
    // - The above should be true for all supported tokens.
    function test_CloseWithGainsExactOutput() public {
        // Setup
        ContractBalances memory contractBalances;
        OwnerBalances memory ownerBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;

            // Setup: open position
            uint256 cAmt = assets.maxCAmts(positions[i].cToken);
            uint256 ltv = 50;
            _fund(owner, positions[i].cToken, cAmt);
            IERC20(positions[i].cToken).approve(addr, cAmt);
            IPosition(addr).add(cAmt, ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

            // Get pre-act balances
            contractBalances.preBToken = IERC20(positions[i].bToken).balanceOf(addr);
            contractBalances.preVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.preAToken = _getATokenBalance(addr, positions[i].cToken);
            ownerBalances.preBToken = IERC20(positions[i].bToken).balanceOf(owner);
            ownerBalances.preCToken = IERC20(positions[i].cToken).balanceOf(owner);

            // Assertions
            assertEq(ownerBalances.preBToken, 0);
            assertNotEq(contractBalances.preBToken, 0);
            assertNotEq(contractBalances.preVDToken, 0);

            // Mock Uniswap to ensure position gains
            _fund(SWAP_ROUTER, positions[i].dToken, contractBalances.preVDToken);
            bytes memory code = address(new MockUniswapGains()).code;
            vm.etch(SWAP_ROUTER, code);

            // Act
            /// @dev start event recorder
            vm.recordLogs();
            IPosition(addr).close(3000, true, 0, WITHDRAW_BUFFER);
            VmSafe.Log[] memory entries = vm.getRecordedLogs();

            // Get post-act balances
            contractBalances.postBToken = IERC20(positions[i].bToken).balanceOf(addr);
            contractBalances.postVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.postAToken = _getATokenBalance(addr, positions[i].cToken);
            ownerBalances.postBToken = IERC20(positions[i].bToken).balanceOf(owner);
            ownerBalances.postCToken = IERC20(positions[i].cToken).balanceOf(owner);

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
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken + gains + contractBalances.preAToken);
                assertEq(ownerBalances.postCToken, ownerBalances.postBToken);
            } else {
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken + gains);
                assertEq(ownerBalances.postCToken, ownerBalances.preCToken + contractBalances.preAToken);
            }

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - Position contract's bToken balance should go to 0.
    // - Position contract's debt on Aave should go to 0.
    // - Position contract's dToken balance should be the amount received from swap minus the amount repaid to Aave.
    // - Owner's cToken balance should increase by the amount of collateral withdrawn.
    // - Owner's bToken balance should stay the same, as there are no gains.
    // - The above should be true for all supported tokens.
    function testFuzz_CloseWithGainsExactInput(uint256 _dAmtRemainder) public {
        // Setup
        ContractBalances memory contractBalances;
        OwnerBalances memory ownerBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;

            // Setup: open position
            uint256 cAmt = assets.maxCAmts(positions[i].cToken);
            uint256 ltv = 50;
            _fund(owner, positions[i].cToken, cAmt);
            IERC20(positions[i].cToken).approve(addr, cAmt);
            IPosition(addr).add(cAmt, ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

            // Get pre-act balances
            contractBalances.preBToken = IERC20(positions[i].bToken).balanceOf(addr);
            contractBalances.preVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.preAToken = _getATokenBalance(addr, positions[i].cToken);
            contractBalances.preDToken = IERC20(positions[i].dToken).balanceOf(addr);
            ownerBalances.preBToken = IERC20(positions[i].bToken).balanceOf(owner);
            ownerBalances.preCToken = IERC20(positions[i].cToken).balanceOf(owner);

            // Assertions
            assertEq(ownerBalances.preBToken, 0);
            assertEq(contractBalances.preDToken, 0);
            assertNotEq(contractBalances.preBToken, 0);
            assertNotEq(contractBalances.preVDToken, 0);

            // Bound: upper bound is 150% of preVDToken
            uint256 upperBound = contractBalances.preVDToken + (contractBalances.preVDToken * 50) / 100;
            _dAmtRemainder = bound(_dAmtRemainder, 2, upperBound);

            // Mock Uniswap to ensure position gains
            uint256 amountOut = contractBalances.preVDToken + _dAmtRemainder;
            _fund(SWAP_ROUTER, positions[i].dToken, contractBalances.preVDToken + _dAmtRemainder);
            bytes memory code = address(new MockUniswapGains()).code;
            vm.etch(SWAP_ROUTER, code);

            // Act
            /// @dev start event recorder
            vm.recordLogs();
            IPosition(addr).close(3000, false, 0, WITHDRAW_BUFFER);
            VmSafe.Log[] memory entries = vm.getRecordedLogs();

            // Get post-act balances
            contractBalances.postBToken = IERC20(positions[i].bToken).balanceOf(addr);
            contractBalances.postVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.postAToken = _getATokenBalance(addr, positions[i].cToken);
            contractBalances.postDToken = IERC20(positions[i].dToken).balanceOf(addr);
            ownerBalances.postBToken = IERC20(positions[i].bToken).balanceOf(owner);
            ownerBalances.postCToken = IERC20(positions[i].cToken).balanceOf(owner);

            bytes memory closeEvent = entries[entries.length - 1].data;
            uint256 gains;

            assembly {
                gains := mload(add(closeEvent, 0x20))
            }

            // Assertions:
            assertApproxEqAbs(contractBalances.postDToken, amountOut - contractBalances.preVDToken, 1);
            assertEq(contractBalances.postBToken, 0);
            assertEq(contractBalances.postVDToken, 0);
            assertEq(contractBalances.postAToken, 0);
            assertEq(gains, 0);

            if (positions[i].bToken == positions[i].cToken) {
                /// @dev In this case, bToken and cToken balances will increase by the same amount (collateral withdrawn)
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken + contractBalances.preAToken);
                assertEq(ownerBalances.postCToken, ownerBalances.postBToken);
            } else {
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken);
                assertEq(ownerBalances.postCToken, ownerBalances.preCToken + contractBalances.preAToken);
            }

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - Position contract's bToken balance should go to 0.
    // - Position contract's debt on Aave should decrease by the amount received from the swap.
    // - Owner's cToken balance should increase by the amount of collateral withdrawn.
    // - If bToken != cToken, the owner's bToken balance should not increase.
    // - The above should be true for all supported tokens.
    function test_CloseNoGainsExactInput() public {
        // Setup
        ContractBalances memory contractBalances;
        OwnerBalances memory ownerBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;

            // Setup: open position
            uint256 cAmt = assets.maxCAmts(positions[i].cToken);
            uint256 ltv = 50;
            _fund(owner, positions[i].cToken, cAmt);
            IERC20(positions[i].cToken).approve(addr, cAmt);
            IPosition(addr).add(cAmt, ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

            // Get pre-act balances
            contractBalances.preBToken = IERC20(positions[i].bToken).balanceOf(addr);
            contractBalances.preVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.preAToken = _getATokenBalance(addr, positions[i].cToken);
            ownerBalances.preBToken = IERC20(positions[i].bToken).balanceOf(owner);
            ownerBalances.preCToken = IERC20(positions[i].cToken).balanceOf(owner);

            // Assertions
            assertEq(ownerBalances.preBToken, 0);
            assertNotEq(contractBalances.preBToken, 0);
            assertNotEq(contractBalances.preVDToken, 0);

            // Mock Uniswap to ensure position gains
            uint256 repayAmt = contractBalances.preVDToken * REPAY_PERCENT / 100;
            _fund(SWAP_ROUTER, positions[i].dToken, repayAmt);
            bytes memory code = address(new MockUniswapLosses()).code;
            vm.etch(SWAP_ROUTER, code);

            // Act
            IPosition(addr).close(3000, false, 0, WITHDRAW_BUFFER);

            // Get post-act balances
            contractBalances.postBToken = IERC20(positions[i].bToken).balanceOf(addr);
            contractBalances.postVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);
            contractBalances.postAToken = _getATokenBalance(addr, positions[i].cToken);
            ownerBalances.postBToken = IERC20(positions[i].bToken).balanceOf(owner);
            ownerBalances.postCToken = IERC20(positions[i].cToken).balanceOf(owner);

            // Assertions
            assertApproxEqAbs(
                contractBalances.postVDToken, contractBalances.preVDToken * (100 - REPAY_PERCENT) / 100, 1
            );
            assertApproxEqAbs(contractBalances.postVDToken, contractBalances.preVDToken - repayAmt, 1);
            assertEq(contractBalances.postBToken, 0);
            uint256 withdrawAmt = contractBalances.preAToken - contractBalances.postAToken;
            assertApproxEqAbs(ownerBalances.postCToken, ownerBalances.preCToken + withdrawAmt, 1);
            if (positions[i].bToken == positions[i].cToken) {
                /// @dev In this case, bToken and cToken balances will increase by the same amount (the collateral amount withdrawn)
                assertEq(ownerBalances.postBToken, ownerBalances.postCToken);
            } else {
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken);
            }

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - It should revert because the position contract doesn't have enough bTokens to facilitate the exact output swap.
    function testFail_CloseNoGainsExactOutput() public {
        // Setup
        ContractBalances memory contractBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;

            // Setup: open position
            uint256 cAmt = assets.maxCAmts(positions[i].cToken);
            uint256 ltv = 50;
            _fund(owner, positions[i].cToken, cAmt);
            IERC20(positions[i].cToken).approve(addr, cAmt);
            IPosition(addr).add(cAmt, ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

            // Get pre-act balances
            contractBalances.preVDToken = _getVariableDebtTokenBalance(addr, positions[i].dToken);

            // Mock Uniswap to ensure position gains
            uint256 repayAmt = contractBalances.preVDToken * REPAY_PERCENT / 100;
            _fund(SWAP_ROUTER, positions[i].dToken, repayAmt);
            bytes memory code = address(new MockUniswapLosses()).code;
            vm.etch(SWAP_ROUTER, code);

            // Act
            IPosition(addr).close(3000, true, 0, WITHDRAW_BUFFER);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }
}

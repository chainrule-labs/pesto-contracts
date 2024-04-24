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
    PROFIT_PERCENT,
    PROTOCOL_FEE_RATE,
    SWAP_ROUTER,
    TEST_CLIENT,
    TEST_LTV,
    TEST_POOL_FEE,
    USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { MockUniswapGains } from "test/mocks/MockUniswap.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionReduceGainsTest is Test, TokenUtils, DebtUtils {
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

    /// @dev
    // - Position contract's (bToken) AToken balance should go to 0 (full withdraw).
    // - Position contract's (cToken) AToken balance should go to 0 (full withdraw).
    // - Position contract's bToken balance should remain 0.
    // - Position contract's debt on Aave should go to 0.
    // - Position gains should be equal to the supplied base token amount times profit percent (uniswap mock takes 1 - PROFIT_PERCENT of input tokens).
    // - Owner's cToken balance should increase by the amount of collateral withdrawn.
    // - Owner's bToken balance should increase by the position's gains amount.
    // - The above should be true for all supported tokens.
    function test_ReduceExactOutputDiffCAndB() public {
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
                contractBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.preBAToken = _getATokenBalance(p.addr, p.bToken);
                ownerBalances.preBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.preCToken = IERC20(p.cToken).balanceOf(owner);

                // Assertions
                assertEq(ownerBalances.preBToken, 0);
                assertEq(contractBalances.preBToken, 0);
                assertNotEq(contractBalances.preVDToken, 0);
                assertNotEq(contractBalances.preCAToken, 0);
                assertNotEq(contractBalances.preBAToken, 0);

                // Mock Uniswap to ensure position gains
                _fund(SWAP_ROUTER, p.dToken, contractBalances.preVDToken);
                bytes memory code = address(new MockUniswapGains()).code;
                vm.etch(SWAP_ROUTER, code);

                // Act
                /// @dev start event recorder
                vm.recordLogs();
                /// @dev since profitable, withdrawCAmt is max int and withdrawBAmt is its (base) AToken balance
                IPosition(p.addr).reduce(TEST_POOL_FEE, true, 0, type(uint256).max, contractBalances.preBAToken);
                VmSafe.Log[] memory entries = vm.getRecordedLogs();

                // Get post-act balances
                contractBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
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

                // Assertions:
                assertEq(contractBalances.postBToken, 0);
                assertEq(contractBalances.postVDToken, 0);
                assertEq(contractBalances.postCAToken, 0);
                assertEq(contractBalances.postBAToken, 0);
                /// @dev Uniswap mock takes (1 - PROFIT_PERCENT)% of the input token balance
                //       at the time it's called, leaving PROFIT_PERCENT on the contract.
                assertApproxEqAbs(gains, contractBalances.preBAToken * PROFIT_PERCENT / 100, 1);
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken + gains);
                assertEq(ownerBalances.postCToken, ownerBalances.preCToken + contractBalances.preCAToken);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }

    /// @dev
    // - Position contract's (cToken) AToken balance should go to 0 (full withdraw).
    // - Position contract's (bToken) AToken balance should equal its (cToken) AToken balance.
    // - Position contract's bToken balance should remain 0.
    // - Position contract's debt on Aave should go to 0.
    // - Position gains should be equal to the supplied base token amount times profit percent (uniswap mock takes 1 - PROFIT_PERCENT of input tokens).
    // - Owner's cToken balance should increase by (collateral withdrawn + position's gains).
    // - Owner's bToken balance should equal its cToken balance.
    // - The above should be true for all supported tokens.
    function test_ReduceExactOutputSameCAndB() public {
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
                contractBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.preBAToken = _getATokenBalance(p.addr, p.bToken);
                ownerBalances.preBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.preCToken = IERC20(p.cToken).balanceOf(owner);

                // Assertions
                assertEq(ownerBalances.preBToken, 0);
                assertEq(contractBalances.preBToken, 0);
                assertNotEq(contractBalances.preVDToken, 0);
                assertNotEq(contractBalances.preCAToken, 0);
                assertEq(contractBalances.preBAToken, contractBalances.preCAToken);

                // Mock Uniswap to ensure position gains
                _fund(SWAP_ROUTER, p.dToken, contractBalances.preVDToken);
                bytes memory code = address(new MockUniswapGains()).code;
                vm.etch(SWAP_ROUTER, code);

                // Act
                /// @dev since profitable, withdrawCAmt is max int and withdrawBAmt is its (base) AToken balance
                IPosition(p.addr).reduce(TEST_POOL_FEE, true, 0, type(uint256).max, suppliedBAmt);
                entries = vm.getRecordedLogs();

                // Get post-act balances
                contractBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
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

                // Assertions:
                assertEq(contractBalances.postBToken, 0);
                assertEq(contractBalances.postVDToken, 0);
                assertEq(contractBalances.postCAToken, 0);
                assertEq(contractBalances.postBAToken, contractBalances.postCAToken);
                /// @dev Uniswap mock takes (1 - PROFIT_PERCENT)% of the input token balance
                //       at the time it's called, leaving PROFIT_PERCENT on the contract.
                assertApproxEqAbs(gains, suppliedBAmt * PROFIT_PERCENT / 100, 1);
                /// @dev In this case, bToken and cToken balances will increase by the
                //       same amount (gains + collateral withdrawn - suppliedBAmt).
                assertApproxEqAbs(
                    ownerBalances.postBToken,
                    ownerBalances.preBToken + gains + (contractBalances.preCAToken - suppliedBAmt),
                    1
                );
                assertEq(ownerBalances.postCToken, ownerBalances.postBToken);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }

    /// @dev: Simulates reduction where all B_TOKEN is withdrawn and swapped for D_TOKEN,
    //        where D_TOKEN amount is greater than total debt.
    // - Position contract's (bToken) AToken balance should go to 0 (full withdraw).
    // - Position contract's (cToken) AToken balance should go to 0 (full withdraw).
    ///  @notice If B_TOKEN withdraw value > debt value, there will be left over D_TOKEN on the position contract.
    // - Position contract's dToken balance should be (swap dAmtOut - debt repayment).
    // - Position contract's bToken balance should remain 0.
    // - Position contract's debt on Aave should go to 0.
    // - Owner's cToken balance should increase by the amount of collateral withdrawn.
    // - Owner's bToken balance should stay the same, as gains will be in debt token if exactInput is called.
    // - The above should be true for all supported tokens.
    function testFuzz_ReduceFullExactInputDiffCAndB(uint256 _dAmtRemainder) public {
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
                uint256 cAmt = assets.maxCAmts(p.cToken);
                _fund(owner, p.cToken, cAmt);
                IERC20(p.cToken).approve(p.addr, cAmt);
                IPosition(p.addr).add(cAmt, TEST_LTV, 0, TEST_POOL_FEE, TEST_CLIENT);

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

                // Bound: upper bound is 150% of preVDToken
                uint256 upperBound = contractBalances.preVDToken + (contractBalances.preVDToken * 50) / 100;
                _dAmtRemainder = bound(_dAmtRemainder, 2, upperBound);

                // Mock Uniswap to ensure position gains
                uint256 amountOut = contractBalances.preVDToken + _dAmtRemainder;
                _fund(SWAP_ROUTER, p.dToken, amountOut);
                bytes memory code = address(new MockUniswapGains()).code;
                vm.etch(SWAP_ROUTER, code);

                // Act
                /// @dev start event recorder
                vm.recordLogs();
                IPosition(p.addr).reduce(TEST_POOL_FEE, false, 0, type(uint256).max, contractBalances.preBAToken);
                VmSafe.Log[] memory entries = vm.getRecordedLogs();

                // Get post-act balances
                contractBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                contractBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                contractBalances.postDToken = IERC20(p.dToken).balanceOf(p.addr);
                ownerBalances.postBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.postCToken = IERC20(p.cToken).balanceOf(owner);

                bytes memory reduceEvent = entries[entries.length - 1].data;
                uint256 gains;

                assembly {
                    gains := mload(add(reduceEvent, 0x20))
                }

                // Assertions:
                assertApproxEqAbs(contractBalances.postDToken, amountOut - contractBalances.preVDToken, 1);
                assertEq(contractBalances.postBToken, 0);
                assertEq(contractBalances.postVDToken, 0);
                assertEq(contractBalances.postCAToken, 0);
                assertEq(contractBalances.postBAToken, 0);
                assertEq(gains, 0);
                assertEq(ownerBalances.postBToken, ownerBalances.preBToken);
                assertEq(ownerBalances.postCToken, ownerBalances.preCToken + contractBalances.preCAToken);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }

    /// @dev Tests that the reduce function works when the position has gains and collateral token and base token are the same.
    /// @notice Test strategy:
    // - 1. Open a position. In doing so, extract the amount of base token added to Aave.
    // - 2. Mock Uniswap to ensure position gains.
    // - 3. Reduce the position, such that all B_TOKEN is withdrawn and all C_TOKEN is withdrawn.

    /// @notice Assertions:
    // - Position contract's (bToken) AToken balance should go to 0 (full withdraw).
    // - Position contract's (cToken) AToken balance should go to 0 (full withdraw).
    // - Position contract's dToken balance should be the amount received from swap minus the amount repaid to Aave.
    // - Position contract's bToken balance should remain 0.
    // - Position contract's debt on Aave should go to 0.
    // - Owner's cToken balance should increase by the amount of collateral withdrawn.
    // - Owner's bToken balance should increase by the amount of collateral withdrawn.
    // - The above should be true for all supported tokens.
    function testFuzz_ReduceExactInputSameCAndB(uint256 _dAmtRemainder) public {
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
                assertEq(contractBalances.preBToken, 0);
                assertNotEq(contractBalances.preVDToken, 0);
                assertNotEq(contractBalances.preCAToken, 0);
                assertEq(contractBalances.preBAToken, contractBalances.preCAToken);

                // Bound: upper bound is 150% of preVDToken
                uint256 upperBound = contractBalances.preVDToken + (contractBalances.preVDToken * 50) / 100;
                _dAmtRemainder = bound(_dAmtRemainder, 2, upperBound);

                // Mock Uniswap to ensure position gains
                uint256 amountOut = contractBalances.preVDToken + _dAmtRemainder;
                _fund(SWAP_ROUTER, p.dToken, contractBalances.preVDToken + _dAmtRemainder);
                bytes memory code = address(new MockUniswapGains()).code;
                vm.etch(SWAP_ROUTER, code);

                // Act
                IPosition(p.addr).reduce(TEST_POOL_FEE, false, 0, type(uint256).max, suppliedBAmt);
                entries = vm.getRecordedLogs();

                // Get post-act balances
                contractBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                contractBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                contractBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                contractBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                contractBalances.postDToken = IERC20(p.dToken).balanceOf(p.addr);
                ownerBalances.postBToken = IERC20(p.bToken).balanceOf(owner);
                ownerBalances.postCToken = IERC20(p.cToken).balanceOf(owner);

                bytes memory reduceEvent = entries[entries.length - 1].data;
                uint256 gains;

                assembly {
                    gains := mload(add(reduceEvent, 0x20))
                }

                // Assertions:
                assertApproxEqAbs(contractBalances.postDToken, amountOut - contractBalances.preVDToken, 1);
                assertEq(contractBalances.postBToken, 0);
                assertEq(contractBalances.postVDToken, 0);
                assertEq(contractBalances.postCAToken, 0);
                assertEq(contractBalances.postBAToken, 0);
                assertEq(gains, 0);
                /// @dev In this case, bToken and cToken balances will increase by the same amount (collateral withdrawn - suppliedBAmt)
                //       Gains will be in debt token if exactInput is called.
                assertApproxEqAbs(
                    ownerBalances.postBToken, ownerBalances.preBToken + (contractBalances.preCAToken - suppliedBAmt), 1
                );
                assertEq(ownerBalances.postCToken, ownerBalances.postBToken);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }
}

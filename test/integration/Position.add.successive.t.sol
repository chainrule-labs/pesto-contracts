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
    CLIENT_RATE,
    CLIENT_TAKE_RATE,
    CONTRACT_DEPLOYER,
    DAI,
    FEE_COLLECTOR,
    SUCCESSIVE_ITERATIONS,
    TEST_CLIENT,
    TEST_POOL_FEE,
    USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { FeeUtils } from "test/common/utils/FeeUtils.t.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionAddSuccessiveTest is Test, TokenUtils, DebtUtils, FeeUtils {
    /* solhint-disable func-name-mixedcase */

    struct TestPosition {
        address addr;
        address cToken;
        address dToken;
        address bToken;
    }

    struct PositionBalances {
        uint256 preBToken;
        uint256 postBToken;
        uint256 preVDToken;
        uint256 postVDToken;
        uint256 preCAToken;
        uint256 preBAToken;
        uint256 postCAToken;
        uint256 postBAToken;
    }

    struct OwnerBalances {
        uint256 preCToken;
        uint256 postCToken;
    }

    struct FeeData {
        uint256 maxFee;
        uint256 userSavings;
        uint256 protocolFee;
    }

    struct SuccessiveSums {
        uint256 cAmt;
        uint256 dAmt;
        uint256 bAmt;
    }

    struct LoanData {
        uint256 debtBeforeTimeDelta;
        uint256 debtAfterTimeDelta;
        uint256 debtInterest;
        uint256 colBeforeTimeDelta;
        uint256 colAfterTimeDelta;
        uint256 colInterest;
        uint256 baseBeforeTimeDelta;
        uint256 baseAfterTimeDelta;
        uint256 baseInterest;
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

        // Set client rate
        vm.prank(CONTRACT_DEPLOYER);
        IFeeCollector(FEE_COLLECTOR).setClientRate(CLIENT_RATE);

        // Set client take rate
        vm.prank(TEST_CLIENT);
        IFeeCollector(FEE_COLLECTOR).setClientTakeRate(CLIENT_TAKE_RATE);

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

    /// @dev Tests that add function works successively over varying time deltas
    //       when the collateral token and base token are different.
    /// @notice Test strategy:
    // - 1. Add to a position 5 times over time deltas.
    // - 2. Accound for interest on debt, collateral, and base tokens over each delta.
    // - 3. The emprically-derived max time delta is 4 weeks. Longer time detlas cause
    //      more interest on debt. More debt affects ability to borrow.

    /// @notice Assertions:
    // - The Position contract's (B_TOKEN) aToken balance on Aave should increase
    //   by the sum of bAmt's receieved from swaps across all add actions.
    // - The Position contract's (C_TOKEN) aToken balance should increase by
    //   the sum of emitted cAmt's across all add actions.
    // - The Position contract's variableDebtToken balance should increase by
    //   the sum of dAmt's received from borrowing across all add actions.
    // - The Position contract's B_TOKEN balance should remain 0.
    // - The above should be true for a wide range of LTVs.
    // - The above should be true for a wide range of collateral amounts.
    // - The above should be true for all supported tokens.
    function testFuzz_AddSuccessiveDiffCAndB(uint256 _ltv, uint256 _cAmt, uint256 _time) public {
        // Setup
        PositionBalances memory positionBalances;
        TestPosition memory p;
        SuccessiveSums memory sums;
        LoanData memory loanData;

        // Take snapshot
        uint256 id = vm.snapshot();

        /// @dev Test each position
        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken != p.bToken) {
                sums.cAmt = 0;
                sums.dAmt = 0;
                sums.bAmt = 0;
                loanData.debtBeforeTimeDelta = 0;
                loanData.debtAfterTimeDelta = 0;
                loanData.debtInterest = 0;
                loanData.colBeforeTimeDelta = 0;
                loanData.colAfterTimeDelta = 0;
                loanData.colInterest = 0;
                loanData.baseBeforeTimeDelta = 0;
                loanData.baseAfterTimeDelta = 0;
                loanData.baseInterest = 0;
                for (uint256 j; j < SUCCESSIVE_ITERATIONS; j++) {
                    // Bound fuzzed variables
                    _ltv = bound(_ltv, 1, 60);
                    _cAmt = bound(_cAmt, assets.minCAmts(p.cToken), assets.maxCAmts(p.cToken));
                    _time = bound(_time, 1 minutes, 4 weeks);

                    // Fund owner with collateral
                    _fund(owner, p.cToken, _cAmt);

                    // Approve Position contract to spend collateral
                    IERC20(p.cToken).approve(p.addr, _cAmt);

                    // Act
                    vm.recordLogs();
                    IPosition(p.addr).add(_cAmt, _ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

                    // Retrieve bAmt and dAmt from Add event
                    VmSafe.Log[] memory entries = vm.getRecordedLogs();
                    bytes memory addEvent = entries[entries.length - 1].data;
                    uint256 netCAmt;
                    uint256 dAmt;
                    uint256 bAmt;
                    assembly {
                        netCAmt := mload(add(addEvent, 0x20))
                        dAmt := mload(add(addEvent, 0x40))
                        bAmt := mload(add(addEvent, 0x60))
                    }

                    // Sum successive adds
                    sums.cAmt += (netCAmt + loanData.colInterest);
                    sums.dAmt += (dAmt + loanData.debtInterest);
                    sums.bAmt += (bAmt + loanData.baseInterest);

                    // Introduce time delta between successive adds
                    if (j != SUCCESSIVE_ITERATIONS - 1) {
                        loanData.debtBeforeTimeDelta = _getVariableDebtTokenBalance(p.addr, p.dToken);
                        loanData.colBeforeTimeDelta = _getATokenBalance(p.addr, p.cToken);
                        loanData.baseBeforeTimeDelta = _getATokenBalance(p.addr, p.bToken);
                        skip(_time);
                        loanData.debtAfterTimeDelta = _getVariableDebtTokenBalance(p.addr, p.dToken);
                        loanData.colAfterTimeDelta = _getATokenBalance(p.addr, p.cToken);
                        loanData.baseAfterTimeDelta = _getATokenBalance(p.addr, p.bToken);
                        loanData.debtInterest = loanData.debtAfterTimeDelta - loanData.debtBeforeTimeDelta;
                        loanData.colInterest = loanData.colAfterTimeDelta - loanData.colBeforeTimeDelta;
                        loanData.baseInterest = loanData.baseAfterTimeDelta - loanData.baseBeforeTimeDelta;
                    }
                }

                // Post-act balances
                positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                positionBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);

                // Assertions
                /// @dev Due to Aave interest, the max delta per iteration is 1.
                //  Therefore, the max delta for all iterations is the number of iterations.
                assertApproxEqAbs(positionBalances.postBAToken, sums.bAmt, SUCCESSIVE_ITERATIONS);
                assertApproxEqAbs(positionBalances.postCAToken, sums.cAmt, SUCCESSIVE_ITERATIONS);
                assertApproxEqAbs(positionBalances.postVDToken, sums.dAmt, SUCCESSIVE_ITERATIONS);
                assertEq(positionBalances.postBToken, 0);

                // Revert to snapshot to standardize chain state for each position
                vm.revertTo(id);
            }
        }
    }

    /// @dev Tests that add function works successively over varying time deltas
    //       when the collateral token and base token are the same.
    /// @notice Test strategy:
    // - 1. Add to a position 5 times over time deltas.
    // - 2. Accound for interest on debt, collateral, and base tokens over each delta.
    // - 3. The emprically-derived max time delta is 4 weeks. Longer time detlas cause
    //      more interest on debt. More debt affects ability to borrow.

    /// @notice Assertions:
    // - The Position contract's (C_TOKEN) aToken balance on Aave should increase by sum(bAmts) + sum(emitted cAmts),
    //   where bAmt is the amount received from swap and cAmt is the amount emitted from add.
    //   by the sum of bAmt's receieved from swaps across all add actions
    // - The Position contract's (B_TOKEN) aToken balance should equal its (C_TOKEN) aToken balance.
    // - The Position contract's variableDebtToken balance should increase by
    //   the sum of dAmt's received from borrowing across all add actions.
    // - The Position contract's B_TOKEN balance should remain 0.
    // - The above should be true for a wide range of LTVs.
    // - The above should be true for a wide range of collateral amounts.
    // - The above should be true for all supported tokens.
    function testFuzz_AddSuccessiveSameCAndB(uint256 _ltv, uint256 _cAmt, uint256 _time) public {
        // Setup
        PositionBalances memory positionBalances;
        TestPosition memory p;
        SuccessiveSums memory sums;
        LoanData memory loanData;

        // Take snapshot
        uint256 id = vm.snapshot();

        /// @dev Test each position
        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken == p.bToken) {
                sums.cAmt = 0;
                sums.dAmt = 0;
                loanData.debtBeforeTimeDelta = 0;
                loanData.debtAfterTimeDelta = 0;
                loanData.debtInterest = 0;
                loanData.colBeforeTimeDelta = 0;
                loanData.colAfterTimeDelta = 0;
                loanData.colInterest = 0;
                for (uint256 j; j < SUCCESSIVE_ITERATIONS; j++) {
                    // Bound fuzzed variables
                    _ltv = bound(_ltv, 1, 60);
                    _cAmt = bound(_cAmt, assets.minCAmts(p.cToken), assets.maxCAmts(p.cToken));
                    _time = bound(_time, 1 minutes, 4 weeks);

                    // Fund owner with collateral
                    _fund(owner, p.cToken, _cAmt);

                    // Approve Position contract to spend collateral
                    IERC20(p.cToken).approve(p.addr, _cAmt);

                    // Act
                    vm.recordLogs();
                    IPosition(p.addr).add(_cAmt, _ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

                    // Retrieve bAmt and dAmt from Add event
                    VmSafe.Log[] memory entries = vm.getRecordedLogs();
                    bytes memory addEvent = entries[entries.length - 1].data;
                    uint256 netCAmt;
                    uint256 dAmt;
                    uint256 bAmt;
                    assembly {
                        netCAmt := mload(add(addEvent, 0x20))
                        dAmt := mload(add(addEvent, 0x40))
                        bAmt := mload(add(addEvent, 0x60))
                    }

                    // Sum successive adds
                    /// @dev added cAmt is bAmt + netCamt, as B_TOKEN and C_TOKEN are the same
                    sums.cAmt += (bAmt + netCAmt + loanData.colInterest);
                    sums.dAmt += (dAmt + loanData.debtInterest);

                    // Introduce time delta between successive adds
                    if (j != SUCCESSIVE_ITERATIONS - 1) {
                        loanData.debtBeforeTimeDelta = _getVariableDebtTokenBalance(p.addr, p.dToken);
                        loanData.colBeforeTimeDelta = _getATokenBalance(p.addr, p.cToken);
                        skip(_time);
                        loanData.debtAfterTimeDelta = _getVariableDebtTokenBalance(p.addr, p.dToken);
                        loanData.colAfterTimeDelta = _getATokenBalance(p.addr, p.cToken);
                        loanData.debtInterest = loanData.debtAfterTimeDelta - loanData.debtBeforeTimeDelta;
                        loanData.colInterest = loanData.colAfterTimeDelta - loanData.colBeforeTimeDelta;
                    }
                }

                // Post-act balances
                positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                positionBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);

                // Assertions
                /// @dev Due to Aave interest, the max delta per iteration is 1.
                //  Therefore, the max delta for all iterations is the number of iterations.
                assertApproxEqAbs(positionBalances.postCAToken, sums.cAmt, SUCCESSIVE_ITERATIONS);
                assertEq(positionBalances.postBAToken, positionBalances.postCAToken);
                assertApproxEqAbs(positionBalances.postVDToken, sums.dAmt, SUCCESSIVE_ITERATIONS);
                assertEq(positionBalances.postBToken, 0);

                assertTrue(true);

                // Revert to snapshot to standardize chain state for each position
                vm.revertTo(id);
            }
        }
    }
}

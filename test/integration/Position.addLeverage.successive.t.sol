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
    CLIENT_RATE,
    CLIENT_TAKE_RATE,
    CONTRACT_DEPLOYER,
    DAI,
    FEE_COLLECTOR,
    PROTOCOL_FEE_RATE,
    SUCCESSIVE_ITERATIONS,
    TEST_CLIENT,
    TEST_POOL_FEE,
    USDC,
    WBTC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IPool } from "src/interfaces/aave/IPool.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";

contract PositionAddLeverageSuccessiveTest is Test, TokenUtils, DebtUtils {
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
        uint256 totalColInterest;
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

    /// @dev Tests that addLeverage function works successively when the collateral token and base token are different.
    // - The Position contract's (B_TOKEN) aToken balance after adding leverage should equal bAmt received from swap across all addLeverage actions.
    // - The Position contract's (C_TOKEN) aToken balance should remain unchanged.
    // - The Position contract's variable debt token balance should increase by dAmt received from borrow across all add actions
    // - The above should be true for a large range of LTVs and cAmts.
    // - The above should be true for all positions where the collateral token is the same as the base token.
    function testFuzz_AddLeverageSuccessiveDiffCAndB(uint256 _ltv, uint256 _dAmt, uint256 _time) public {
        // Setup
        PositionBalances memory positionBalances;
        TestPosition memory p;
        SuccessiveSums memory sums;
        LoanData memory loanData;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken != p.bToken) {
                // Bound fuzzed variables
                _ltv = bound(_ltv, 1, 60);

                // Open position
                _fund(owner, p.cToken, assets.maxCAmts(p.cToken));
                IERC20(p.cToken).approve(p.addr, assets.maxCAmts(p.cToken));
                IPosition(p.addr).add(assets.maxCAmts(p.cToken), _ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

                // Pre-act balances
                positionBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);

                /// @dev Initial balances to refect inital add
                sums.dAmt = _getVariableDebtTokenBalance(p.addr, p.dToken);
                sums.bAmt = _getATokenBalance(p.addr, p.bToken);
                loanData.debtBeforeTimeDelta = 0;
                loanData.debtAfterTimeDelta = 0;
                loanData.debtInterest = 0;
                loanData.colBeforeTimeDelta = 0;
                loanData.colAfterTimeDelta = 0;
                loanData.colInterest = 0;
                loanData.baseBeforeTimeDelta = 0;
                loanData.baseAfterTimeDelta = 0;
                loanData.baseInterest = 0;
                loanData.totalColInterest = 0;

                bool shallowLiquidity = (p.bToken == DAI && p.dToken == WBTC) || (p.bToken == WBTC && p.dToken == DAI);
                if (!shallowLiquidity) {
                    for (uint256 j; j < SUCCESSIVE_ITERATIONS; j++) {
                        // Bound fuzzed variables
                        _time = bound(_time, 1 minutes, 4 weeks);

                        // Get max borrow
                        _dAmt = bound(
                            _dAmt, assets.minDAmts(p.dToken), _getMaxBorrow(p.addr, p.dToken, assets.decimals(p.dToken))
                        );

                        // Act
                        vm.recordLogs();
                        IPosition(p.addr).addLeverage(_dAmt, 0, TEST_POOL_FEE, TEST_CLIENT);

                        // Retrieve bAmt and dAmt from AddLeverage event
                        VmSafe.Log[] memory entries = vm.getRecordedLogs();
                        bytes memory addLeverageEvent = entries[entries.length - 1].data;
                        uint256 netCAmt;
                        uint256 bAmt;
                        assembly {
                            netCAmt := mload(add(addLeverageEvent, 0x20))
                            bAmt := mload(add(addLeverageEvent, 0x40))
                        }

                        // Sum successive adds
                        sums.cAmt += (netCAmt + loanData.colInterest);
                        sums.dAmt += (_dAmt + loanData.debtInterest);
                        sums.bAmt += (bAmt + loanData.baseInterest);

                        // Track total collateral interest
                        loanData.totalColInterest += loanData.colInterest;

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
                    positionBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                    positionBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                    positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                    positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);

                    // Assertions
                    /// @dev Due to Aave interest, the max delta per iteration is 1.
                    //  Therefore, the max delta for all iterations is the number of iterations.
                    assertApproxEqAbs(positionBalances.postBAToken, sums.bAmt, SUCCESSIVE_ITERATIONS);
                    assertEq(positionBalances.postCAToken, positionBalances.preCAToken + loanData.totalColInterest);
                    assertApproxEqAbs(positionBalances.postVDToken, sums.dAmt, SUCCESSIVE_ITERATIONS);
                    assertEq(positionBalances.postBToken, 0);
                }

                // Revert to snapshot to standardize chain state for each position
                vm.revertTo(id);
            }
        }
    }

    /// @dev Tests that addLeverage function works when the collateral token and base token are the same.
    // - The Position contract's (C_TOKEN) aToken should increase by equal bAmt received from swap across all addLeverage actions.
    // - The Position contract's (B_TOKEN) aToken balance should equal its (C_TOKEN) aToken balance.
    // - The Position contract's variable debt token balance should increase by dAmt received from borrow across all add actions
    // - The above should be true for a large range of LTVs and cAmts.
    // - The above should be true for all positions where the collateral token is the same as the base token.
    function testFuzz_AddLeverageSuccessiveSameCAndB(uint256 _ltv, uint256 _dAmt, uint256 _time) public {
        // Setup
        PositionBalances memory positionBalances;
        TestPosition memory p;
        SuccessiveSums memory sums;
        LoanData memory loanData;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken == p.bToken) {
                // Bound fuzzed variables
                _ltv = bound(_ltv, 1, 60);

                // Open position
                _fund(owner, p.cToken, assets.maxCAmts(p.cToken));
                IERC20(p.cToken).approve(p.addr, assets.maxCAmts(p.cToken));
                IPosition(p.addr).add(assets.maxCAmts(p.cToken), _ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

                // Pre-act balances
                positionBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);

                /// @dev Initial balances to refect inital add
                sums.dAmt = _getVariableDebtTokenBalance(p.addr, p.dToken);
                sums.bAmt = _getATokenBalance(p.addr, p.bToken);
                loanData.debtBeforeTimeDelta = 0;
                loanData.debtAfterTimeDelta = 0;
                loanData.debtInterest = 0;
                loanData.colBeforeTimeDelta = 0;
                loanData.colAfterTimeDelta = 0;
                loanData.colInterest = 0;
                loanData.baseBeforeTimeDelta = 0;
                loanData.baseAfterTimeDelta = 0;
                loanData.baseInterest = 0;
                loanData.totalColInterest = 0;

                bool shallowLiquidity = (p.bToken == DAI && p.dToken == WBTC) || (p.bToken == WBTC && p.dToken == DAI);
                if (!shallowLiquidity) {
                    for (uint256 j; j < SUCCESSIVE_ITERATIONS; j++) {
                        // Bound fuzzed variables
                        _time = bound(_time, 1 minutes, 4 weeks);

                        // Get max borrow
                        _dAmt = bound(
                            _dAmt, assets.minDAmts(p.dToken), _getMaxBorrow(p.addr, p.dToken, assets.decimals(p.dToken))
                        );

                        // Act
                        vm.recordLogs();
                        IPosition(p.addr).addLeverage(_dAmt, 0, TEST_POOL_FEE, TEST_CLIENT);

                        // Retrieve bAmt and dAmt from AddLeverage event
                        VmSafe.Log[] memory entries = vm.getRecordedLogs();
                        bytes memory addLeverageEvent = entries[entries.length - 1].data;
                        uint256 netCAmt;
                        uint256 bAmt;
                        assembly {
                            netCAmt := mload(add(addLeverageEvent, 0x20))
                            bAmt := mload(add(addLeverageEvent, 0x40))
                        }

                        // Sum successive adds
                        sums.cAmt += (netCAmt + loanData.colInterest);
                        sums.dAmt += (_dAmt + loanData.debtInterest);
                        sums.bAmt += (bAmt + loanData.baseInterest);

                        // Track total collateral interest
                        loanData.totalColInterest += loanData.colInterest;

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
                    positionBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                    positionBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                    positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                    positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);

                    // Assertions
                    /// @dev Due to Aave interest, the max delta per iteration is 1.
                    //  Therefore, the max delta for all iterations is the number of iterations.
                    assertApproxEqAbs(positionBalances.postCAToken, sums.bAmt, SUCCESSIVE_ITERATIONS);
                    assertEq(positionBalances.postBAToken, positionBalances.postCAToken);
                    assertApproxEqAbs(positionBalances.postVDToken, sums.dAmt, SUCCESSIVE_ITERATIONS);
                    assertEq(positionBalances.postBToken, 0);
                }

                // Revert to snapshot to standardize chain state for each position
                vm.revertTo(id);
            }
        }
    }
}

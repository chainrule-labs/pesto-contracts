// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import {
    Assets,
    AAVE_POOL,
    AAVE_ORACLE,
    CONTRACT_DEPLOYER,
    DAI,
    FEE_COLLECTOR,
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

contract PositionAddLeverageTest is Test, TokenUtils, DebtUtils {
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
        uint256 preAToken;
        uint256 postAToken;
        uint256 cTotalUSD;
        uint256 dTotalUSD;
    }

    struct SuccessiveSums {
        uint256 cAmt;
        uint256 dAmt;
    }

    struct LoanData {
        uint256 debtBeforeTimeDelta;
        uint256 debtAfterTimeDelta;
        uint256 debtInterest;
        uint256 colBeforeTimeDelta;
        uint256 colAfterTimeDelta;
        uint256 colInterest;
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
    // - The Position contract's bToken balance after adding leverage should equal bAmt (from swap).
    // - The Position contract's aToken balance should increase by its bToken balance before adding leverage.
    // - The Position contract's variable debt token balance should increase by dAmt (from borrow).
    // - The above should be true for a large range of LTVs and cAmts.
    function testFuzz_AddLeverage(uint256 _ltv, uint256 _cAmt) public {
        // Setup
        PositionBalances memory positionBalances;
        TestPosition memory p;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            // Bound fuzzed variables
            _ltv = bound(_ltv, 1, 60);
            _cAmt = bound(_cAmt, assets.minCAmts(p.cToken), assets.maxCAmts(p.cToken));

            // Fund owner with collateral
            _fund(owner, p.cToken, _cAmt);

            // Approve position to spend collateral
            IERC20(p.cToken).approve(p.addr, _cAmt);

            // Add initial position
            IPosition(p.addr).add(_cAmt, 50, 0, TEST_POOL_FEE, TEST_CLIENT);

            // Pre-act balances
            positionBalances.preBToken = IERC20(p.bToken).balanceOf(p.addr);
            positionBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
            positionBalances.preAToken = _getATokenBalance(p.addr, p.cToken);

            // Act
            vm.recordLogs();
            IPosition(p.addr).addLeverage(_ltv, 0, TEST_POOL_FEE, TEST_CLIENT);

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
            positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
            positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
            positionBalances.postAToken = _getATokenBalance(p.addr, p.cToken);

            // Assertions
            assertEq(positionBalances.postBToken, bAmt);
            assertApproxEqAbs(positionBalances.postAToken, positionBalances.preAToken + cAmt, 1);
            assertApproxEqAbs(positionBalances.postVDToken, positionBalances.preVDToken + dAmt, 1);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - The Position contract's bToken balance after adding leverage should equal bAmt receieved from swap across all addLeverage actions.
    // - The Position contract's aToken balance should increase by emitted cAmt across all add actions.
    // - The Position contract's variable debt token balance should increase by dAmt received from borrow across all add actions
    // - The above should be true for a large range of LTVs and cAmts.
    // - The above should be true for all positions where the collateral token is the same as the base token.
    function testFuzz_AddLeverageSuccessive(uint256 _cAmt, uint256 _time) public {
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

            // Bound fuzzed variables
            // _ltv = bound(_ltv, 1, 60);
            _cAmt = bound(_cAmt, assets.minCAmts(p.cToken), assets.maxCAmts(p.cToken));

            // Fund owner with collateral
            _fund(owner, p.cToken, _cAmt);

            // Add initial position
            IERC20(p.cToken).approve(p.addr, _cAmt);
            IPosition(p.addr).add(_cAmt, 50, 0, TEST_POOL_FEE, TEST_CLIENT);

            /// @dev Initial balances to refect inital add
            uint256 bAmtEndState;
            sums.cAmt = _getATokenBalance(p.addr, p.cToken);
            sums.dAmt = _getVariableDebtTokenBalance(p.addr, p.dToken);
            loanData.debtBeforeTimeDelta = 0;
            loanData.debtAfterTimeDelta = 0;
            loanData.debtInterest = 0;
            loanData.colBeforeTimeDelta = 0;
            loanData.colAfterTimeDelta = 0;
            loanData.colInterest = 0;

            bool shallowLiquidity = (p.bToken == DAI && p.dToken == WBTC) || (p.bToken == WBTC && p.dToken == DAI);
            if (!shallowLiquidity) {
                for (uint256 j; j < SUCCESSIVE_ITERATIONS; j++) {
                    _time = bound(_time, 1 minutes, 2 minutes);

                    (positionBalances.cTotalUSD, positionBalances.dTotalUSD,,,,) =
                        IPool(AAVE_POOL).getUserAccountData(p.addr);

                    // Act
                    vm.recordLogs();
                    IPosition(p.addr).addLeverage(50, 0, TEST_POOL_FEE, TEST_CLIENT);

                    // Retrieve bAmt and dAmt from AddLeverage event
                    VmSafe.Log[] memory entries = vm.getRecordedLogs();
                    bytes memory addLeverageEvent = entries[entries.length - 1].data;
                    uint256 netCAmt;
                    uint256 dAmt;
                    uint256 bAmt;
                    assembly {
                        netCAmt := mload(add(addLeverageEvent, 0x20))
                        dAmt := mload(add(addLeverageEvent, 0x40))
                        bAmt := mload(add(addLeverageEvent, 0x60))
                    }

                    // Sum successive adds
                    sums.cAmt += (netCAmt + loanData.colInterest);
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
                    } else {
                        bAmtEndState = bAmt;
                    }
                }
                // Post-act balances
                positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                positionBalances.postAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);

                // Assertions

                assertEq(positionBalances.postBToken, bAmtEndState);
                /// @dev The max delta per iteration is 1. Therefore, the max
                //  delta for all iterations is the number of iterations.
                assertApproxEqAbs(positionBalances.postAToken, sums.cAmt, SUCCESSIVE_ITERATIONS);
                assertApproxEqAbs(positionBalances.postVDToken, sums.dAmt, SUCCESSIVE_ITERATIONS);
            }

            // Revert to snapshot to standardize chain state for each position
            vm.revertTo(id);
        }
    }
}

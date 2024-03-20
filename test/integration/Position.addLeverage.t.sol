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
    PROTOCOL_FEE_RATE,
    TEST_CLIENT,
    TEST_LTV,
    TEST_POOL_FEE,
    USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IPool } from "src/interfaces/aave/IPool.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";

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

    /// @dev Tests that addLeverage function works when the collateral token and base token are different.
    /// @notice Assertions:
    // - The Position contract's (B_TOKEN) aToken balance should increase by bAmt (from swap).
    // - The Position contract's (C_TOKEN) aToken balance should not change.
    // - The Position contract's variable debt token balance should increase by dAmt (from borrow).
    // - The Position contract's D_TOKEN balance should remain 0.
    // - The above should be true for a large range of LTVs and cAmts.
    function testFuzz_AddLeverageDiffCAndB(uint256 _ltv, uint256 _dAmt) public {
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

            if (p.cToken != p.bToken) {
                // Bound fuzzed variables
                _ltv = bound(_ltv, 1, 60);

                // Open position
                _fund(owner, p.cToken, assets.maxCAmts(p.cToken));
                IERC20(p.cToken).approve(p.addr, assets.maxCAmts(p.cToken));
                IPosition(p.addr).add(assets.maxCAmts(p.cToken), TEST_LTV, 0, TEST_POOL_FEE, TEST_CLIENT);

                // Pre-act balances
                positionBalances.preBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                positionBalances.preBToken = IERC20(p.bToken).balanceOf(p.addr);

                // Get max borrow
                uint256 maxBorrow = _getMaxBorrow(p.addr, p.dToken, assets.decimals(p.dToken));
                _dAmt = bound(_dAmt, assets.minDAmts(p.dToken), maxBorrow);

                // Act
                vm.recordLogs();
                IPosition(p.addr).addLeverage(_dAmt, 0, TEST_POOL_FEE, TEST_CLIENT);

                // Retrieve bAmt and dAmt from AddLeverage event
                VmSafe.Log[] memory entries = vm.getRecordedLogs();
                bytes memory addLeverageEvent = entries[entries.length - 1].data;
                uint256 bAmt;
                assembly {
                    bAmt := mload(add(addLeverageEvent, 0x40))
                }

                // Post-act balances
                positionBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);

                // Assertions
                assertApproxEqAbs(positionBalances.postBAToken, positionBalances.preBAToken + bAmt, 1);
                assertEq(positionBalances.postCAToken, positionBalances.preCAToken);
                assertApproxEqAbs(positionBalances.postVDToken, positionBalances.preVDToken + _dAmt, 1);
                assertEq(positionBalances.postBToken, 0);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }

    /// @dev Tests that addLeverage function works when the collateral token and base token are the same.
    /// @notice Assertions:
    // - The Position contract's (C_TOKEN) aToken balance should increase by bAmt (from swap).
    // - The Position contract's (B_TOKEN) aToken balance should equal its (C_TOKEN) aToken balance.
    // - The Position contract's variable debt token balance should increase by dAmt (from borrow).
    // - The Position contract's D_TOKEN balance should remain 0.
    // - The above should be true for a large range of LTVs and cAmts.
    function testFuzz_AddLeverageSameCAndB(uint256 _ltv, uint256 _dAmt) public {
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

            if (p.cToken == p.bToken) {
                // Bound fuzzed variables
                _ltv = bound(_ltv, 1, 60);

                // Open position
                _fund(owner, p.cToken, assets.maxCAmts(p.cToken));
                IERC20(p.cToken).approve(p.addr, assets.maxCAmts(p.cToken));
                IPosition(p.addr).add(assets.maxCAmts(p.cToken), TEST_LTV, 0, TEST_POOL_FEE, TEST_CLIENT);

                // Pre-act balances
                positionBalances.preBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                positionBalances.preBToken = IERC20(p.bToken).balanceOf(p.addr);

                // Get max borrow
                uint256 maxBorrow = _getMaxBorrow(p.addr, p.dToken, assets.decimals(p.dToken));
                _dAmt = bound(_dAmt, assets.minDAmts(p.dToken), maxBorrow);

                // Act
                vm.recordLogs();
                IPosition(p.addr).addLeverage(_dAmt, 0, TEST_POOL_FEE, TEST_CLIENT);

                // Retrieve bAmt and dAmt from AddLeverage event
                VmSafe.Log[] memory entries = vm.getRecordedLogs();
                bytes memory addLeverageEvent = entries[entries.length - 1].data;
                uint256 bAmt;
                assembly {
                    bAmt := mload(add(addLeverageEvent, 0x40))
                }

                // Post-act balances
                positionBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);
                positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);

                // Assertions
                assertApproxEqAbs(positionBalances.postCAToken, positionBalances.preCAToken + bAmt, 1);
                assertEq(positionBalances.postBAToken, positionBalances.postCAToken);
                assertApproxEqAbs(positionBalances.postVDToken, positionBalances.preVDToken + _dAmt, 1);
                assertEq(positionBalances.postBToken, 0);

                // Revert to snapshot
                vm.revertTo(id);
            }
        }
    }
}

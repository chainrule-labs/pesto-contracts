// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { DebtServiceHarness } from "test/harness/DebtServiceHarness.t.sol";
import { DebtUtils } from "test/services/utils/DebtUtils.t.sol";
import { TokenUtils } from "test/services/utils/TokenUtils.t.sol";
import { Assets, AAVE_ORACLE, AAVE_POOL, DAI, USDC, USDC_HOLDER, WITHDRAW_BUFFER } from "test/common/Constants.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPool } from "src/interfaces/aave/IPool.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract DebtServiceTest is Test, DebtUtils, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    // Test Contracts
    Assets public assets;

    // Test Storage
    DebtServiceHarness[] public debtServices;
    address[4] public supportedAssets;
    uint256 public mainnetFork;

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        assets = new Assets();
        supportedAssets = assets.getSupported();

        // Construct list of all possible debt services
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                if (i != j) {
                    // Create DebtService
                    address cToken = supportedAssets[i];
                    address dToken = supportedAssets[j];
                    DebtServiceHarness debtService = new DebtServiceHarness(cToken, dToken);
                    debtServices.push(debtService);

                    // Fund DebtService with collateral
                    _fund(address(debtService), cToken, assets.maxCAmts(cToken));
                }
            }
        }
    }

    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - cToken should have correct decimals.
    // - dToken should have correct decimals.
    // - cDecimalConversion should be correct.
    // - dDecimalConversion should be correct.
    // - cToken decimals multiplied by cDecimalConversion should equal 10^18 for all cases.
    // - dToken decimals multiplied by dDecimalConversion should equal 10^18 for all cases.

    function test_SetUpState() public {
        assertEq(debtServices.length, 12);

        // Assert correct decimals and conversions
        for (uint256 i; i < debtServices.length; i++) {
            uint8 cDecimals = assets.decimals(debtServices[i].C_TOKEN());
            uint8 dDecimals = assets.decimals(debtServices[i].D_TOKEN());
            uint64 cDecimalConversion = uint64(10 ** (18 - cDecimals));
            uint64 dDecimalConversion = uint64(10 ** (18 - dDecimals));
            uint256 cResult = 10 ** uint256(cDecimals) * uint256(cDecimalConversion);
            uint256 dResult = 10 ** uint256(dDecimals) * uint256(dDecimalConversion);

            assertEq(debtServices[i].C_DECIMALS(), cDecimals);
            assertEq(debtServices[i].D_DECIMALS(), dDecimals);
            assertEq(debtServices[i].exposed_cDecimalConversion(), cDecimalConversion);
            assertEq(debtServices[i].exposed_dDecimalConversion(), dDecimalConversion);
            assertEq(cResult, 10 ** 18);
            assertEq(dResult, 10 ** 18);
        }
    }

    /// @dev
    // - It's cToken balance should decrease by the amount of collateral supplied.
    // - It's dToken balance should increase by the amount of debt borrowed.
    // - It should borrow the correct amount, given mocked token prices.

    function testFuzz_Borrow(uint256 _ltv) public {
        // Mock AaveOracle
        for (uint256 i; i < supportedAssets.length; i++) {
            vm.mockCall(
                AAVE_ORACLE,
                abi.encodeWithSelector(IAaveOracle(AAVE_ORACLE).getAssetPrice.selector, supportedAssets[i]),
                abi.encode(assets.prices(supportedAssets[i]))
            );
        }

        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();
            address dToken = debtServices[i].D_TOKEN();
            uint256 cDecimalConversion = debtServices[i].exposed_cDecimalConversion();
            uint256 dDecimalConversion = debtServices[i].exposed_dDecimalConversion();
            uint256 cAmt = assets.maxCAmts(cToken);

            // Assumptions
            _ltv = bound(_ltv, 1, 60);

            // Expectations
            uint256 dAmtExpected = _getDAmt(
                assets.prices(cToken), assets.prices(dToken), cDecimalConversion, dDecimalConversion, cAmt, _ltv
            );

            // Pre-Act Assertions
            assertEq(IERC20(cToken).balanceOf(debtService), cAmt);
            assertEq(IERC20(dToken).balanceOf(debtService), 0);

            // Act
            uint256 dAmt = debtServices[i].exposed_borrow(cAmt, _ltv);

            // Assertions
            assertEq(IERC20(cToken).balanceOf(debtService), 0);
            assertEq(IERC20(dToken).balanceOf(debtService), dAmt);
            assertEq(dAmt, dAmtExpected);
        }
    }

    /// @dev
    // - The position contract's debt should decrease by amount the amount repaid.
    // - The above should be true for all supported debt tokens.
    function test_Repay(uint256 _payment) public {
        // Setup
        uint256 ltv = 50;
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByDToken(debtServices);

        assertEq(filteredDebtServices.length, 4);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);

            // Borrow
            address cToken = debtServices[i].C_TOKEN();
            uint256 cAmt = assets.maxCAmts(cToken);
            uint256 dAmt = debtServices[i].exposed_borrow(cAmt, ltv);

            // Pre-act data
            uint256 preDebtAmt = debtServices[i].exposed_getDebtAmt();

            // Bound
            _payment = bound(_payment, 1, dAmt);

            // Act
            vm.prank(debtService);
            debtServices[i].exposed_repay(_payment);

            // Post-act data
            uint256 postDebtAmt = debtServices[i].exposed_getDebtAmt();

            // Assert
            assertApproxEqAbs(postDebtAmt, preDebtAmt - _payment, 1);
        }
    }

    /// @dev
    // - The position contract's aToken balance should decrease by the amount withdrawn (it should go to 0).
    // - The owner's cToken balance should increase by the amount withdrawn.
    // - The above should be true for all supported collateral tokens.
    // - The above should work for a range of withdaw amounts.
    function test_Withdraw(uint256 _cAmt) public {
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByCToken(debtServices);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();

            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Supply collateral
            vm.startPrank(debtService);
            IERC20(cToken).approve(AAVE_POOL, _cAmt);
            IPool(AAVE_POOL).supply(cToken, _cAmt, debtService, 0);

            // Pre-act data
            uint256 preATokenBal = _getATokenBalance(debtService, cToken);
            uint256 preOwnerCTokenBal = IERC20(cToken).balanceOf(address(this));

            // Act
            debtServices[i].exposed_withdraw(address(this), WITHDRAW_BUFFER);

            // Post-act data
            uint256 postATokenBal = _getATokenBalance(debtService, cToken);
            uint256 postOwnerCTokenBal = IERC20(cToken).balanceOf(address(this));

            // Assert
            assertEq(postATokenBal, 0);
            assertEq(postOwnerCTokenBal, preOwnerCTokenBal + preATokenBal);
        }
    }

    /// @dev
    // - It should withdraw the calculated maximum amount.
    function test_GetMaxWithdrawAmtWithDebt(uint256 _cAmt) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();
            uint256 ltv = 50;

            // Assumption
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Borrow
            debtServices[i].exposed_borrow(assets.maxCAmts(cToken), ltv);

            // Act
            uint256 maxWithdrawAmt = debtServices[i].exposed_getMaxWithdrawAmt(WITHDRAW_BUFFER);

            vm.prank(debtService);
            IPool(AAVE_POOL).withdraw(cToken, maxWithdrawAmt, debtService);
            assert(true);
        }
    }

    /// @dev
    // - It should withdraw the calculated maximum amount.
    function test_GetMaxWithdrawAmtNoDebt(uint256 _cAmt) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();

            // Assumption
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Supply collateral
            vm.startPrank(debtService);
            IERC20(cToken).approve(AAVE_POOL, _cAmt);
            IPool(AAVE_POOL).supply(cToken, _cAmt, debtService, 0);

            // Act
            uint256 maxWithdrawAmt = debtServices[i].exposed_getMaxWithdrawAmt(WITHDRAW_BUFFER);

            IPool(AAVE_POOL).withdraw(cToken, maxWithdrawAmt, debtService);
            assert(true);
        }
    }

    /// @dev
    // - It should revert for amounts greater than 1.00001 of max withdraw.
    function testFail_GetMaxWithdrawAmt(uint256 _cAmt, uint256 _extra) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();
            uint256 ltv = 50;

            // Assumption
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Borrow
            debtServices[i].exposed_borrow(assets.maxCAmts(cToken), ltv);

            // Act
            uint256 maxWithdrawAmt = debtServices[i].exposed_getMaxWithdrawAmt(WITHDRAW_BUFFER);

            // Add extra to max withdraw
            uint256 minAmount = maxWithdrawAmt / 100_000;
            vm.assume(_extra >= minAmount);

            vm.prank(debtService);
            IPool(AAVE_POOL).withdraw(cToken, maxWithdrawAmt + _extra, debtService);
        }
    }

    /// @dev
    // - It should return the number of variable debt tokens the contract holds.
    // - The above should be true for all supported debt tokens.

    function test_GetDebtAmt() public {
        // Setup
        uint256 ltv = 50;
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByDToken(debtServices);
        assertEq(filteredDebtServices.length, 4);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            address cToken = debtServices[i].C_TOKEN();
            uint256 cAmt = assets.maxCAmts(cToken);
            uint256 dAmt = debtServices[i].exposed_borrow(cAmt, ltv);

            // Act
            uint256 debtAmt = debtServices[i].exposed_getDebtAmt();

            // Assertions
            assertEq(debtAmt, dAmt);
        }
    }
}

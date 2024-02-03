// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { AdminService } from "src/services/AdminService.sol";
import { DebtServiceHarness } from "test/harness/DebtServiceHarness.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { Assets, AAVE_ORACLE, AAVE_POOL, REPAY_BUFFER, TEST_LTV, WITHDRAW_BUFFER } from "test/common/Constants.t.sol";
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
    address public owner = address(this);

    function setUp() public {
        assets = new Assets();
        supportedAssets = assets.getSupported();

        // Construct list of all possible debt services
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                if (i != j) {
                    // Create DebtService
                    address cToken = supportedAssets[i];
                    address dToken = supportedAssets[j];
                    DebtServiceHarness debtService = new DebtServiceHarness(owner, cToken, dToken);
                    debtServices.push(debtService);

                    // Fund DebtService with collateral
                    _fund(address(debtService), cToken, assets.maxCAmts(cToken));
                }
            }
        }
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
    // - The contract's cToken balance should decrease by the amount of collateral supplied.
    // - The contract's dToken balance should increase by the amount of debt borrowed.
    // - The contract should borrow the correct amount, given mocked token prices.
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
    // - The position contract's debt should decrease by the amount repaid.
    // - The above should be true for all supported debt tokens.
    function testFuzz_Repay(uint256 _payment) public {
        // Setup
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByDToken(debtServices);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);

            // Borrow
            address cToken = debtServices[i].C_TOKEN();
            uint256 cAmt = assets.maxCAmts(cToken);
            uint256 dAmt = debtServices[i].exposed_borrow(cAmt, TEST_LTV);

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
    // - The position contract's aToken balance should decrease by the amount withdrawn.
    // - The owner's cToken balance should increase by the amount withdrawn.
    // - The above should be true for all supported collateral tokens.
    // - The above should work for a range of withdawal amounts.
    function testFuzz_WithdrawPartial(uint256 _cAmt, uint256 _withdrawAmt) public {
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
            vm.stopPrank();

            // Pre-act data
            uint256 preATokenBal = _getATokenBalance(debtService, cToken);
            uint256 preOwnerCTokenBal = IERC20(cToken).balanceOf(owner);

            // Assumptions
            vm.assume(_withdrawAmt > 0 && _withdrawAmt <= preATokenBal);

            // Act
            vm.prank(owner);
            debtServices[i].withdraw(owner, _withdrawAmt);

            // Post-act data
            uint256 postATokenBal = _getATokenBalance(debtService, cToken);
            uint256 postOwnerCTokenBal = IERC20(cToken).balanceOf(owner);

            // Assert
            assertApproxEqAbs(postATokenBal, preATokenBal - _withdrawAmt, 1);
            assertEq(postOwnerCTokenBal, preOwnerCTokenBal + _withdrawAmt);
        }
    }

    /// @dev
    // - The position contract's aToken balance should decrease to 0.
    // - The owner's cToken balance should increase by the amount withdrawn.
    // - The above should be true for all supported collateral tokens.
    function testFuzz_WithdrawFull(uint256 _cAmt) public {
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
            vm.stopPrank();

            // Get max withdraw amount - will always be type(uint256).max because the contract has no debt
            uint256 maxWithdrawAmt = debtServices[i].getMaxWithdrawAmt(WITHDRAW_BUFFER);

            // Pre-act data
            uint256 preATokenBal = _getATokenBalance(debtService, cToken);
            uint256 preOwnerCTokenBal = IERC20(cToken).balanceOf(owner);

            // Act
            vm.prank(owner);
            debtServices[i].withdraw(owner, maxWithdrawAmt);

            // Post-act data
            uint256 postATokenBal = _getATokenBalance(debtService, cToken);
            uint256 postOwnerCTokenBal = IERC20(cToken).balanceOf(owner);

            // Assert
            assertEq(postATokenBal, 0);
            assertEq(postOwnerCTokenBal, preOwnerCTokenBal + preATokenBal);
        }
    }

    /// @dev
    // - It should withdraw the calculated maximum amount of collateral.
    function testFuzz_GetMaxWithdrawAmtWithDebt(uint256 _cAmt) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();

            // Assumption
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Borrow
            debtServices[i].exposed_borrow(assets.maxCAmts(cToken), TEST_LTV);

            // Act
            uint256 maxWithdrawAmt = debtServices[i].getMaxWithdrawAmt(WITHDRAW_BUFFER);

            vm.prank(debtService);
            IPool(AAVE_POOL).withdraw(cToken, maxWithdrawAmt, debtService);
            assert(true);
        }
    }

    /// @dev
    // - It should withdraw the calculated maximum amount of collateral.
    function testFuzz_GetMaxWithdrawAmtNoDebt(uint256 _cAmt) public {
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
            uint256 maxWithdrawAmt = debtServices[i].getMaxWithdrawAmt(WITHDRAW_BUFFER);

            IPool(AAVE_POOL).withdraw(cToken, maxWithdrawAmt, debtService);
            assert(true);
        }
    }

    /// @dev
    // - It should revert for collateral withdrawal amounts greater than 1.00001 of max withdrawal.
    function testFailFuzz_GetMaxWithdrawAmt(uint256 _cAmt, uint256 _extra) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();

            // Assumption
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Borrow
            debtServices[i].exposed_borrow(assets.maxCAmts(cToken), TEST_LTV);

            // Act
            uint256 maxWithdrawAmt = debtServices[i].getMaxWithdrawAmt(WITHDRAW_BUFFER);

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
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByDToken(debtServices);
        assertEq(filteredDebtServices.length, 4);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            address cToken = debtServices[i].C_TOKEN();
            uint256 cAmt = assets.maxCAmts(cToken);
            uint256 dAmt = debtServices[i].exposed_borrow(cAmt, TEST_LTV);

            // Act
            uint256 debtAmt = debtServices[i].exposed_getDebtAmt();

            // Assertions
            assertApproxEqAbs(debtAmt, dAmt + REPAY_BUFFER, 1);
        }
    }

    /// @dev
    // - The contract's aToken balance should increase by amount of collateral supplied.
    // - The owner's cToken balance should decrease by the amount of collateral supplied.
    function testFuzz_AddCollateral(uint256 _cAmt) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();
            debtServices[i].exposed_borrow(assets.maxCAmts(cToken), TEST_LTV);

            // Assumptions
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Fund owner and approve debtService
            _fund(owner, cToken, _cAmt);
            IERC20(cToken).approve(debtService, _cAmt);

            // Pre-Act Assertions
            uint256 preAtokenBalance = _getATokenBalance(debtService, cToken);
            uint256 preOwnerCtokenBalance = IERC20(cToken).balanceOf(owner);
            assertEq(preOwnerCtokenBalance, _cAmt);

            // Act
            debtServices[i].addCollateral(_cAmt);

            // Post-Act Assertions
            uint256 postAtokenBalance = _getATokenBalance(debtService, cToken);
            uint256 postOwnerCtokenBalance = IERC20(cToken).balanceOf(owner);
            assertEq(postOwnerCtokenBalance, preOwnerCtokenBalance - _cAmt);
            assertApproxEqAbs(postAtokenBalance, preAtokenBalance + _cAmt, 1);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotAddCollateral(uint256 _cAmt, address _sender) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();
            debtServices[i].exposed_borrow(assets.maxCAmts(cToken), TEST_LTV);

            // Assumptions
            vm.assume(_sender != owner);
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Fund owner and approve debtService
            _fund(owner, cToken, _cAmt);
            IERC20(cToken).approve(debtService, _cAmt);

            // Act
            vm.prank(_sender);
            vm.expectRevert(AdminService.Unauthorized.selector);
            debtServices[i].addCollateral(_cAmt);
        }
    }

    /// @dev
    // - The contract's debt amount should decrease by amount repaid.
    // - The owner's D_TOKEN balance should decrease by the amount repaid.
    function testFuzz_RepayAndWithdraw(uint256 _payment) public {
        // Setup
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByDToken(debtServices);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);

            // Borrow
            address cToken = debtServices[i].C_TOKEN();
            uint256 cAmt = assets.maxCAmts(cToken);
            uint256 dAmt = debtServices[i].exposed_borrow(cAmt, TEST_LTV);

            // Fund owner with dAmt of D_TOKEN
            _fund(owner, debtServices[i].D_TOKEN(), dAmt);

            // Pre-act data
            uint256 preDebtAmt = debtServices[i].exposed_getDebtAmt();
            uint256 preOwnerDtokenBalance = IERC20(debtServices[i].D_TOKEN()).balanceOf(owner);

            // Bound
            _payment = bound(_payment, 1, dAmt);

            // Approve debtService to spend owner's _payment
            IERC20(debtServices[i].D_TOKEN()).approve(debtService, _payment);

            // Act
            debtServices[i].repayAndWithdraw(_payment, WITHDRAW_BUFFER);

            // Post-act data
            uint256 postDebtAmt = debtServices[i].exposed_getDebtAmt();
            uint256 postOwnerDtokenBalance = IERC20(debtServices[i].D_TOKEN()).balanceOf(owner);

            // Assert
            assertApproxEqAbs(postDebtAmt, preDebtAmt - _payment, 1);
            assertEq(postOwnerDtokenBalance, preOwnerDtokenBalance - _payment);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotRepayAndWithdraw(uint256 _payment, address _sender) public {
        // Setup
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByDToken(debtServices);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);

            // Borrow
            address cToken = debtServices[i].C_TOKEN();
            uint256 cAmt = assets.maxCAmts(cToken);
            uint256 dAmt = debtServices[i].exposed_borrow(cAmt, TEST_LTV);

            // Fund owner with dAmt of D_TOKEN
            _fund(owner, debtServices[i].D_TOKEN(), dAmt);

            // Assumptions
            _payment = bound(_payment, 1, dAmt);
            vm.assume(_sender != owner);

            // Approve debtService to spend owner's _payment
            IERC20(debtServices[i].D_TOKEN()).approve(debtService, _payment);

            // Act
            vm.prank(_sender);
            vm.expectRevert(AdminService.Unauthorized.selector);
            debtServices[i].repayAndWithdraw(_payment, WITHDRAW_BUFFER);
        }
    }
}

contract DebtServicePermitTest is Test, DebtUtils, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    // Test Contracts
    Assets public assets;

    // Test Storage
    DebtServiceHarness[] public debtServices;
    VmSafe.Wallet public wallet;
    address[4] public supportedAssets;
    address public owner;

    function setUp() public {
        // Deploy Assets contract
        assets = new Assets();
        supportedAssets = assets.getSupported();

        // Set contract owner
        wallet = vm.createWallet(uint256(keccak256(abi.encodePacked(uint256(1)))));
        owner = wallet.addr;

        // Construct list of all possible debt services
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                if (i != j) {
                    // Create DebtService
                    address cToken = supportedAssets[i];
                    address dToken = supportedAssets[j];
                    DebtServiceHarness debtService = new DebtServiceHarness(owner, cToken, dToken);
                    debtServices.push(debtService);

                    // Fund DebtService with collateral
                    _fund(address(debtService), cToken, assets.maxCAmts(cToken));
                }
            }
        }
    }

    /// @dev
    // - The contract's aToken balance should increase by amount of collateral supplied.
    // - The owner's cToken balance should decrease by the amount of collateral supplied.
    // - The act should be accomplished without a separate approve tx.
    function testFuzz_AddCollateralWithPermit(uint256 _cAmt) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();
            debtServices[i].exposed_borrow(assets.maxCAmts(cToken), TEST_LTV);

            // Assumptions
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Fund owner and approve debtService
            _fund(owner, cToken, _cAmt);

            // Get permit
            uint256 permitTimestamp = block.timestamp + 1000;
            (uint8 v, bytes32 r, bytes32 s) = _getPermit(cToken, wallet, debtService, _cAmt, permitTimestamp);

            // Pre-Act Assertions
            uint256 preAtokenBalance = _getATokenBalance(debtService, cToken);
            uint256 preOwnerCtokenBalance = IERC20(cToken).balanceOf(owner);
            assertEq(preOwnerCtokenBalance, _cAmt);

            // Act
            vm.prank(owner);
            debtServices[i].addCollateralWithPermit(_cAmt, permitTimestamp, v, r, s);

            // Post-Act Assertions
            uint256 postAtokenBalance = _getATokenBalance(debtService, cToken);
            uint256 postOwnerCtokenBalance = IERC20(cToken).balanceOf(owner);
            assertEq(postOwnerCtokenBalance, preOwnerCtokenBalance - _cAmt);
            assertApproxEqAbs(postAtokenBalance, preAtokenBalance + _cAmt, 1);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotAddCollateralWithPermit(uint256 _cAmt, address _sender) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].C_TOKEN();
            debtServices[i].exposed_borrow(assets.maxCAmts(cToken), TEST_LTV);

            // Assumptions
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));
            vm.assume(_sender != owner);

            // Fund owner and approve debtService
            _fund(owner, cToken, _cAmt);

            // Get permit
            uint256 permitTimestamp = block.timestamp + 1000;
            (uint8 v, bytes32 r, bytes32 s) = _getPermit(cToken, wallet, debtService, _cAmt, permitTimestamp);

            // Act
            vm.prank(_sender);
            vm.expectRevert(AdminService.Unauthorized.selector);
            debtServices[i].addCollateralWithPermit(_cAmt, permitTimestamp, v, r, s);
        }
    }

    /// @dev
    // - The contract's debt amount should decrease by amount repaid.
    // - The owner's D_TOKEN balance should decrease by the amount repaid.
    // - The act should be accomplished without a separate approve tx.
    function testFuzz_RepayAndWithdrawWithPermit(uint256 _payment) public {
        // Setup
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByDToken(debtServices);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            // Borrow
            address cToken = debtServices[i].C_TOKEN();
            address dToken = debtServices[i].D_TOKEN();
            uint256 dAmt = debtServices[i].exposed_borrow(assets.maxCAmts(cToken), TEST_LTV);

            // Fund owner with dAmt of D_TOKEN
            _fund(owner, dToken, dAmt);

            // Bound
            _payment = bound(_payment, 1, dAmt);

            // Get permit
            uint256 permitTimestamp = block.timestamp + 1000;
            (uint8 v, bytes32 r, bytes32 s) =
                _getPermit(dToken, wallet, address(debtServices[i]), _payment, permitTimestamp);

            // Pre-act data
            uint256 preDebtAmt = debtServices[i].exposed_getDebtAmt();
            uint256 preOwnerDtokenBalance = IERC20(debtServices[i].D_TOKEN()).balanceOf(owner);

            // Act
            vm.prank(owner);
            debtServices[i].repayAndWithdrawWithPermit(_payment, WITHDRAW_BUFFER, permitTimestamp, v, r, s);

            // Post-act data
            uint256 postDebtAmt = debtServices[i].exposed_getDebtAmt();
            uint256 postOwnerDtokenBalance = IERC20(debtServices[i].D_TOKEN()).balanceOf(owner);

            // Assert
            assertApproxEqAbs(postDebtAmt, preDebtAmt - _payment, 1);
            assertEq(postOwnerDtokenBalance, preOwnerDtokenBalance - _payment);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotRepayAndWithdrawWithPermit(uint256 _payment, address _sender) public {
        // Setup
        DebtServiceHarness[4] memory filteredDebtServices = _getFilteredDebtServicesByDToken(debtServices);

        for (uint256 i; i < filteredDebtServices.length; i++) {
            // Borrow
            address cToken = debtServices[i].C_TOKEN();
            address dToken = debtServices[i].D_TOKEN();
            uint256 dAmt = debtServices[i].exposed_borrow(assets.maxCAmts(cToken), TEST_LTV);

            // Fund owner with dAmt of D_TOKEN
            _fund(owner, dToken, dAmt);

            // Assumptions
            _payment = bound(_payment, 1, dAmt);
            vm.assume(_sender != owner);

            // Get permit
            uint256 permitTimestamp = block.timestamp + 1000;
            (uint8 v, bytes32 r, bytes32 s) =
                _getPermit(dToken, wallet, address(debtServices[i]), _payment, permitTimestamp);

            // Act
            vm.prank(_sender);
            vm.expectRevert(AdminService.Unauthorized.selector);
            debtServices[i].repayAndWithdrawWithPermit(_payment, WITHDRAW_BUFFER, permitTimestamp, v, r, s);
        }
    }
}

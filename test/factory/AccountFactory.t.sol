// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { AccountFactory } from "src/AccountFactory.sol";
import { IAccount } from "src/interfaces/IAccount.sol";
import { Assets, CONTRACT_DEPLOYER } from "test/factory/common/Constants.t.sol";

contract AccountFactoryTest is Test {
    /* solhint-disable func-name-mixedcase */

    // Test Storage
    AccountFactory public accountFactory;
    Assets public assets;

    function setUp() public {
        vm.prank(CONTRACT_DEPLOYER);
        accountFactory = new AccountFactory();
        assets = new Assets();
    }

    function test_CreateAccount() public {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();
        address account;
        address owner;
        address col;
        address debt;
        address base;

        // Expectation: all accounts should not exist
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                for (uint256 k; k < supportedAssets.length; k++) {
                    account = accountFactory.accounts(
                        address(this), supportedAssets[i], supportedAssets[j], supportedAssets[k]
                    );
                    assertEq(account, address(0));
                }
            }
        }

        // Act
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                for (uint256 k; k < supportedAssets.length; k++) {
                    account = accountFactory.createAccount(supportedAssets[i], supportedAssets[j], supportedAssets[k]);
                    owner = IAccount(account).owner();
                    col = IAccount(account).col();
                    debt = IAccount(account).debt();
                    base = IAccount(account).base();

                    // Assertions
                    assertNotEq(account, address(0));
                    assertEq(owner, address(this));
                    assertEq(col, supportedAssets[i]);
                    assertEq(debt, supportedAssets[j]);
                    assertEq(base, supportedAssets[k]);
                }
            }
        }
    }

    function test_CannotCreateAccount() public {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();
        address account;
        address duplicate;

        // Act
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                for (uint256 k; k < supportedAssets.length; k++) {
                    account = accountFactory.createAccount(supportedAssets[i], supportedAssets[j], supportedAssets[k]);
                    /// @dev Duplicate account creation should revert
                    vm.expectRevert(AccountFactory.AccountExists.selector);
                    duplicate = accountFactory.createAccount(supportedAssets[i], supportedAssets[j], supportedAssets[k]);
                }
            }
        }
    }
}

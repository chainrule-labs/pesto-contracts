// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { Assets, CONTRACT_DEPLOYER } from "test/common/Constants.t.sol";

contract PositionFactoryTest is Test {
    /* solhint-disable func-name-mixedcase */

    // Test Contracts
    PositionFactory public positionFactory;
    Assets public assets;

    // Test Storage
    uint256 public mainnetFork;

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory();
        assets = new Assets();
    }

    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
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
                    account = positionFactory.accounts(
                        address(this), supportedAssets[i], supportedAssets[j], supportedAssets[k]
                    );
                    assertEq(account, address(0));
                }
            }
        }

        // Act
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                if (j != i) {
                    for (uint256 k; k < supportedAssets.length; k++) {
                        if (k != j) {
                            account = positionFactory.createAccount(
                                supportedAssets[i], supportedAssets[j], supportedAssets[k]
                            );
                            owner = IPosition(account).OWNER();
                            col = IPosition(account).C_TOKEN();
                            debt = IPosition(account).D_TOKEN();
                            base = IPosition(account).B_TOKEN();

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
                    account = positionFactory.createAccount(supportedAssets[i], supportedAssets[j], supportedAssets[k]);
                    /// @dev Duplicate account creation should revert
                    vm.expectRevert(PositionFactory.AccountExists.selector);
                    duplicate =
                        positionFactory.createAccount(supportedAssets[i], supportedAssets[j], supportedAssets[k]);
                }
            }
        }
    }
}

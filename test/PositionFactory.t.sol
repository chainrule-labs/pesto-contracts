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
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER);
        assets = new Assets();
    }

    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    function test_CreatePosition() public {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();
        address position;
        address owner;
        address cToken;
        address dToken;
        address bToken;

        // Expectation: all positions should not exist
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                if (j != i) {
                    for (uint256 k; k < supportedAssets.length; k++) {
                        if (k != j) {
                            position = positionFactory.positions(
                                address(this), supportedAssets[i], supportedAssets[j], supportedAssets[k]
                            );
                            assertEq(position, address(0));
                        }
                    }
                }
            }
        }

        // Act
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                if (j != i) {
                    for (uint256 k; k < supportedAssets.length; k++) {
                        if (k != j) {
                            position = positionFactory.createPosition(
                                supportedAssets[i], supportedAssets[j], supportedAssets[k]
                            );
                            owner = IPosition(position).OWNER();
                            cToken = IPosition(position).C_TOKEN();
                            dToken = IPosition(position).D_TOKEN();
                            bToken = IPosition(position).B_TOKEN();

                            // Assertions
                            assertNotEq(position, address(0));
                            assertEq(owner, address(this));
                            assertEq(cToken, supportedAssets[i]);
                            assertEq(dToken, supportedAssets[j]);
                            assertEq(bToken, supportedAssets[k]);
                        }
                    }
                }
            }
        }
    }

    function test_CannotCreatePosition() public {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();
        address position;
        address duplicate;

        // Act
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                for (uint256 k; k < supportedAssets.length; k++) {
                    position =
                        positionFactory.createPosition(supportedAssets[i], supportedAssets[j], supportedAssets[k]);
                    /// @dev Duplicate position creation should revert
                    vm.expectRevert(PositionFactory.PositionExists.selector);
                    duplicate =
                        positionFactory.createPosition(supportedAssets[i], supportedAssets[j], supportedAssets[k]);
                }
            }
        }
    }

    // function test_getPositions() public {
    //     // Setup
    //     address[4] memory supportedAssets = assets.getSupported();
    //     address position;
    //     address[] positions;
    //     address owner;
    //     address cToken;
    //     address dToken;
    //     address bToken;

    //     // Act 1: no positions should exist
    //     positions = positionFactory.getPositions(owner);

    //     // Create all possible position
    //     for (uint256 i; i < supportedAssets.length; i++) {
    //         for (uint256 j; j < supportedAssets.length; j++) {
    //             if (j != i) {
    //                 for (uint256 k; k < supportedAssets.length; k++) {
    //                     if (k != j) {
    //                         position = positionFactory.createPosition(
    //                             supportedAssets[i], supportedAssets[j], supportedAssets[k]
    //                         );
    //                         owner = IPosition(position).OWNER();
    //                         cToken = IPosition(position).C_TOKEN();
    //                         dToken = IPosition(position).D_TOKEN();
    //                         bToken = IPosition(position).B_TOKEN();

    //                         // Assertions
    //                         assertNotEq(position, address(0));
    //                         assertEq(owner, address(this));
    //                         assertEq(cToken, supportedAssets[i]);
    //                         assertEq(dToken, supportedAssets[j]);
    //                         assertEq(bToken, supportedAssets[k]);
    //                     }
    //                 }
    //             }
    //         }
    //     }

    //     // Expectation: all positions should exist

    //     // position = positionFactory.createPosition(supportedAssets[i], supportedAssets[j], supportedAssets[k]);

    //     // Act
    // }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { Assets, CONTRACT_DEPLOYER } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionFactoryTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    // Test Contracts
    PositionFactory public positionFactory;
    Assets public assets;

    // Test Storage
    address public positionOwner = address(this);

    // Errors
    error OwnableUnauthorizedAccount(address account);

    // Events
    event PositionCreated(address indexed owner, address indexed position);

    function setUp() public {
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER);
        assets = new Assets();
    }

    /// @dev
    // - It should create a Position contract for each possible permutation of cToken, bToken, and bToken.
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
                                positionOwner, supportedAssets[i], supportedAssets[j], supportedAssets[k]
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
                            vm.expectEmit(true, false, false, false, address(positionFactory));
                            emit PositionCreated(positionOwner, address(0));

                            position = positionFactory.createPosition(
                                supportedAssets[i], supportedAssets[j], supportedAssets[k]
                            );
                            owner = IPosition(position).OWNER();
                            cToken = IPosition(position).C_TOKEN();
                            dToken = IPosition(position).D_TOKEN();
                            bToken = IPosition(position).B_TOKEN();
                            uint8 bDecimals = assets.decimals(IPosition(position).B_TOKEN());

                            // Assertions
                            assertNotEq(position, address(0));
                            assertEq(owner, positionOwner);
                            assertEq(cToken, supportedAssets[i]);
                            assertEq(dToken, supportedAssets[j]);
                            assertEq(bToken, supportedAssets[k]);
                            assertEq(IPosition(position).B_DECIMALS(), bDecimals);
                        }
                    }
                }
            }
        }
    }

    /// @dev
    // - It should revert with PositionExists() error when attempting to create a duplicate position.
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

    /// @dev
    // - It should return a list of all the owner's Position contract addresses.
    function test_getPositions() public {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();
        address position;
        address[] memory positions;
        address owner;
        address cToken;
        address dToken;
        address bToken;

        // Act 1: no positions should exist
        positions = positionFactory.getPositions(owner);

        // Assertions 1
        assertEq(positions.length, 0);

        // Create all possible position
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
                            assertEq(owner, positionOwner);
                            assertEq(cToken, supportedAssets[i]);
                            assertEq(dToken, supportedAssets[j]);
                            assertEq(bToken, supportedAssets[k]);
                        }
                    }
                }
            }
        }

        // Act 2: all positions should exist
        positions = positionFactory.getPositions(owner);

        // Assertions 2
        assertEq(positions.length, 36);
        for (uint256 i; i < positions.length; i++) {
            assertNotEq(positions[i], address(0));
        }
    }

    /// @dev
    // - The contract's native balance should decrease by the amount transferred.
    // - The owner's native balance should increase by the amount transferred.
    function testFuzz_ExtractNative(uint256 _amount) public {
        // Setup: fund contract with _amount of native token
        _amount = bound(_amount, 1, 1e22);
        vm.deal(address(positionFactory), _amount);

        // Get pre-act balances
        uint256 preContractBalance = address(positionFactory).balance;
        uint256 preOwnerBalance = CONTRACT_DEPLOYER.balance;

        // Assertions
        assertEq(preContractBalance, _amount);

        // Act
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory.extractNative();

        // Ge post-act balances
        uint256 postContractBalance = address(positionFactory).balance;
        uint256 postOwnerBalance = CONTRACT_DEPLOYER.balance;

        // Assertions
        assertEq(postContractBalance, 0);
        assertEq(postOwnerBalance, preOwnerBalance + _amount);
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotExtractNative(uint256 _amount, address _sender) public {
        // Setup: fund contract with _amount of native token
        _amount = bound(_amount, 1, 1e22);
        vm.assume(_sender != CONTRACT_DEPLOYER);
        vm.deal(address(positionFactory), _amount);

        // Act: attempt to extract native
        vm.prank(_sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, _sender));
        positionFactory.extractNative();
    }

    /// @dev
    // - The contract's ERC20 token balance should decrease by the amount transferred.
    // - The owner's ERC20 token balance should increase by the amount transferred.
    function testFuzz_ExtractERC20(uint256 _amount) public {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();
        uint256 preContractBalance;
        uint256 preOwnerBalance;

        for (uint256 i; i < supportedAssets.length; i++) {
            // Assumptions
            _amount = bound(_amount, 1, assets.maxCAmts(supportedAssets[i]));

            // Fund contract with _amount of each ERC20 token in supportedAssets
            _fund(address(positionFactory), supportedAssets[i], _amount);

            // Get pre-act balances
            preContractBalance = IERC20(supportedAssets[i]).balanceOf(address(positionFactory));
            preOwnerBalance = IERC20(supportedAssets[i]).balanceOf(CONTRACT_DEPLOYER);

            // Assertions
            assertEq(IERC20(supportedAssets[i]).balanceOf(address(positionFactory)), _amount);

            // Act
            vm.prank(CONTRACT_DEPLOYER);
            positionFactory.extractERC20(supportedAssets[i]);

            // Assertions
            assertEq(IERC20(supportedAssets[i]).balanceOf(address(positionFactory)), 0);
            assertEq(IERC20(supportedAssets[i]).balanceOf(CONTRACT_DEPLOYER), preOwnerBalance + _amount);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotExtractERC20(uint256 _amount, address _sender) public {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();

        // Assumptions
        vm.assume(_sender != CONTRACT_DEPLOYER);

        for (uint256 i; i < supportedAssets.length; i++) {
            // Assumptions
            _amount = bound(_amount, 1, assets.maxCAmts(supportedAssets[i]));

            // Fund contract with _amount of each ERC20 token in supportedAssets
            _fund(address(positionFactory), supportedAssets[i], _amount);

            // Act
            vm.prank(_sender);
            vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, _sender));
            positionFactory.extractERC20(supportedAssets[i]);
        }
    }
}

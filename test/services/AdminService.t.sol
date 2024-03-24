// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { AdminService } from "src/services/AdminService.sol";
import { Assets, CONTRACT_DEPLOYER } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract AdminServiceTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;

    // Test Storage
    address public positionAddr;
    address public owner = address(this);

    function setUp() public {
        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER);

        // Deploy a Position
        positionAddr = positionFactory.createPosition(supportedAssets[0], supportedAssets[3], supportedAssets[2]);
    }

    /// @dev
    // - The contract's native balance should decrease by the amount transferred.
    // - The owner's native balance should increase by the amount transferred.
    function testFuzz_ExtractNative(uint256 _amount) public {
        // Assumptions
        _amount = bound(_amount, 1, 1e22);

        // Setup
        vm.deal(positionAddr, _amount);

        // Get pre-act balances
        uint256 preContractBalance = positionAddr.balance;
        uint256 preOwnerBalance = owner.balance;

        // Assertions
        assertEq(preContractBalance, _amount);

        // Act
        vm.prank(owner);
        IPosition(positionAddr).extractNative();

        // Ge post-act balances
        uint256 postContractBalance = positionAddr.balance;
        uint256 postOwnerBalance = owner.balance;

        // Assertions
        assertEq(postContractBalance, 0);
        assertEq(postOwnerBalance, preOwnerBalance + _amount);
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotExtractNative(uint256 _amount, address _sender) public {
        // Assumptions
        _amount = bound(_amount, 1, 1e22);
        vm.assume(_sender != owner);

        // Setup
        vm.deal(positionAddr, _amount);

        // Act: attempt to extract native
        vm.prank(_sender);
        vm.expectRevert(AdminService.Unauthorized.selector);
        IPosition(positionAddr).extractNative();
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
            _fund(positionAddr, supportedAssets[i], _amount);

            // Get pre-act balances
            preContractBalance = IERC20(supportedAssets[i]).balanceOf(positionAddr);
            preOwnerBalance = IERC20(supportedAssets[i]).balanceOf(owner);

            // Assertions
            assertEq(IERC20(supportedAssets[i]).balanceOf(positionAddr), _amount);

            // Act
            vm.prank(owner);
            IPosition(positionAddr).extractERC20(supportedAssets[i]);

            // Assertions
            assertEq(IERC20(supportedAssets[i]).balanceOf(positionAddr), 0);
            assertEq(IERC20(supportedAssets[i]).balanceOf(owner), preOwnerBalance + _amount);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotExtractERC20(uint256 _amount, address _sender) public {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();

        // Assumptions
        vm.assume(_sender != owner);

        for (uint256 i; i < supportedAssets.length; i++) {
            // Assumptions
            _amount = bound(_amount, 1, assets.maxCAmts(supportedAssets[i]));

            // Fund contract with _amount of each ERC20 token in supportedAssets
            _fund(positionAddr, supportedAssets[i], _amount);

            // Act
            vm.prank(_sender);
            vm.expectRevert(AdminService.Unauthorized.selector);
            IPosition(positionAddr).extractERC20(supportedAssets[i]);
        }
    }

    /// @dev Necessary for the owner, address(this), to receive native extractNative tests
    receive() external payable { }
}

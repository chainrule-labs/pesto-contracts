// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { Position } from "src/Position.sol";
import { Assets, CONTRACT_DEPLOYER } from "test/common/Constants.t.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { TokenUtils } from "test/services/utils/TokenUtils.t.sol";

contract PositionAdminTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    // Test contracts
    PositionFactory public positionFactory;
    Position public position;
    Assets public assets;

    // Test Storage
    uint256 public mainnetFork;

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER);

        // Deploy Position
        // TODO: Does it even make sense to deploy all possible positions to test PositionAdmin functionality???
        position = Position(
            payable(positionFactory.createPosition(supportedAssets[0], supportedAssets[3], supportedAssets[2]))
        );
    }

    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    function test_ExtractNative(uint256 _amount) public {
        // Setup: fund contract with _amount of native token
        _amount = bound(_amount, 1, 1e22);
        vm.deal(address(position), _amount);

        // Get pre-act balances
        uint256 preContractBalance = address(position).balance;
        uint256 preOwnerBalance = address(this).balance;

        // Assertions
        assertEq(preContractBalance, _amount);

        // Act
        vm.prank(address(this));
        position.extractNative();

        // Ge post-act balances
        uint256 postContractBalance = address(position).balance;
        uint256 postOwnerBalance = address(this).balance;

        // Assertions
        assertEq(postContractBalance, 0);
        assertEq(postOwnerBalance, preOwnerBalance + _amount);
    }

    function test_CannotExtractNative(uint256 _amount, address _invalidExtractor) public {
        // Setup: fund contract with _amount of native token
        _amount = bound(_amount, 1, 1e22);
        vm.assume(_invalidExtractor != address(this));
        vm.deal(address(position), _amount);

        // Act: attempt to extract native
        vm.prank(_invalidExtractor);
        vm.expectRevert(PositionFactory.Unauthorized.selector);
        position.extractNative();
    }

    function test_ExtractERC20(uint256 _amountUSDC, uint256 _amountDAI, uint256 _amountWETH, uint256 _amountWBTC)
        public
    {
        // Setup
        address[4] memory supportedAssets = assets.getSupported();
        _amountUSDC = bound(_amountUSDC, 1, assets.maxCAmts(supportedAssets[0]));
        _amountDAI = bound(_amountDAI, 1, assets.maxCAmts(supportedAssets[1]));
        _amountWETH = bound(_amountWETH, 1, assets.maxCAmts(supportedAssets[2]));
        _amountWBTC = bound(_amountWBTC, 1, assets.maxCAmts(supportedAssets[3]));
        uint256[4] memory _amounts = [_amountUSDC, _amountDAI, _amountWETH, _amountWBTC];
        uint256[4] memory preContractBalances;
        uint256[4] memory preOwnerBalances;

        for (uint256 i; i < supportedAssets.length; i++) {
            // Fund contract with _amounts of each ERC20 token in supportedAssets
            _fund(address(position), supportedAssets[i], _amounts[i]);

            // Get pre-act balances
            preContractBalances[i] = IERC20(supportedAssets[i]).balanceOf(address(position));
            preOwnerBalances[i] = IERC20(supportedAssets[i]).balanceOf(address(this));

            // Assertions
            assertEq(IERC20(supportedAssets[i]).balanceOf(address(position)), _amounts[i]);
        }

        // Test
        for (uint256 i; i < supportedAssets.length; i++) {
            // Act
            vm.prank(address(this));
            position.extractERC20(supportedAssets[i]);

            // Assertions
            assertEq(IERC20(supportedAssets[i]).balanceOf(address(position)), 0);
            assertEq(IERC20(supportedAssets[i]).balanceOf(address(this)), preOwnerBalances[i] + _amounts[i]);
        }
    }

    function test_CannotExtractERC20(
        uint256 _amountUSDC,
        uint256 _amountDAI,
        uint256 _amountWETH,
        uint256 _amountWBTC,
        address _invalidExtractor
    ) public {
        // Setup
        vm.assume(_invalidExtractor != address(this));
        address[4] memory supportedAssets = assets.getSupported();
        _amountUSDC = bound(_amountUSDC, 1, assets.maxCAmts(supportedAssets[0]));
        _amountDAI = bound(_amountDAI, 1, assets.maxCAmts(supportedAssets[1]));
        _amountWETH = bound(_amountWETH, 1, assets.maxCAmts(supportedAssets[2]));
        _amountWBTC = bound(_amountWBTC, 1, assets.maxCAmts(supportedAssets[3]));
        uint256[4] memory _amounts = [_amountUSDC, _amountDAI, _amountWETH, _amountWBTC];

        for (uint256 i; i < supportedAssets.length; i++) {
            // Fund contract with _amounts of each ERC20 token in supportedAssets
            _fund(address(position), supportedAssets[i], _amounts[i]);
        }

        // Act
        for (uint256 i; i < supportedAssets.length; i++) {
            vm.prank(_invalidExtractor);
            vm.expectRevert(PositionFactory.Unauthorized.selector);
            position.extractERC20(supportedAssets[i]);
        }
    }

    /// @dev Necessary for address(this) to receive native extractNative tests
    receive() external payable { }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { Assets, CONTRACT_DEPLOYER } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/services/utils/TokenUtils.t.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionFactoryTest is Test, TokenUtils {
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

    function test_ExtractNative(uint256 _amount) public {
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

    function test_CannotExtractNative(uint256 _amount, address _invalidExtractor) public {
        // Setup: fund contract with _amount of native token
        _amount = bound(_amount, 1, 1e22);
        vm.assume(_invalidExtractor != CONTRACT_DEPLOYER);
        vm.deal(address(positionFactory), _amount);

        // Act: attempt to extract native
        vm.prank(_invalidExtractor);
        vm.expectRevert(PositionFactory.Unauthorized.selector);
        positionFactory.extractNative();
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
            _fund(address(positionFactory), supportedAssets[i], _amounts[i]);

            // Get pre-act balances
            preContractBalances[i] = IERC20(supportedAssets[i]).balanceOf(address(positionFactory));
            preOwnerBalances[i] = IERC20(supportedAssets[i]).balanceOf(CONTRACT_DEPLOYER);

            // Assertions
            assertEq(IERC20(supportedAssets[i]).balanceOf(address(positionFactory)), _amounts[i]);
        }

        // Test
        for (uint256 i; i < supportedAssets.length; i++) {
            // Act
            vm.prank(CONTRACT_DEPLOYER);
            positionFactory.extractERC20(supportedAssets[i]);

            // Assertions
            assertEq(IERC20(supportedAssets[i]).balanceOf(address(positionFactory)), 0);
            assertEq(IERC20(supportedAssets[i]).balanceOf(CONTRACT_DEPLOYER), preOwnerBalances[i] + _amounts[i]);
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
        vm.assume(_invalidExtractor != CONTRACT_DEPLOYER);
        address[4] memory supportedAssets = assets.getSupported();
        _amountUSDC = bound(_amountUSDC, 1, assets.maxCAmts(supportedAssets[0]));
        _amountDAI = bound(_amountDAI, 1, assets.maxCAmts(supportedAssets[1]));
        _amountWETH = bound(_amountWETH, 1, assets.maxCAmts(supportedAssets[2]));
        _amountWBTC = bound(_amountWBTC, 1, assets.maxCAmts(supportedAssets[3]));
        uint256[4] memory _amounts = [_amountUSDC, _amountDAI, _amountWETH, _amountWBTC];

        for (uint256 i; i < supportedAssets.length; i++) {
            // Fund contract with _amounts of each ERC20 token in supportedAssets
            _fund(address(positionFactory), supportedAssets[i], _amounts[i]);
        }

        // Act
        for (uint256 i; i < supportedAssets.length; i++) {
            vm.prank(_invalidExtractor);
            vm.expectRevert(PositionFactory.Unauthorized.selector);
            positionFactory.extractERC20(supportedAssets[i]);
        }
    }
}

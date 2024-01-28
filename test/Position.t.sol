// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { PositionAdmin } from "src/PositionAdmin.sol";
import {
    Assets,
    CONTRACT_DEPLOYER,
    DAI,
    FEE_COLLECTOR,
    TEST_CLIENT,
    USDC,
    WITHDRAW_BUFFER
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionTest is Test, TokenUtils, DebtUtils {
    /* solhint-disable func-name-mixedcase */

    struct TestPosition {
        address addr;
        address cToken;
        address dToken;
        address bToken;
    }

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    VmSafe.Wallet public wallet;
    address public positionAddr;
    uint256 public mainnetFork;
    address public owner;

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Set contract owner
        wallet = vm.createWallet(uint256(keccak256(abi.encodePacked(uint256(1)))));
        owner = wallet.addr;

        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        deployCodeTo("FeeCollector.sol", abi.encode(CONTRACT_DEPLOYER), FEE_COLLECTOR);

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
                            vm.prank(owner);
                            positionAddr = positionFactory.createPosition(cToken, dToken, bToken);
                            TestPosition memory newPosition =
                                TestPosition({ addr: positionAddr, cToken: cToken, dToken: dToken, bToken: bToken });
                            positions.push(newPosition);
                        }
                    }
                }
            }
        }
    }

    /// @dev
    // - The active fork should be the forked network created in the setup
    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotShort(address _sender) public {
        // Setup
        uint256 ltv = 60;

        // Assumptions
        vm.assume(_sender != owner);

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;
            address cToken = positions[i].cToken;
            uint256 cAmt = assets.maxCAmts(cToken);

            // Fund owner with collateral
            _fund(owner, cToken, cAmt);

            // Approve position to spend collateral
            IERC20(cToken).approve(addr, cAmt);

            // Act
            vm.prank(_sender);
            vm.expectRevert(PositionAdmin.Unauthorized.selector);
            IPosition(addr).short(cAmt, ltv, 0, 3000, TEST_CLIENT);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotShortWithPermit(address _sender) public {
        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address cToken = positions[i].cToken;
            uint256 cAmt = assets.maxCAmts(cToken);
            uint256 ltv = 60;

            // Assumptions
            vm.assume(_sender != owner);

            // Fund owner with collateral
            _fund(owner, cToken, cAmt);

            // Get permit
            uint256 permitTimestamp = block.timestamp + 1000;
            (uint8 v, bytes32 r, bytes32 s) = _getPermit(cToken, wallet, positions[i].addr, cAmt, permitTimestamp);

            // Act
            vm.prank(_sender);
            vm.expectRevert(PositionAdmin.Unauthorized.selector);
            IPosition(positions[i].addr).shortWithPermit(cAmt, ltv, 0, 3000, TEST_CLIENT, permitTimestamp, v, r, s);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotClose(address _sender) public {
        // Setup
        uint256 ltv = 50;

        // Assumptions
        vm.assume(_sender != owner);

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;

            // Setup: open short position
            uint256 cAmt = assets.maxCAmts(positions[i].cToken);
            _fund(owner, positions[i].cToken, cAmt);
            vm.startPrank(owner);
            IERC20(positions[i].cToken).approve(addr, cAmt);
            IPosition(addr).short(cAmt, ltv, 0, 3000, TEST_CLIENT);
            vm.stopPrank();

            // Act
            vm.prank(_sender);
            vm.expectRevert(PositionAdmin.Unauthorized.selector);
            IPosition(addr).close(3000, false, 0, WITHDRAW_BUFFER);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }
}

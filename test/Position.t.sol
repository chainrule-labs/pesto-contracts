// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { Assets, AAVE_ORACLE, CONTRACT_DEPLOYER, DAI, USDC, WBTC, WETH } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/services/utils/TokenUtils.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionTest is Test, TokenUtils {
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
    address public positionAddr;
    uint256 public mainnetFork;

    // Events
    event Short(uint256 cAmt, uint256 dAmt, uint256 bAmt);

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory();

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
                            positionAddr = positionFactory.createPosition(cToken, dToken, bToken);
                            TestPosition memory newPosition =
                                TestPosition({ addr: positionAddr, cToken: cToken, dToken: dToken, bToken: bToken });
                            positions.push(newPosition);
                        }
                    }
                }
            }
        }

        // Mock AaveOracle
        for (uint256 i; i < supportedAssets.length; i++) {
            vm.mockCall(
                AAVE_ORACLE,
                abi.encodeWithSelector(IAaveOracle(AAVE_ORACLE).getAssetPrice.selector, supportedAssets[i]),
                abi.encode(assets.prices(supportedAssets[i]))
            );
        }
    }

    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - User's cToken balance should decrease by collateral amount supplied.
    // - Position's bToken balance should increase by amount receieved from swap.
    // - The above should be true for a wide range of LTVs.
    // - The above should be true for a wide range of collateral amounts.
    // - The above should be true for all supported tokens.

    function testFuzz_Short(uint256 _ltv, uint256 _cAmt) public {
        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;
            address cToken = positions[i].cToken;
            address bToken = positions[i].bToken;

            // Bound fuzzed variables
            _ltv = bound(_ltv, 1, 60);
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Fund user with collateral
            _fund(address(this), cToken, _cAmt);

            // Approve position to spend collateral
            IERC20(cToken).approve(addr, _cAmt);

            // Pre-act balances
            uint256 colPreBal = IERC20(cToken).balanceOf(address(this));
            uint256 basePreBal = IERC20(cToken).balanceOf(addr);

            // Act
            vm.recordLogs();
            IPosition(addr).short(_cAmt, _ltv, 0, 3000);
            VmSafe.Log[] memory entries = vm.getRecordedLogs();

            // Post-act balances
            uint256 colPostBal = IERC20(cToken).balanceOf(address(this));
            uint256 basePostBal = IERC20(bToken).balanceOf(addr);
            bytes memory shortEvent = entries[entries.length - 1].data;
            uint256 bAmt;

            assembly {
                let startPos := sub(mload(shortEvent), 32)
                bAmt := mload(add(shortEvent, add(0x20, startPos)))
            }

            // Assertions
            assertEq(colPostBal, colPreBal - _cAmt);
            assertEq(basePostBal, basePreBal + bAmt);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - Position contract's bToken balance should go to 0.
    // - Position contract's debt on Aave should go to 0.
    // - User's cToken balance should increase by the amount of collateral withdrawn.
    // - User's bToken balance should increase by the position's gains amount.
    // - The above should be true for all supported tokens.

    // function testFuzz_CloseWithGain() public {
    //     // Take snapshot
    //     uint256 id = vm.snapshot();

    //     for (uint256 i; i < positions.length; i++) {
    //         // Test variables
    //         address addr = positions[i].addr;
    //         address cToken = positions[i].cToken;
    //         address dToken = positions[i].dToken;
    //         address bToken = positions[i].bToken;

    //         // Bound fuzzed variables

    //         // Setup: open short position
    //         uint256 cAmt = assets.maxCAmts(cToken);
    //         uint256 ltv = 50;
    //         _fund(address(this), cToken, cAmt);
    //         IERC20(cToken).approve(addr, cAmt);
    //         IPosition(addr).short(cAmt, ltv, 0, 3000);

    //         // Pre-act data

    //         // Act
    //         IPosition(addr).close(3000, true, 0, 10);

    //         // Post-act data

    //         // Revert to snapshot
    //         vm.revertTo(id);
    //     }
    // }
}

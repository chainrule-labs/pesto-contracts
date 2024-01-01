// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { SwapServiceHarness } from "test/harness/SwapServiceHarness.t.sol";
import { Assets, DAI, USDC, USDC_HOLDER } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/services/utils/TokenUtils.t.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract SwapServiceTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    // Test Contracts
    SwapServiceHarness public swapService;
    Assets public assets;

    // Test Storage
    address[4] public supportedAssets;
    address swapServiceAddr;
    uint256 public mainnetFork;

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        assets = new Assets();
        supportedAssets = assets.getSupported();

        swapService = new SwapServiceHarness();
        swapServiceAddr = address(swapService);
    }

    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - It's input token balance should decrease by the amount inputted.
    // - It's output token balance should increase by the amount outputted.
    // - The above should be true for all supported tokens.

    function test_SwapExactInput() public {
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                address inputToken = supportedAssets[i];
                address outputToken = supportedAssets[j];

                bool noPool = (inputToken == USDC && outputToken == DAI) || (inputToken == DAI && outputToken == USDC);
                bool poolExists = !noPool;

                if (i != j && poolExists) {
                    // Take snapshot
                    uint256 id = vm.snapshot();

                    // Fund SwapService with input token
                    _fund(swapServiceAddr, inputToken, assets.maxCAmts(inputToken));

                    // Pre-act balances
                    uint256 inputPreBal = IERC20(inputToken).balanceOf(swapServiceAddr);
                    uint256 outputPreBal = IERC20(outputToken).balanceOf(swapServiceAddr);

                    // Act
                    (uint256 amtIn, uint256 amtOut) = swapService.exposed_swapExactInput(
                        inputToken, outputToken, assets.maxCAmts(inputToken), 0, 3000
                    );

                    // Post-act balances
                    uint256 inputPostBal = IERC20(inputToken).balanceOf(swapServiceAddr);
                    uint256 outputPostBal = IERC20(outputToken).balanceOf(swapServiceAddr);

                    // Assertions
                    assertEq(inputPostBal, 0);
                    assertEq(inputPostBal, inputPreBal - amtIn);
                    assertEq(outputPostBal, outputPreBal + amtOut);

                    // Revert to snapshot
                    vm.revertTo(id);
                }
            }
        }
    }
}

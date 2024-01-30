// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { FeeCollector } from "src/FeeCollector.sol";
import { Assets, CONTRACT_DEPLOYER } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract FeeCollectorClientFeesTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    // Test contracts
    FeeCollector public feeCollector;
    Assets public assets;

    // Test Storage
    address[] public supportedAssets;
    uint256 public mainnetFork;
    address public owner = address(this);
    address public feeCollectorAddr;

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Deploy assets
        assets = new Assets();
        supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        feeCollector = new FeeCollector(CONTRACT_DEPLOYER);
        feeCollectorAddr = address(feeCollector);
    }

    /// @dev
    // - The active fork should be the forked network created in the setup
    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    function testFuzz_ClientProtocolFeeBalances(
        uint256 _feeAmount,
        uint256 _time,
        uint256 _clientRate,
        uint256 _clientTakeRate,
        address _client
    ) public {
        for (uint256 i; i < supportedAssets.length; i++) {
            // Bounds
            _clientRate = bound(_clientRate, 30, 100);
            _clientTakeRate = bound(_clientTakeRate, 0, 100);
            vm.assume(_client != address(0));

            // Setup
            address feeToken = supportedAssets[i];
            // uint256 clientTakeRate = 50;

            // Set client rate
            vm.prank(CONTRACT_DEPLOYER);
            feeCollector.setClientRate(_clientRate);

            // Set client take rate
            vm.prank(_client);
            feeCollector.setClientTakeRate(_clientTakeRate);

            // uint256 clientFeeSum;
            uint256 expClientsBal = 0;
            for (uint256 j; j < 100; j++) {
                // Bounds
                _feeAmount = bound(_feeAmount, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));
                _time = bound(_time, 1 minutes, 52 weeks);

                // Setup
                _fund(owner, feeToken, _feeAmount);

                // Take fees
                IERC20(feeToken).approve(feeCollectorAddr, _feeAmount);
                (, uint256 clientFee) = feeCollector.getClientAllocations(_client, _feeAmount);
                feeCollector.collectFees(_client, feeToken, _feeAmount, clientFee);

                // Calculate expected client fee
                uint256 expectedClientFee = (_clientTakeRate * _clientRate * _feeAmount) / 1e4;

                // The expectedClientFee should always be equal to or 1 less than clientFee, due to integer division
                assertApproxEqAbs(expectedClientFee, clientFee, 1);
                expClientsBal += clientFee;

                // Go forward in time (should be time invariant)
                skip(_time);
            }

            // Get balances
            uint256 clientsBal = feeCollector.totalClientBalances(feeToken);

            // Assertions
            assertEq(expClientsBal, clientsBal, "expClientsBal != clientsBal");
        }
    }
}

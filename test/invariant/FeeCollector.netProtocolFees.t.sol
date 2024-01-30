// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

import "forge-std/console.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import { Assets, CONTRACT_DEPLOYER, TEST_CLIENT, CLIENT_RATE, USDC, WETH, WBTC } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { FeeUtils } from "test/common/utils/FeeUtils.t.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract FeeCollectorNetProtocolFeesTest is Test, TokenUtils, FeeUtils {
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

        // Set client rate
        vm.prank(CONTRACT_DEPLOYER);
        feeCollector.setClientRate(CLIENT_RATE);
    }

    /// @dev
    // - The active fork should be the forked network created in the setup
    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - Invariant: TotalClientCollectedFees / TotalCollectedProtocolFees = clientRate * clientTakeRate
    // -  TotalCollectedProtocolFees - TotalClientCollectedFees = (1 - (clientRate * clientTakeRate)) * TotalCollectedProtocolFees

    function testFuzz_NetProtocolFeesInvariant(
        uint256 _feeAmount,
        uint256 _clientRate,
        uint256 _clientTakeRate,
        uint256 _time
    ) public {
        for (uint256 i; i < supportedAssets.length; i++) {
            // Setup
            address feeToken = supportedAssets[i];
            // console.log("feeToken: ", feeToken);

            // Bounds
            _clientRate = bound(_clientRate, 30, 100);
            _clientTakeRate = bound(_clientRate, 0, 100);

            // Set client rates
            vm.prank(CONTRACT_DEPLOYER);
            feeCollector.setClientRate(_clientRate);

            vm.prank(TEST_CLIENT);
            feeCollector.setClientTakeRate(_clientTakeRate);

            // uint256 clientFeeSum;
            for (uint256 j; j < 20; j++) {
                // Bounds
                _feeAmount = bound(_feeAmount, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));
                _time = bound(_time, 1 minutes, 1 weeks);

                // Fund
                _fund(owner, feeToken, _feeAmount);

                // Approve FeeCollector to spend owner's feeToken
                IERC20(feeToken).approve(feeCollectorAddr, _feeAmount);

                // Take fees
                (, uint256 clientFee) = feeCollector.getClientAllocations(TEST_CLIENT, _feeAmount);
                feeCollector.collectFees(TEST_CLIENT, feeToken, _feeAmount, clientFee);

                // console.log("_feeAmount: ", _feeAmount);
                // clientFeeSum += clientFee;
                // console.log("clientFee: ", clientFee);

                // Skip _time ahead of current block.timestamp
                skip(_time);
            }

            // Get balances
            uint256 contractFeeBalance = IERC20(feeToken).balanceOf(feeCollectorAddr);
            uint256 totalClientBalances = feeCollector.totalClientBalances(feeToken);

            // Scale to avoid getting 0 from division
            // uint256 factor = 1e36;
            // uint256 scaledActalClientsPortion = (totalClientBalances * factor) / contractFeeBalance;
            // uint256 scaledExpectedClientPortion = (_clientRate * _clientTakeRate * factor) / 10000;

            // console.log("totalClientBalances: ", totalClientBalances);
            // console.log("contractFeeBalance: ", contractFeeBalance);
            // console.log("_clientRate: ", _clientRate);
            // console.log("_clientTakeRate: ", _clientTakeRate);

            // // Assertions
            // assertEq(scaledActalClientsPortion, scaledExpectedClientPortion);

            // TotalCollectedProtocolFees - TotalClientCollectedFees = (1 - (clientRate * clientTakeRate)) * TotalCollectedProtocolFees

            // 1. Calculate user savings
            // NOTE: Delta is still present even without division
            uint256 userTakeRate = 100 - _clientTakeRate;
            uint256 userPercentage = (userTakeRate * _clientRate);
            uint256 clientPercentage = 100 * _clientRate - userPercentage;
            uint256 ourPercentage = 100 * 100 - clientPercentage;
            uint256 ourAmt = (ourPercentage * contractFeeBalance);
            uint256 scaledActualOurAmt = 100 * 100 * (contractFeeBalance - totalClientBalances);
            assertApproxEqAbs(scaledActualOurAmt, ourAmt, 0);

            // console.log("contractFeeBalance - totalClientBalances: ", contractFeeBalance - totalClientBalances);
            // console.log("ourAmt: ", ourAmt);

            // uint256 expectedShaaveCut = ((100 - (_clientRate * _clientTakeRate) / 100) * contractFeeBalance) / 100;
            // assertEq(contractFeeBalance - totalClientBalances, expectedShaaveCut);
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { FeeCollector } from "src/FeeCollector.sol";
import { Assets, CONTRACT_DEPLOYER } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract FeeCollectorNetProtocolFeesTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    // Test contracts
    FeeCollector public feeCollector;
    Assets public assets;

    // Test Storage
    address[] public supportedAssets;
    address public owner = address(this);
    address public feeCollectorAddr;

    function setUp() public {
        // Deploy assets
        assets = new Assets();
        supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        feeCollector = new FeeCollector(CONTRACT_DEPLOYER);
        feeCollectorAddr = address(feeCollector);
    }

    /// @dev
    // - Invariant: netProtocolFees = 1 - clientRate * sum(clientTakeRate_i * maxFee_i)
    // - Ensure netProtocolFees >= (1 - clientRate) * totalBal
    // - The above should be true for a large range of maxFee, clienRate, clientTakeRate, time, and clients.
    function testFuzz_NetProtocolFeesInvariant(
        uint256 _maxFee,
        uint256 _clientRate,
        uint256 _clientTakeRate,
        uint256 _time,
        address _client
    ) public {
        for (uint256 i; i < supportedAssets.length; i++) {
            // Bounds
            _clientRate = bound(_clientRate, 30, 100);
            _clientTakeRate = bound(_clientTakeRate, 0, 100);

            // Setup
            address feeToken = supportedAssets[i];

            // Set client rates
            vm.prank(CONTRACT_DEPLOYER);
            feeCollector.setClientRate(_clientRate);

            vm.prank(_client);
            feeCollector.setClientTakeRate(_clientTakeRate);

            for (uint256 j; j < 100; j++) {
                // Bounds
                _maxFee = bound(_maxFee, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));
                _time = bound(_time, 1 minutes, 52 weeks);

                // Setup
                _fund(owner, feeToken, _maxFee);

                // Take fees
                IERC20(feeToken).approve(feeCollectorAddr, _maxFee);
                (, uint256 clientFee) = feeCollector.getClientAllocations(_client, _maxFee);
                feeCollector.collectFees(_client, feeToken, _maxFee, clientFee);

                // Go forward in time (should be time invariant)
                skip(_time);
            }

            // Get balances
            uint256 totalBal = IERC20(feeToken).balanceOf(feeCollectorAddr);
            uint256 clientsBal = feeCollector.totalClientBalances(feeToken);

            // Calculated expected and gather actual
            uint256 protocolMinPercent = 100 - _clientRate;
            uint256 expectedNetProtocolBal = (protocolMinPercent * totalBal) / 100;
            uint256 actualNetProtocolBal = totalBal - clientsBal;

            // Assertions
            assertGe(actualNetProtocolBal, expectedNetProtocolBal, "actualNetProtocolBal < expectedNetProtocolBal");
        }
    }
}

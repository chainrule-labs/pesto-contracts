// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import {
    Assets,
    CLIENT_RATE,
    CONTRACT_DEPLOYER,
    FEE_COLLECTOR,
    PROTOCOL_FEE_RATE,
    TEST_CLIENT
} from "test/common/Constants.t.sol";
import { FeeLib } from "src/libraries/FeeLib.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { FeeUtils } from "test/common/utils/FeeUtils.t.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract FeeLibTest is Test, TokenUtils, FeeUtils {
    /* solhint-disable func-name-mixedcase */

    // Test Contracts
    Assets public assets;
    address[] public supportedAssets;

    function setUp() public {
        // Deploy assets
        assets = new Assets();
        supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        deployCodeTo("FeeCollector.sol", abi.encode(CONTRACT_DEPLOYER, PROTOCOL_FEE_RATE), FEE_COLLECTOR);

        // Set client rate
        vm.prank(CONTRACT_DEPLOYER);
        IFeeCollector(FEE_COLLECTOR).setClientRate(CLIENT_RATE);
    }

    /// @dev
    // - This contract's token balance should decrease by: (max fee - user savings).
    // - The balance of the FeeCollector should increase by: (max fee - user savings).
    // - The client's balance on the FeeCollector should increase by expectedFee.
    // - The above should be true for all supported tokens.
    // - The above should be true for fuzzed cAmts and clientTakeRates.
    function testFuzz_TakeProtocolFee(uint256 _cAmt, uint256 _clientTakeRate) public {
        // Bound fuzzed inputs
        _clientTakeRate = bound(_clientTakeRate, 0, 100);

        // Setup
        vm.prank(TEST_CLIENT);
        IFeeCollector(FEE_COLLECTOR).setClientTakeRate(_clientTakeRate);

        for (uint256 i; i < supportedAssets.length; i++) {
            // Test Variables
            address feeToken = supportedAssets[i];

            // Bound fuzzed inputs
            _cAmt = bound(_cAmt, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));

            // Fund this contract with collateral
            _fund(address(this), supportedAssets[i], _cAmt);

            // Expectations
            uint256 _maxFee = (_cAmt * PROTOCOL_FEE_RATE) / 1000;
            (uint256 expectedUserSavings, uint256 expectedClientFee) =
                _getExpectedClientAllocations(_maxFee, _clientTakeRate);
            uint256 expectedFee = _maxFee - expectedUserSavings;

            // Pre-act Data
            uint256 preFeeTokenBal = IERC20(feeToken).balanceOf(address(this));
            uint256 preFeeCollectorFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            uint256 preClientFeeTokenBal = IFeeCollector(FEE_COLLECTOR).balances(TEST_CLIENT, feeToken);

            // Act
            FeeLib.takeProtocolFee(feeToken, _cAmt, TEST_CLIENT);

            // Post-act Data
            uint256 postFeeTokenBal = IERC20(feeToken).balanceOf(address(this));
            uint256 postFeeCollectorFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            uint256 postClientFeeTokenBal = IFeeCollector(FEE_COLLECTOR).balances(TEST_CLIENT, feeToken);

            // Assertions
            assertEq(postFeeTokenBal, preFeeTokenBal - expectedFee);
            assertEq(postFeeCollectorFeeTokenBal, preFeeCollectorFeeTokenBal + expectedFee);
            assertEq(postClientFeeTokenBal, preClientFeeTokenBal + expectedClientFee);
        }
    }
}

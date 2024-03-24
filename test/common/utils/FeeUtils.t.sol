// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { CLIENT_RATE } from "test/common/Constants.t.sol";

contract FeeUtils is Test {
    function _getExpectedClientAllocations(uint256 _maxFee, uint256 _clientTakeRate)
        internal
        pure
        returns (uint256 userSavings, uint256 clientFee)
    {
        uint256 userTakeRate = 100 - _clientTakeRate;
        uint256 userPercentOfProtocolFee = (userTakeRate * CLIENT_RATE);
        userSavings = (userPercentOfProtocolFee * _maxFee) / 1e4;

        // 2. Calculate client fee
        uint256 maxClientFee = (_maxFee * CLIENT_RATE) / 100;
        clientFee = maxClientFee - userSavings;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { Assets, DAI, USDC, USDC_HOLDER } from "test/common/Constants.t.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract TokenUtils is Test {
    function _fund(address _account, address _token, uint256 _amount) internal {
        if (_token != USDC) {
            deal(_token, _account, _amount);
        } else {
            // Work around deal not working for USDC
            vm.startPrank(USDC_HOLDER);
            IERC20(USDC).transfer(_account, _amount);
            vm.stopPrank();
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local file imports
import { SwapService } from "src/services/SwapService.sol";

contract SwapServiceHarness is SwapService {
    /* solhint-disable func-name-mixedcase */

    function exposed_swapExactInput(
        address _inputToken,
        address _outputToken,
        uint256 _inputTokenAmt,
        uint256 _amtOutMin,
        uint24 _poolFee
    ) external returns (uint256 amtIn, uint256 amtOut) {
        return _swapExactInput(_inputToken, _outputToken, _inputTokenAmt, _amtOutMin, _poolFee);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

pragma abicoder v2;

// Local imports
import { TransferHelper } from "src/dependencies/uniswap/TransferHelper.sol";
import { ISwapRouter } from "src/interfaces/uniswap/ISwapRouter.sol";
import { IERC20, IERC20Metadata } from "src/interfaces/token/IERC20Metadata.sol";

contract SwapService {
    // Constants: no SLOAD to save gas
    ISwapRouter private constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * @param _inputToken The address of the input token.
     * @param _outputToken The address of the output token.
     * @param _inputTokenAmt The amount of the input token to swap.
     * @param _amtOutMin The minimum amount of output tokens that must be received for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     * @return amtIn The amount of tokens sent to Uniswap.
     * @return amtOut The amount of tokens received from Uniswap.
     */
    function _swapExactInput(
        address _inputToken,
        address _outputToken,
        uint256 _inputTokenAmt,
        uint256 _amtOutMin,
        uint24 _poolFee
    ) internal returns (uint256 amtIn, uint256 amtOut) {
        TransferHelper.safeApprove(_inputToken, address(SWAP_ROUTER), _inputTokenAmt);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _inputToken,
            tokenOut: _outputToken,
            fee: _poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _inputTokenAmt,
            amountOutMinimum: _amtOutMin,
            sqrtPriceLimitX96: 0
        });

        amtIn = _inputTokenAmt;
        amtOut = SWAP_ROUTER.exactInputSingle(params);
    }
}

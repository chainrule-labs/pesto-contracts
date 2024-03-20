// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// Local imports
import { TransferHelper } from "src/dependencies/uniswap/TransferHelper.sol";
import { ISwapRouter } from "src/interfaces/uniswap/ISwapRouter.sol";

/// @title The swap service contract
/// @author Chain Rule, LLC
/// @notice Manages all swap-related interactions for each position
contract SwapService {
    // Constants: no SLOAD to save gas
    ISwapRouter private constant SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible.
    /// @param _inToken The address of the input token.
    /// @param _outToken The address of the output token.
    /// @param _inTokenAmt The amount of the input token to swap.
    /// @param _amtOutMin The minimum amount of output tokens that must be received for the tx to go through.
    /// @param _poolFee The fee of the Uniswap pool.
    /// @return amtIn The amount of tokens sent to Uniswap.
    /// @return amtOut The amount of tokens received from Uniswap.
    function _swapExactInput(
        address _inToken,
        address _outToken,
        uint256 _inTokenAmt,
        uint256 _amtOutMin,
        uint24 _poolFee
    ) internal returns (uint256 amtIn, uint256 amtOut) {
        TransferHelper.safeApprove(_inToken, address(SWAP_ROUTER), _inTokenAmt);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _inToken,
            tokenOut: _outToken,
            fee: _poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _inTokenAmt,
            amountOutMinimum: _amtOutMin,
            sqrtPriceLimitX96: 0
        });

        amtIn = _inTokenAmt;
        amtOut = SWAP_ROUTER.exactInputSingle(params);
    }

    /// @notice Swaps as many of input tokens as necessary for an exact amount of output tokens.
    /// @param _inToken The address of the input token.
    /// @param _outToken The address of the output token.
    /// @param _outTokenAmt The amount of output tokens to receive.
    /// @param _amtInMax Maximum permissible quantity of input tokens to be exchanged for a specified amount of output tokens.
    /// @param _poolFee The fee of the Uniswap pool.
    /// @return amtIn The amount of tokens sent to Uniswap.
    /// @return amtOut The amount of tokens received from Uniswap.
    function _swapExactOutput(
        address _inToken,
        address _outToken,
        uint256 _outTokenAmt,
        uint256 _amtInMax,
        uint24 _poolFee
    ) internal returns (uint256 amtIn, uint256 amtOut) {
        TransferHelper.safeApprove(_inToken, address(SWAP_ROUTER), _amtInMax);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _inToken,
            tokenOut: _outToken,
            fee: _poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _outTokenAmt,
            amountInMaximum: _amtInMax,
            sqrtPriceLimitX96: 0
        });

        amtIn = SWAP_ROUTER.exactOutputSingle(params);
        amtOut = _outTokenAmt;
    }
}

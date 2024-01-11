// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ISwapRouter } from "src/interfaces/uniswap/ISwapRouter.sol";
import { TransferHelper } from "src/dependencies/uniswap/TransferHelper.sol";
import { DAI, PROFIT_PERCENT, USDC, WBTC, WETH } from "test/common/Constants.t.sol";
import { IERC20Metadata, IERC20 } from "src/interfaces/token/IERC20Metadata.sol";

contract MockUniswapGains {
    function exactOutputSingle(ISwapRouter.ExactOutputSingleParams calldata params)
        public
        payable
        returns (uint256 amtIn)
    {
        uint256 callerInputTokenBalance = IERC20(params.tokenIn).balanceOf(msg.sender);
        amtIn = callerInputTokenBalance * (100 - PROFIT_PERCENT) / 100;
        uint256 amtOut = IERC20(params.tokenOut).balanceOf(address(this));
        TransferHelper.safeTransferFrom(params.tokenIn, msg.sender, address(this), amtIn);
        TransferHelper.safeTransfer(params.tokenOut, msg.sender, amtOut);
    }
}

contract MockUniswapLosses {
    function exactOutputSingle() public pure {
        revert("Insufficient input token balance.");
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params)
        public
        payable
        returns (uint256 amtOut)
    {
        amtOut = IERC20(params.tokenOut).balanceOf(address(this));
        TransferHelper.safeTransferFrom(params.tokenIn, msg.sender, address(this), params.amountIn);
        TransferHelper.safeTransfer(params.tokenOut, msg.sender, amtOut);
    }
}

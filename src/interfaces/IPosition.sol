// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IPosition {
    /* solhint-disable func-name-mixedcase */
    // Meta data
    function OWNER() external returns (address);
    function C_TOKEN() external returns (address);
    function D_TOKEN() external returns (address);
    function B_TOKEN() external returns (address);

    // Core Functions
    function short(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee) external payable;
    function close(uint24 _poolFee, bool _exactOutput, uint256 _swapAmtOutMin, uint256 _withdrawBuffer)
        external
        payable;
}

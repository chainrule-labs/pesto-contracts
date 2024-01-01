// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IAccount {
    // Meta data
    function owner() external returns (address);
    function cToken() external returns (address);
    function dToken() external returns (address);
    function bToken() external returns (address);

    // Core Functions
    function short(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee) external payable;
    function close() external;
}

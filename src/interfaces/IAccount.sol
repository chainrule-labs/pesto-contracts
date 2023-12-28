// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IAccount {
    // Meta data
    function owner() external returns (address);
    function col() external returns (address);
    function debt() external returns (address);
    function base() external returns (address);

    // Core Functions
    function addToPosition() external;
    function closePosition() external;

    // Inherited Functions
    function getNeededCollateral(uint256 _debtAmount, uint256 _ltv) external returns (uint256);
}

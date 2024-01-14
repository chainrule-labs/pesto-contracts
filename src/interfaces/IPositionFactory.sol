// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IPositionFactory {
    /* solhint-disable func-name-mixedcase */
    // Meta data
    function positions(address, address, address, address) external view returns (address);
    function positionsLookup(address) external view returns (address[] memory);

    // Core Functions
    function createPosition(address _cToken, address _dToken, address _bToken)
        external
        payable
        returns (address position);
    function getPositions(address _owner) external view returns (address[] memory);
}

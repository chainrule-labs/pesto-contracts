// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local
import { Position } from "src/Position.sol";

/// @title Position Factory
/// @author chainrule.eth
/// @notice Creates and stores user positions
contract PositionFactory {
    // Constants: no SLOAD to save gas
    address private constant CONTRACT_DEPLOYER = 0x0a5B347509621337cDDf44CBCf6B6E7C9C908CD2;

    // Factory Storage
    // positions[owner][col][debt][base] = address(positionContract)
    mapping(address => mapping(address => mapping(address => mapping(address => address)))) public positions;

    // Errors
    error Unauthorized();
    error PositionExists();

    constructor() {
        if (msg.sender != CONTRACT_DEPLOYER) revert Unauthorized();
    }

    function createPosition(address _col, address _debt, address _base) public payable returns (address position) {
        if (positions[msg.sender][_col][_debt][_base] != address(0)) revert PositionExists();

        position = address(new Position(msg.sender, _col, _debt, _base));

        positions[msg.sender][_col][_debt][_base] = position;
    }
}

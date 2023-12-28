// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local
import { Account } from "../accounts/Account.sol";

/// @title Account Factory
/// @author deloperator.eth
/// @notice Creates and stores user accounts
contract AccountFactory {
    // Constants: no SLOAD to save gas
    address private constant CONTRACT_DEPLOYER = 0x0a5B347509621337cDDf44CBCf6B6E7C9C908CD2;

    // Factory Storage
    mapping(address => mapping(address => mapping(address => mapping(address => address)))) public accounts;

    // Errors
    error Unauthorized();
    error AccountExists();

    constructor() {
        if (msg.sender != CONTRACT_DEPLOYER) revert Unauthorized();
    }

    function createAccount(address _col, address _debt, address _base) public payable returns (address account) {
        if (accounts[msg.sender][_col][_debt][_base] != address(0)) revert AccountExists();

        account = address(new Account(msg.sender, _col, _debt, _base));

        accounts[msg.sender][_col][_debt][_base] = account;
    }
}

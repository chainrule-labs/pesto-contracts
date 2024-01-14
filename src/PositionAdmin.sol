// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @title Position Admin
/// @author Chain Rule, LLC
/// @notice Defines logic that Position and DebtService both need access to.
contract PositionAdmin {
    // Immutable: no SLOAD to save gas
    address public immutable OWNER;

    constructor(address _owner) {
        OWNER = _owner;
    }

    /// @notice Check if the caller is the owner of the Position contract
    modifier onlyOwner() {
        require(OWNER == msg.sender, "Ownable: caller is not the owner");
        _;
    }
}

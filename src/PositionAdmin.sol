// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { IERC20 } from "src/interfaces/token/IERC20.sol";

/// @title Position Admin
/// @author Chain Rule, LLC
/// @notice Defines logic that Position and DebtService both need access to.
contract PositionAdmin {
    // Immutables: no SLOAD to save gas
    address public immutable OWNER;

    // Errors
    error Unauthorized();

    constructor(address _owner) {
        OWNER = _owner;
    }

    /**
     * @notice Allows owner to withdraw all of this contract's native token balance.
     */
    function extractNative() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @notice Allows owner to withdraw all of a specified ERC20 token's balance from this contract.
     * @param _token The address of token to remove.
     */
    function extractERC20(address _token) public payable onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));

        IERC20(_token).transfer(msg.sender, balance);
    }

    /**
     * @notice Executes when native is sent to this contract through a non-existent function.
     */
    fallback() external payable { } // solhint-disable-line no-empty-blocks

    /**
     * @notice Executes when native is sent to this contract with a plain transaction.
     */
    receive() external payable { } // solhint-disable-line no-empty-blocks

    /// @notice Check if the caller is the owner of the Position contract
    modifier onlyOwner() {
        if (msg.sender != OWNER) revert Unauthorized();
        _;
    }
}

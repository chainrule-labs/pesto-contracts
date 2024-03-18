// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IAdminService } from "src/interfaces/IAdminService.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

/// @title The Position admin service
/// @author Chain Rule, LLC
/// @notice Defines admin logic that Position and DebtService both need access to
contract AdminService is IAdminService {
    // Immutables: no SLOAD to save gas

    /// @notice The account address of the contract owner.
    address public immutable OWNER;

    // Errors
    error Unauthorized();

    /// @notice This function is called when the AdminService is deployed.
    /// @param _owner The account address of the AdminService contract's owner.
    constructor(address _owner) {
        OWNER = _owner;
    }

    /// @inheritdoc IAdminService
    function extractNative() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @inheritdoc IAdminService
    function extractERC20(address _token) public payable onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));

        SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, balance);
    }

    /**
     * @notice Executes when native is sent to this contract through a non-existent function.
     */
    fallback() external payable { } // solhint-disable-line no-empty-blocks

    /// @notice Check if the caller is the owner of the Position contract
    modifier onlyOwner() {
        if (msg.sender != OWNER) revert Unauthorized();
        _;
    }
}

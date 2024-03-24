// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IAdminService {
    /* solhint-disable func-name-mixedcase */

    /// @notice Returns the owner of this contract.
    function OWNER() external view returns (address);

    /* ****************************************************************************
    **
    **  ADMIN FUNCTIONS
    **
    ******************************************************************************/

    /// @notice Allows owner to withdraw all of this contract's native token balance.
    function extractNative() external payable;

    /// @notice Allows owner to withdraw all of a specified ERC20 token's balance from this contract.
    /// @param _token The address of token to remove.
    function extractERC20(address _token) external payable;
}

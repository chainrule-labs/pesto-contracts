// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IPositionFactory {
    /* solhint-disable func-name-mixedcase */
    /* ****************************************************************************
    **
    **  METADATA
    **
    ******************************************************************************/

    /// @notice The address of the Position contract for the given owner and token permutation.
    /// @dev Example: positions[owner][cToken][dToken][bToken] = position
    /// @return position The address of the corresponding Position contract.
    function positions(address _owner, address _cToken, address _dToken, address _bToken)
        external
        view
        returns (address);

    /* ****************************************************************************
    **
    **  CORE FUNCTIONS
    **
    ******************************************************************************/

    /// @notice Deploys a Position contract for msg.sender, given a _cToken, _dToken, and _bToken.
    /// @param _cToken The address of the token to be used as collateral.
    /// @param _dToken The address of the token to be borrowed.
    /// @param _bToken The address of the token to swap _dToken for.
    /// @return position The address of the newly created Position contract.
    function createPosition(address _cToken, address _dToken, address _bToken)
        external
        payable
        returns (address position);

    /// @notice Returns a list of Position contract addresses owned by the supplied _positionOwner.
    /// @param _positionOwner The owner of the Position contracts.
    /// @return positions The list of the supplied _positionOwner's Position contract addresses.
    function getPositions(address _positionOwner) external view returns (address[] memory);

    /* ****************************************************************************
    **
    **  ADMIN FUNCTIONS
    **
    ******************************************************************************/

    /// @notice Allows OWNER to withdraw all of this contract's native token balance.
    /// @dev This function is only callable by the owner account.
    function extractNative() external payable;

    /// @notice Allows OWNER to withdraw all of a specified ERC20 token's balance from this contract.
    /// @dev This function is only callable by the owner account.
    /// @param _token The address of token to remove.
    function extractERC20(address _token) external payable;
}

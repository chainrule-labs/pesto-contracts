// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IPositionFactory {
    /* solhint-disable func-name-mixedcase */
    /* ****************************************************************************
    **
    **  METADATA
    **
    ******************************************************************************/

    /**
     * @notice Returns the owner of this contract.
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the address of an owner's specified Position contract.
     */
    function positions(address _owner, address _cToken, address _dToken, address _bToken)
        external
        view
        returns (address);

    /**
     * @notice Returns an indexed contract addresses from the list of contracts for the given owner.
     *         Direct external calls to this mapping require an index to retrieve
     *         a specific address. To get the full array, call getPositions().
     */
    function positionsLookup(address _owner) external view returns (address[] memory);

    /* ****************************************************************************
    **
    **  CORE FUNCTIONS
    **
    ******************************************************************************/
    /**
     * @notice Deploys a Position contract for msg.sender, given a _cToken, _dToken, and _bToken.
     * @param _cToken The address of the token to be used as collateral.
     * @param _dToken The address of the token to be borrowed.
     * @param _bToken The address of the token to swap _dToken for.
     */
    function createPosition(address _cToken, address _dToken, address _bToken)
        external
        payable
        returns (address position);

    /**
     * @notice Returns a list of contract addresses for the given _positionOwner.
     * @param _positionOwner The owner of the Position contracts.
     */
    function getPositions(address _positionOwner) external view returns (address[] memory);

    /* ****************************************************************************
    **
    **  ADMIN FUNCTIONS
    **
    ******************************************************************************/
    /**
     * @notice Allows owner to withdraw all of this contract's native token balance.
     */
    function extractNative() external payable;

    /**
     * @notice Allows owner to withdraw all of a specified ERC20 token's balance from this contract.
     * @param _token The address of token to remove.
     */
    function extractERC20(address _token) external payable;
}

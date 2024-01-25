// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IFeeCollector {
    /* solhint-disable func-name-mixedcase */
    /* ****************************************************************************
    **
    **  CORE FUNCTIONS
    **
    ******************************************************************************/
    /**
     * @notice Returns the owner of this contract.
     */
    function owner() external returns (address);

    /**
     * @notice Returns the current client rate.
     */
    function clientRate() external returns (uint256);

    /**
     * @notice Returns the total balance for the specified token across all client operators.
     * @param _token The token address to check.
     * @return balance The total balance for the specified token across all client operators.
     */
    function totalClientBalances(address _token) external view returns (uint256);

    /**
     * @notice Returns the balance for the specified token for the specified client operator.
     * @param _client A client operator address.
     * @param _token The token address to check.
     * @return balance The balance for the specified token for the specified client operator.
     */
    function balances(address _client, address _token) external view returns (uint256);

    /**
     * @notice Collects fees from Position contracts when collateral is added.
     * @param _client The address, controlled by client operators, for receiving protocol fees.
     * @param _token The token to collect fees in (the collateral token of the calling Position contract).
     * @param _amt The total amount of fees to collect.
     */
    function collectFees(address _client, address _token, uint256 _amt) external payable;
    /**
     * @notice Withdraw collected fees from this contract.
     * @param _token The token address to withdraw.
     */
    function clientWithdraw(address _token) external payable;

    /* ****************************************************************************
    **
    **  ADMIN FUNCTIONS
    **
    ******************************************************************************/
    /**
     * @notice Allows owner to set client rate.
     * @param _clientRate The percentage of total transaction-specific protocol fee, allocated to the utilized client.
     */
    function setClientRate(uint256 _clientRate) external payable;

    /**
     * @notice Allows owner to withdraw all of this contract's native token balance.
     */
    function extractNative() external payable;

    /**
     * @notice Allows owner to withdraw protocol fees from this contract.
     * @param _token The address of token to remove.
     */
    function extractERC20(address _token) external payable;
}

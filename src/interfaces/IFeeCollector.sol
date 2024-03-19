// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IFeeCollector {
    /* solhint-disable func-name-mixedcase */
    /* ****************************************************************************
    **
    **  CORE FUNCTIONS
    **
    ******************************************************************************/

    /// @notice The maximum percentage of protocol fees allocated to clients.
    function clientRate() external view returns (uint256);

    /// @notice Returns the take rate of the specified client operator (% of client rate that the operator keeps).
    /// @dev Example: clientTakeRates[client] = clientTakeRate
    /// @param _client A client operator address.
    /// @return clientTakeRate The percentage of the client rate that the operator keeps.
    function clientTakeRates(address _client) external view returns (uint256);

    /// @notice Returns the total balance for the specified token across all client operators.
    /// @dev Example: totalClientBalances[token] = totalClientBalance
    /// @param _token The token address to check.
    /// @return balance The total balance for the specified token across all client operators.
    function totalClientBalances(address _token) external view returns (uint256);

    /// @notice Returns the balance for the specified token for the specified client operator.
    /// @dev Example: balances[client][token] = clientBalance
    /// @param _client A client operator address.
    /// @param _token The token address to check.
    /// @return balance The balance for the specified token for the specified client operator.
    function balances(address _client, address _token) external view returns (uint256);

    /// @notice Returns the current protocol fee rate.
    function feeRate() external view returns (uint256);

    /// @notice Collects fees from Position contracts.
    /// @param _client The address where a client operator will receive protocols fees.
    /// @param _token The token to collect fees in (collateral token or debt token of the calling Position contract).
    /// @param _amt The total amount of fees to collect.
    function collectFees(address _client, address _token, uint256 _amt, uint256 _clientFee) external payable;

    /// @notice Withdraw collected fees from this contract.
    /// @param _token The token address to withdraw.
    function clientWithdraw(address _token) external payable;

    /// @notice Allows clients to set the percentage of clientRate they receive each revenue-generating tx.
    /// @dev Amounts less than 100 will give the calling client's users a protocol fee discount.
    /// @param _clientTakeRate The percentage of clientRate the client receives (100 = 100%).
    function setClientTakeRate(uint256 _clientTakeRate) external payable;

    /// @notice Returns discount amount and client fees when using the provided client.
    /// @param _client The address where a client operator will receive protocols fees.
    /// @param _maxFee The maximum amount of fees the protocol will collect.
    /// @return userSavings The amount of fees discounted from the protocol fee.
    /// @return clientFee The amount of fees the client will receive.
    function getClientAllocations(address _client, uint256 _maxFee)
        external
        view
        returns (uint256 userSavings, uint256 clientFee);

    /* ****************************************************************************
    **
    **  ADMIN FUNCTIONS
    **
    ******************************************************************************/

    /// @notice Allows owner to set client rate.
    /// @dev This function is only callable by the owner account.
    /// @param _clientRate The percentage of total transaction-specific protocol fee, allocated to the utilized client.
    function setClientRate(uint256 _clientRate) external payable;

    /// @notice Allows owner to withdraw all of this contract's native token balance.
    /// @dev This function is only callable by the owner account.
    function extractNative() external payable;

    /// @notice Allows owner to withdraw protocol fees from this contract.
    /// @dev This function is only callable by the owner account.
    /// @param _token The address of token to remove.
    function extractERC20(address _token) external payable;
}

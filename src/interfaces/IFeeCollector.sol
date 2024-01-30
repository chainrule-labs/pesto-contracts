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
     * @param _client The address where a client operator will receive protocols fees.
     * @param _token The token to collect fees in (the collateral token of the calling Position contract).
     * @param _amt The total amount of fees to collect.
     */
    function collectFees(address _client, address _token, uint256 _amt, uint256 _clientFee) external payable;
    /**
     * @notice Withdraw collected fees from this contract.
     * @param _token The token address to withdraw.
     */
    function clientWithdraw(address _token) external payable;

    /**
     * @notice Allows clients to set the percentage of the clientRate they will receive each revenue-generating tx.
     *         Amounts less than 100 will give the calling client's users a protocol fee discount:
     *         clientTakeRateOfProtocolFee = clientRate * _clientTakeRate
     *              ex: _clientTakeRate = 50% -> clientTakeRate = clientRate * 0.5
     *         userTakeRateOfProtocolFee =  clientRate * (1 - _clientTakeRate)
     *              ex: _clientTakeRate = 50% -> userTakeRate = clientRate * (1 - 0.5)
     *         clientFee = protocolFee * clientTakeRateOfProtocolFee
     *         userSavings = protocolFee * userTakeRateOfProtocolFee
     * @param _clientTakeRate The percentage of the clientRate the client will receive each revenue-generating tx (100 = 100%).
     */
    function setClientTakeRate(uint256 _clientTakeRate) external payable;

    /**
     * @notice Returns the amount discounted from the protocol fee by using the provided client.
     * @param _client The address where a client operator will receive protocols fees.
     * @param _protocolFee The maximum amount of fees the protocol will collect.
     */
    function getClientAllocations(address _client, uint256 _protocolFee)
        external
        view
        returns (uint256 userSavings, uint256 clientFee);

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

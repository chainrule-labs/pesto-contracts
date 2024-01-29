// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { Ownable } from "src/dependencies/access/Ownable.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

/// @title FeeCollector
/// @author Chain Rule, LLC
/// @notice Collects protocol fees
contract FeeCollector is Ownable {
    // Constants: no SLOAD to save gas
    address private constant CONTRACT_DEPLOYER = 0x0a5B347509621337cDDf44CBCf6B6E7C9C908CD2;

    // Storage
    uint256 public clientRate;
    mapping(address => uint256) public clientTakeRates;
    mapping(address => uint256) public totalClientBalances;
    mapping(address => mapping(address => uint256)) public balances;

    // Errors
    error Unauthorized();
    error OutOfRange();

    constructor(address _owner) Ownable(_owner) {
        if (msg.sender != CONTRACT_DEPLOYER) revert Unauthorized();
    }

    /**
     * @notice Collects fees from Position contracts when collateral is added.
     * @param _client The address where a client operator will receive protocols fees.
     * @param _token The token to collect fees in (the collateral token of the calling Position contract).
     * @param _amt The total amount of fees to collect.
     */
    function collectFees(address _client, address _token, uint256 _amt) external payable {
        // 1. Transfer tokens to this contract
        SafeTransferLib.safeTransferFrom(ERC20(_token), msg.sender, address(this), _amt);

        // 2. Update client balances
        if (_client != address(0)) {
            uint256 clientFee = (_amt * clientRate) / 100;
            balances[_client][_token] += clientFee;
            totalClientBalances[_token] += clientFee;
        }
    }

    /**
     * @notice Withdraw collected fees from this contract.
     * @param _token The token address to withdraw.
     */
    function clientWithdraw(address _token) public payable {
        uint256 withdrawAmt = balances[msg.sender][_token];

        // 1. Update accounting
        balances[msg.sender][_token] -= withdrawAmt;
        totalClientBalances[_token] -= withdrawAmt;

        // 2. Transfer tokens to msg.sender
        SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, withdrawAmt);
    }

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
    function setClientTakeRate(uint256 _clientTakeRate) public payable {
        if (_clientTakeRate > 100) revert OutOfRange();
        clientTakeRates[msg.sender] = _clientTakeRate;
    }

    /**
     * @notice Returns the amount discounted from the protocol fee by using the provided client.
     * @param _client The address where a client operator will receive protocols fees.
     * @param _maxFee The maximum amount of fees the protocol will collect.
     */
    function getUserSavings(address _client, uint256 _maxFee) public view returns (uint256 userSavings) {
        uint256 userTakeRate = 100 - clientTakeRates[_client];
        uint256 userPercentOfProtocolFee = (userTakeRate * clientRate) / 100;
        userSavings = (userPercentOfProtocolFee * _maxFee) / 100;
    }

    /* ****************************************************************************
    **
    **  Admin Functions
    **
    ******************************************************************************/

    /**
     * @notice Allows owner to set client rate.
     * @param _clientRate The percentage of total transaction-specific protocol fee, allocated to the utilized client.
     */
    function setClientRate(uint256 _clientRate) public payable onlyOwner {
        if (_clientRate < 30 || _clientRate > 100) revert OutOfRange();

        clientRate = _clientRate;
    }

    /**
     * @notice Allows OWNER to withdraw all of this contract's native token balance.
     */
    function extractNative() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @notice Allows owner to withdraw protocol fees from this contract.
     * @param _token The address of token to remove.
     */
    function extractERC20(address _token) public payable onlyOwner {
        uint256 withdrawAmt = IERC20(_token).balanceOf(address(this)) - totalClientBalances[_token];

        SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, withdrawAmt);
    }

    /**
     * @notice Executes when native is sent to this contract through a non-existent function.
     */
    fallback() external payable { } // solhint-disable-line no-empty-blocks

    /**
     * @notice Executes when native is sent to this contract with a plain transaction.
     */
    receive() external payable { } // solhint-disable-line no-empty-blocks
}

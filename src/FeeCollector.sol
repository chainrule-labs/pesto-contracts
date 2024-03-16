// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { Ownable } from "src/dependencies/access/Ownable.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

/// @title The fee collector contract
/// @author Chain Rule, LLC
/// @notice Collects all protocol fees
contract FeeCollector is Ownable, IFeeCollector {
    // Constants: no SLOAD to save gas
    address private constant CONTRACT_DEPLOYER = 0x0a5B347509621337cDDf44CBCf6B6E7C9C908CD2;

    // Storage
    /// @inheritdoc IFeeCollector
    uint256 public clientRate;

    /// @inheritdoc IFeeCollector
    mapping(address => uint256) public clientTakeRates;

    /// @inheritdoc IFeeCollector
    mapping(address => uint256) public totalClientBalances;

    /// @inheritdoc IFeeCollector
    mapping(address => mapping(address => uint256)) public balances;

    // Errors
    error Unauthorized();
    error OutOfRange();

    /// @notice This function is called when the FeeCollector is deployed.
    /// @param _owner The account address of the FeeCollector contract's owner.
    constructor(address _owner) Ownable(_owner) {
        if (msg.sender != CONTRACT_DEPLOYER) revert Unauthorized();
    }

    /// @inheritdoc IFeeCollector
    function collectFees(address _client, address _token, uint256 _amt, uint256 _clientFee) external payable {
        // 1. Transfer tokens to this contract
        SafeTransferLib.safeTransferFrom(ERC20(_token), msg.sender, address(this), _amt);

        // 2. Update client balances
        if (_client != address(0)) {
            // Cannot overflow because the sum of all client balances can't exceed the max uint256 value.
            unchecked {
                balances[_client][_token] += _clientFee;
                totalClientBalances[_token] += _clientFee;
            }
        }
    }

    /// @inheritdoc IFeeCollector
    function clientWithdraw(address _token) public payable {
        uint256 withdrawAmt = balances[msg.sender][_token];

        // 1. Update accounting
        balances[msg.sender][_token] -= withdrawAmt;
        totalClientBalances[_token] -= withdrawAmt;

        // 2. Transfer tokens to msg.sender
        SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, withdrawAmt);
    }

    /// @inheritdoc IFeeCollector
    function setClientTakeRate(uint256 _clientTakeRate) public payable {
        if (_clientTakeRate > 100) revert OutOfRange();
        clientTakeRates[msg.sender] = _clientTakeRate;
    }

    /// @inheritdoc IFeeCollector
    function getClientAllocations(address _client, uint256 _maxFee)
        public
        view
        returns (uint256 userSavings, uint256 clientFee)
    {
        // 1. Calculate user savings
        uint256 userTakeRate = 100 - clientTakeRates[_client];
        uint256 userPercentOfProtocolFee = (userTakeRate * clientRate);
        userSavings = (userPercentOfProtocolFee * _maxFee) / 1e4;

        // 2. Calculate client fee
        uint256 maxClientFee = (_maxFee * clientRate) / 100;
        clientFee = maxClientFee - userSavings;
    }

    /* ****************************************************************************
    **
    **  Admin Functions
    **
    ******************************************************************************/

    /// @inheritdoc IFeeCollector
    function setClientRate(uint256 _clientRate) public payable onlyOwner {
        if (_clientRate < 30 || _clientRate > 100) revert OutOfRange();

        clientRate = _clientRate;
    }

    /// @inheritdoc IFeeCollector
    function extractNative() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @inheritdoc IFeeCollector
    function extractERC20(address _token) public payable onlyOwner {
        uint256 withdrawAmt = IERC20(_token).balanceOf(address(this)) - totalClientBalances[_token];

        SafeTransferLib.safeTransfer(ERC20(_token), msg.sender, withdrawAmt);
    }
}

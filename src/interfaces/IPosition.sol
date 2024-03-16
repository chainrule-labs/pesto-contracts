// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IDebtService } from "src/interfaces/IDebtService.sol";

interface IPosition is IDebtService {
    /* solhint-disable func-name-mixedcase */
    /* ****************************************************************************
    **
    **  METADATA
    **
    ******************************************************************************/

    /// @notice Returns the address of this position's base token (the token that the debt token is swapped for when shorting).
    function B_TOKEN() external view returns (address);

    /// @notice Returns the number of decimals this position's base token is denominated in.
    function B_DECIMALS() external view returns (uint8);

    /* ****************************************************************************
    **
    **  CORE FUNCTIONS
    **
    ******************************************************************************/

    /// @notice Adds to this contract's position.
    /// @param _cAmt The amount of collateral token to be supplied for this transaction-specific loan (units: C_DECIMALS).
    /// @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
    /// @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
    /// @param _poolFee The fee of the Uniswap pool.
    /// @param _client The address of the client operator. Use address(0) if not using a client.
    function add(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee, address _client)
        external
        payable;

    /// @notice Adds to this contract's position with permit, obviating the need for a separate approve tx.
    ///         This function can only be used for ERC-2612-compliant tokens.
    /// @param _cAmt The amount of collateral token to be supplied for this transaction-specific loan (units: C_DECIMALS).
    /// @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
    /// @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
    /// @param _poolFee The fee of the Uniswap pool.
    /// @param _client The address of the client operator. Use address(0) if not using a client.
    /// @param _deadline The expiration timestamp of the permit.
    /// @param _v The V parameter of ERC712 signature for the permit.
    /// @param _r The R parameter of ERC712 signature for the permit.
    /// @param _s The S parameter of ERC712 signature for the permit.
    function addWithPermit(
        uint256 _cAmt,
        uint256 _ltv,
        uint256 _swapAmtOutMin,
        uint24 _poolFee,
        address _client,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable;

    /// @notice Adds leverage to this contract's position.
    /// @param _dAmt The amount of D_TOKEN to borrow; use position LTV to identify max amount.
    /// @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
    /// @param _poolFee The fee of the Uniswap pool.
    /// @param _client The address of the client operator. Use address(0) if not using a client.
    function addLeverage(uint256 _dAmt, uint256 _swapAmtOutMin, uint24 _poolFee, address _client) external payable;

    /// @notice Fully closes the position.
    /// @param _poolFee The fee of the Uniswap pool.
    /// @param _exactOutput Whether to swap exact output or exact input (true for exact output, false for exact input).
    /// @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through (only used if _exactOutput is false, supply 0 if true).
    /// @param _withdrawCAmt The amount of C_TOKEN to withdraw (units: C_DECIMALS).
    /// @param _withdrawBAmt The amount of B_TOKEN to withdraw (units: B_DECIMALS).
    function close(
        uint24 _poolFee,
        bool _exactOutput,
        uint256 _swapAmtOutMin,
        uint256 _withdrawCAmt,
        uint256 _withdrawBAmt
    ) external payable;
}

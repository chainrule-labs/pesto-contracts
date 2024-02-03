// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IPosition {
    /* solhint-disable func-name-mixedcase */
    /* ****************************************************************************
    **
    **  METADATA
    **
    ******************************************************************************/
    /**
     * @notice Returns the owner of this contract.
     */
    function OWNER() external view returns (address);
    /**
     * @notice Returns the address of this position's collateral token.
     */
    function C_TOKEN() external view returns (address);
    /**
     * @notice Returns the address of this position's debt token.
     */
    function D_TOKEN() external view returns (address);
    /**
     * @notice Returns the address of this position's base token (the token that the debt token is swapped for when shorting).
     */
    function B_TOKEN() external view returns (address);

    /**
     * @notice Returns the address of the FeeCollector contract, which is responsible for collecting and allocating protocol fees.
     */
    function FEE_COLLECTOR() external view returns (address);

    /**
     * @notice Returns the maximum percentage of the collateral token that the protocol charges each revenue-generating transaction.
     */
    function PROTOCOL_FEE_RATE() external view returns (uint256);

    /**
     * @notice Returns the number of decimals for this position's collateral token.
     */
    function C_DECIMALS() external view returns (uint8);

    /**
     * @notice Returns the number of decimals for this position's debt token.
     */
    function D_DECIMALS() external view returns (uint8);

    /**
     * @notice Returns the number of decimals for this position's base token.
     */
    function B_DECIMALS() external view returns (uint8);

    /* ****************************************************************************
    **
    **  CORE FUNCTIONS
    **
    ******************************************************************************/
    /**
     * @notice Adds to this contract's position.
     * @param _cAmt The amount of collateral token to be supplied for this transaction-specific loan (units: C_DECIMALS).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _client The address of the client operator. Use address(0) if not using a client.
     */
    function add(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee, address _client)
        external
        payable;

    /**
     * @notice Adds to this contract's position with permit, obviating the need for a separate approve tx.
     *         This function can only be used for ERC-2612-compliant tokens.
     * @param _cAmt The amount of collateral token to be supplied for this transaction-specific loan (units: C_DECIMALS).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _client The address of the client operator. Use address(0) if not using a client.
     * @param _deadline The expiration timestamp of the permit.
     * @param _v The V parameter of ERC712 signature for the permit.
     * @param _r The R parameter of ERC712 signature for the permit.
     * @param _s The S parameter of ERC712 signature for the permit.
     */
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

    /**
     * @notice Adds leverage to this contract's position. This function can only be used for positions where the
     *         collateral token is the same as the base token.
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _client The address of the client operator. Use address(0) if not using a client.
     */
    function addLeverage(uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee, address _client) external payable;

    /**
     * @notice Fully closes the position.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _exactOutput Whether to swap exact output or exact input (true for exact output, false for exact input).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through (only used if _exactOutput is false, supply 0 if true).
     * @param _withdrawBuffer The amount of collateral, in USD, left as safety buffer for tx to go through (at least 100_000 recommended, units: 8 decimals).
     */
    function close(uint24 _poolFee, bool _exactOutput, uint256 _swapAmtOutMin, uint256 _withdrawBuffer)
        external
        payable;

    /**
     * @notice Increases the collateral amount backing this contract's loan.
     * @param _cAmt The amount of collateral to be supplied (units: C_DECIMALS).
     */
    function addCollateral(uint256 _cAmt) external payable;

    /**
     * @notice Increases the collateral amount for this contract's loan with permit,
     *         obviating the need for a separate approve tx. This function can only be used for ERC-2612-compliant tokens.
     * @param _cAmt The amount of collateral to be supplied (units: C_DECIMALS).
     * @param _deadline The expiration timestamp of the permit.
     * @param _v The V parameter of ERC712 signature for the permit.
     * @param _r The R parameter of ERC712 signature for the permit.
     * @param _s The S parameter of ERC712 signature for the permit.
     */
    function addCollateralWithPermit(uint256 _cAmt, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s)
        external
        payable;

    /**
     * @notice Withdraws collateral token from Aave to specified recipient.
     * @param _recipient The recipient of the funds.
     * @param _cAmt The amount of collateral to be withdrawn (units: C_DECIMALS). Add a small buffer if withdrawing max amount.
     */
    function withdraw(address _recipient, uint256 _cAmt) external payable;

    /**
     * @notice Repays any outstanding debt to Aave and transfers remaining collateral from Aave to owner.
     * @param _dAmt The amount of debt token to repay to Aave (units: D_DECIMALS).
     *              To pay off entire debt, _dAmt = debtOwed + smallBuffer (to account for interest).
     * @param _withdrawBuffer The amount of collateral, in USD, left as safety buffer for tx to go through (at least 100_000 recommended, units: 8 decimals).
     */
    function repayAndWithdraw(uint256 _dAmt, uint256 _withdrawBuffer) external payable;

    /**
     * @notice Repays any outstanding debt to Aave and transfers remaining collateral from Aave to owner,
     *         with permit, obviating the need for a separate approve tx. This function can only be used for ERC-2612-compliant tokens.
     * @param _dAmt The amount of debt token to repay to Aave (units: D_DECIMALS).
     *              To pay off entire debt, _dAmt = debtOwed + smallBuffer (to account for interest).
     * @param _withdrawBuffer The amount of collateral, in USD, left as safety buffer for tx to go through (at least 100_000 recommended, units: 8 decimals).
     * @param _deadline The expiration timestamp of the permit.
     * @param _v The V parameter of ERC712 signature for the permit.
     * @param _r The R parameter of ERC712 signature for the permit.
     * @param _s The S parameter of ERC712 signature for the permit.
     */
    function repayAndWithdrawWithPermit(
        uint256 _dAmt,
        uint256 _withdrawBuffer,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable;

    /**
     * @notice Calculates the maximum amount of collateral that can be withdrawn.
     * @param _buffer The amount of collateral, in USD, left as safety buffer for tx to go through (at least 100_000 recommended, units: 8 decimals).
     * @return maxWithdrawAmt The maximum amount of collateral that can be withdrawn (units: C_DECIMALS).
     * uint256 cNeededUSD = (dTotalUSD * 1e4) / liqThreshold;
     * uint256 maxWithdrawUSD = cTotalUSD - cNeededUSD - _buffer; (units: 8 decimals)
     * maxWithdrawAmt = (maxWithdrawUSD * 10 ** (C_DECIMALS)) / cPriceUSD; (units: C_DECIMALS)
     * Docs: https://docs.aave.com/developers/guides/liquidations#how-is-health-factor-calculated
     */
    function getMaxWithdrawAmt(uint256 _buffer) external view returns (uint256 maxWithdrawAmt);

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

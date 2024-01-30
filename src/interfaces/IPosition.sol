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
    function OWNER() external returns (address);
    /**
     * @notice Returns the address of this position's collateral token.
     */
    function C_TOKEN() external returns (address);
    /**
     * @notice Returns the address of this position's debt token.
     */
    function D_TOKEN() external returns (address);
    /**
     * @notice Returns the address of this position's base token (the token that the debt token is swapped for when shorting).
     */
    function B_TOKEN() external returns (address);

    /* ****************************************************************************
    **
    **  CORE FUNCTIONS
    **
    ******************************************************************************/
    /**
     * @notice Adds to this contract's short position.
     * @param _cAmt The amount of collateral token to be supplied for this transaction-specific loan (units: C_DECIMALS).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _client The address of the client operator. Use address(0) if not using a client.
     */
    function short(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee, address _client)
        external
        payable;

    /**
     * @notice Adds to this contract's short position with permit, obviating the need for a separate approve tx.
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
    function shortWithPermit(
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
     * @notice Fully closes the short position.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _exactOutput Whether to swap exact output or exact input (true for exact output, false for exact input).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through (only used if _exactOutput is false, supply 0 if true).
     * @param _withdrawBuffer The amount of collateral left as safety buffer for tx to go through (default = 100_000, units: 8 decimals).
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
     * @notice Increases the collateral amount for this contract's loan with permit, obviating the need for a separate approve tx.
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
     * @notice Repays any outstanding debt to Aave and transfers remaining collateral from Aave to owner.
     * @param _dAmt The amount of debt token to repay to Aave (units: D_DECIMALS).
     *              To pay off entire debt, _dAmt = debtOwed + smallBuffer (to account for interest).
     * @param _withdrawBuffer The amount of collateral left as safety buffer for tx to go through (default = 100_000, units: 8 decimals).
     */
    function repayAfterClose(uint256 _dAmt, uint256 _withdrawBuffer) external payable;

    /**
     * @notice Repays any outstanding debt to Aave and transfers remaining collateral from Aave to owner,
     *         with permit, obviating the need for a separate approve tx.
     * @param _dAmt The amount of debt token to repay to Aave (units: D_DECIMALS).
     *              To pay off entire debt, _dAmt = debtOwed + smallBuffer (to account for interest).
     * @param _withdrawBuffer The amount of collateral left as safety buffer for tx to go through (default = 100_000, units: 8 decimals).
     * @param _deadline The expiration timestamp of the permit.
     * @param _v The V parameter of ERC712 signature for the permit.
     * @param _r The R parameter of ERC712 signature for the permit.
     * @param _s The S parameter of ERC712 signature for the permit.
     */
    function repayAfterCloseWithPermit(
        uint256 _dAmt,
        uint256 _withdrawBuffer,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable;

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

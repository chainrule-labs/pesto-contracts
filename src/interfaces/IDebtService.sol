// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IAdminService } from "src/interfaces/IAdminService.sol";

interface IDebtService is IAdminService {
    /* solhint-disable func-name-mixedcase */

    /// @notice Returns the number of decimals this position's collateral token is denominated in.
    function C_DECIMALS() external view returns (uint8);

    /// @notice Returns the number of decimals this position's debt token is denominated in.
    function D_DECIMALS() external view returns (uint8);

    /// @notice Returns the address of this position's collateral token.
    function C_TOKEN() external view returns (address);

    /// @notice Returns the address of this position's debt token.
    function D_TOKEN() external view returns (address);

    /// @notice Increases the collateral amount backing this contract's loan.
    /// @param _cAmt The amount of collateral to be supplied (units: C_DECIMALS).
    function addCollateral(uint256 _cAmt) external payable;

    /// @notice Increases the collateral amount for this contract's loan with permit (no separate approve tx).
    /// @dev This function can only be used for ERC-2612-compliant tokens.
    /// @param _cAmt The amount of collateral to be supplied (units: C_DECIMALS).
    /// @param _deadline The expiration timestamp of the permit.
    /// @param _v The V parameter of ERC712 signature for the permit.
    /// @param _r The R parameter of ERC712 signature for the permit.
    /// @param _s The S parameter of ERC712 signature for the permit.
    function addCollateralWithPermit(uint256 _cAmt, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s)
        external
        payable;

    /// @notice Withdraws collateral from Aave to the specified recipient.
    /// @param _token The address of the collateral token to be withdrawn (C_TOKEN or B_TOKEN).
    /// @param _amt The amount of collateral to be withdrawn (units: C_DECIMALS or B_DECIMALS).
    /// @param _recipient The recipient of the funds.
    function withdraw(address _token, uint256 _amt, address _recipient) external payable;

    /// @notice Repays outstanding debt to Aave.
    /// @dev To pay off entire debt, _dAmt = debtOwed + smallBuffer (to account for interest).
    /// @param _dAmt The amount of debt token to repay to Aave (units: D_DECIMALS).
    function repay(uint256 _dAmt) external payable;

    /// @notice Repays outstanding debt to Aave with permit (no separate approve tx).
    /// @dev This function can only be used for ERC-2612-compliant tokens.
    /// @dev To pay off entire debt, _dAmt = debtOwed + smallBuffer (to account for interest).
    /// @param _dAmt The amount of debt token to repay to Aave (units: D_DECIMALS).
    /// @param _deadline The expiration timestamp of the permit.
    /// @param _v The V parameter of ERC712 signature for the permit.
    /// @param _r The R parameter of ERC712 signature for the permit.
    /// @param _s The S parameter of ERC712 signature for the permit.
    function repayWithPermit(uint256 _dAmt, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external payable;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { AdminService } from "src/services/AdminService.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { IPool } from "src/interfaces/aave/IPool.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IERC20Permit } from "src/interfaces/token/IERC20Permit.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IERC20Metadata } from "src/interfaces/token/IERC20Metadata.sol";

/// @title DebtService
/// @author Chain Rule, LLC
/// @notice Manages all debt-related interactions
contract DebtService is AdminService {
    // Constants: no SLOAD to save gas
    address private constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address private constant AAVE_ORACLE = 0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7;

    // Immutables: no SLOAD to save gas
    uint64 internal immutable _C_DEC_CONVERSION;
    uint64 internal immutable _D_DEC_CONVERSION;
    uint8 public immutable C_DECIMALS;
    uint8 public immutable D_DECIMALS;
    address public immutable C_TOKEN;
    address public immutable D_TOKEN;

    // Errors
    error TokenUnsupported();

    constructor(address _owner, address _cToken, address _dToken) AdminService(_owner) {
        C_TOKEN = _cToken;
        D_TOKEN = _dToken;
        C_DECIMALS = IERC20Metadata(_cToken).decimals();
        D_DECIMALS = IERC20Metadata(_dToken).decimals();
        _C_DEC_CONVERSION = uint64(10 ** (18 - C_DECIMALS));
        _D_DEC_CONVERSION = uint64(10 ** (18 - D_DECIMALS));
    }

    /**
     * @notice Borrows debt token from Aave.
     * @param _cAmt The amount of collateral to be supplied (units: C_DECIMALS).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @return dAmt The amount of the debt token borrowed (units: D_DECIMALS).
     * @dev dAmt is calculated as follows:
     * c_amt_wei = _cAmt * _C_DEC_CONVERSION (decimals: 18)
     * c_amt_usd = c_amt_wei * cPrice (decimals: 18 + 8 => 26)
     * debt_amt_usd = c_amt_usd * _ltv / 100 (decimals: 26)
     * debt_amt_usd_d_decimals = debt_amt_usd / _D_DEC_CONVERSION (decimals: 26 - (18 - D_DECIMALS))
     * dAmt = debt_amt_d_decimals = debt_amt_usd_d_decimals / dPrice (decimals: D_DECIMALS)
     */
    function _takeLoan(uint256 _cAmt, uint256 _ltv) internal returns (uint256 dAmt) {
        // 1. Supply collateral to Aave
        SafeTransferLib.safeApprove(ERC20(C_TOKEN), AAVE_POOL, _cAmt);
        IPool(AAVE_POOL).supply(C_TOKEN, _cAmt, address(this), 0);

        // 2. Get asset prices USD
        uint256 cPrice = IAaveOracle(AAVE_ORACLE).getAssetPrice(C_TOKEN);
        uint256 dPrice = IAaveOracle(AAVE_ORACLE).getAssetPrice(D_TOKEN);

        // 3. Calculate debt dAmt
        dAmt = (_cAmt * cPrice * uint256(_C_DEC_CONVERSION) * _ltv) / (100 * dPrice * uint256(_D_DEC_CONVERSION));

        // 4. Borrow
        _borrow(dAmt);
    }

    /**
     * @notice Borrows debt token from Aave.
     * @param _dAmt The amount of the debt token to be borrowed (units: D_DECIMALS).
     */
    function _borrow(uint256 _dAmt) internal {
        IPool(AAVE_POOL).borrow(D_TOKEN, dAmt, 2, 0, address(this));
    }

    /**
     * @notice Repays debt token to Aave.
     * @param _dAmt The amount of debt token to repay to Aave.
     */
    function _repay(uint256 _dAmt) internal {
        SafeTransferLib.safeApprove(ERC20(D_TOKEN), AAVE_POOL, _dAmt);
        IPool(AAVE_POOL).repay(D_TOKEN, _dAmt, 2, address(this));
    }

    /**
     * @notice Returns this contract's total debt (principle + interest).
     * @return outstandingDebt This contract's total debt + small buffer (units: D_DECIMALS).
     */
    function _getDebtAmt() internal view returns (uint256) {
        address variableDebtTokenAddress = IPool(AAVE_POOL).getReserveData(D_TOKEN).variableDebtTokenAddress;
        /// @dev add 2 units as a buffer to debt amount to ensure a full repayment (units: D_DECIMALS)
        return IERC20(variableDebtTokenAddress).balanceOf(address(this)) + 2;
    }

    /**
     * @notice Increases the collateral amount backing this contract's loan.
     * @param _cAmt The amount of collateral to be supplied (units: C_DECIMALS).
     */
    function addCollateral(uint256 _cAmt) public payable onlyOwner {
        // 1. Transfer collateral from owner to this contract
        SafeTransferLib.safeTransferFrom(ERC20(C_TOKEN), msg.sender, address(this), _cAmt);

        // 2. Approve Aave to spend _cAmt of this contract's C_TOKEN
        SafeTransferLib.safeApprove(ERC20(C_TOKEN), AAVE_POOL, _cAmt);

        // 3. Supply collateral to Aave
        IPool(AAVE_POOL).supply(C_TOKEN, _cAmt, address(this), 0);
    }

    /**
     * @notice Increases the collateral amount for this contract's loan with permit, obviating the need for a separate approve tx.
     *         This function can only be used for ERC-2612-compliant tokens.
     * @param _cAmt The amount of collateral to be supplied (units: C_DECIMALS).
     * @param _deadline The expiration timestamp of the permit.
     * @param _v The V parameter of ERC712 signature for the permit.
     * @param _r The R parameter of ERC712 signature for the permit.
     * @param _s The S parameter of ERC712 signature for the permit.
     */
    function addCollateralWithPermit(uint256 _cAmt, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s)
        public
        payable
        onlyOwner
    {
        // 1. Approve with permit
        IERC20Permit(C_TOKEN).permit(msg.sender, address(this), _cAmt, _deadline, _v, _r, _s);

        // 2. Add Collateral
        addCollateral(_cAmt);
    }

    /**
     * @notice Supplies the contract's base token balance as collateral.
     * @param _bToken The address of the base token to be supplied as collateral.
     * @param _bAmt The amount of collateral to be supplied (units: D_DECIMALS).
     */
    function _supplyBase(address _bToken, uint256 _bAmt) internal onlyOwner {
        // 1. Approve Aave to spend _cAmt of this contract's C_TOKEN
        SafeTransferLib.safeApprove(ERC20(_bToken), AAVE_POOL, _bAmt);

        // 2. Supply collateral to Aave
        IPool(AAVE_POOL).supply(_bToken, _bAmt, address(this), 0);
    }

    /**
     * @notice Withdraws collateral token from Aave to specified recipient.
     * @param _token The address of the collateral token to be withdrawn (C_TOKEN or B_TOKEN).
     * @param _amt The amount of collateral to be withdrawn (units: C_DECIMALS or B_DECIMALS).
     * @param _recipient The recipient of the funds.
     */
    function withdraw(address _token, uint256 _amt, address _recipient) public payable onlyOwner {
        IPool(AAVE_POOL).withdraw(_token, _amt, _recipient);
    }

    /**
     * @notice Repays any outstanding debt to Aave.
     * @param _dAmt The amount of debt token to repay to Aave (units: D_DECIMALS).
     *              To pay off entire debt, _dAmt = debtOwed + smallBuffer (to account for interest).
     */
    function repay(uint256 _dAmt) public payable onlyOwner {
        SafeTransferLib.safeTransferFrom(ERC20(D_TOKEN), msg.sender, address(this), _dAmt);
        _repay(_dAmt);
    }

    /**
     * @notice Repays any outstanding debt to Aave and transfers remaining collateral from Aave to owner,
     *         with permit, obviating the need for a separate approve tx. This function can only be used for ERC-2612-compliant tokens.
     * @param _dAmt The amount of debt token to repay to Aave (units: D_DECIMALS).
     *              To pay off entire debt, _dAmt = debtOwed + smallBuffer (to account for interest).
     * @param _deadline The expiration timestamp of the permit.
     * @param _v The V parameter of ERC712 signature for the permit.
     * @param _r The R parameter of ERC712 signature for the permit.
     * @param _s The S parameter of ERC712 signature for the permit.
     */
    function repayWithPermit(uint256 _dAmt, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s)
        public
        payable
        onlyOwner
    {
        IERC20Permit(D_TOKEN).permit(msg.sender, address(this), _dAmt, _deadline, _v, _r, _s);
        repay(_dAmt);
    }
}

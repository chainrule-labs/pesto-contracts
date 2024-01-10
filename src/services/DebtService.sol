// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { IPool } from "src/interfaces/aave/IPool.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IERC20Metadata } from "src/interfaces/token/IERC20Metadata.sol";

/// @title DebtService
/// @author chainrule.eth
/// @notice Manages all debt-related interactions
contract DebtService {
    // Constants: no SLOAD to save gas
    address private constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address private constant AAVE_ORACLE = 0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7;

    // Immutables: no SLOAD to save gas
    uint8 public immutable C_DECIMALS;
    uint8 public immutable D_DECIMALS;
    uint64 internal immutable _C_DEC_CONVERSION;
    uint64 internal immutable _D_DEC_CONVERSION;
    address public immutable C_TOKEN;
    address public immutable D_TOKEN;

    constructor(address _cToken, address _dToken) {
        C_TOKEN = _cToken;
        D_TOKEN = _dToken;
        C_DECIMALS = IERC20Metadata(_cToken).decimals();
        D_DECIMALS = IERC20Metadata(_dToken).decimals();
        _C_DEC_CONVERSION = uint64(10 ** (18 - C_DECIMALS));
        _D_DEC_CONVERSION = uint64(10 ** (18 - D_DECIMALS));
    }

    /**
     * @notice Borrows debt token from Aave.
     * @param _cAmt The dAmt of collateral to be supplied (units: collateral token decimals).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @return dAmt The dAmt of the debt token borrowed (units: debt token decimals).
     * @dev Debt dAmt is calculated as follows:
     * c_amt_wei = _cAmt * _C_DEC_CONVERSION (decimals: 18)
     * c_amt_usd = c_amt_wei * cPrice (decimals: 18 + 8 => 26)
     * debt_amt_usd = c_amt_usd * _ltv / 100 (decimals: 26)
     * debt_amt_usd_d_decimals = debt_amt_usd / _D_DEC_CONVERSION (decimals: 26 - (18 - D_DECIMALS))
     * dAmt = debt_amt_d_decimals = debt_amt_usd_d_decimals / dPrice (decimals: D_DECIMALS)
     */
    function _borrow(uint256 _cAmt, uint256 _ltv) internal returns (uint256 dAmt) {
        // 1. Supply collateral to Aave
        IERC20(C_TOKEN).approve(AAVE_POOL, _cAmt);
        IPool(AAVE_POOL).supply(C_TOKEN, _cAmt, address(this), 0);

        // 2. Get asset prices USD
        uint256 cPrice = IAaveOracle(AAVE_ORACLE).getAssetPrice(C_TOKEN);
        uint256 dPrice = IAaveOracle(AAVE_ORACLE).getAssetPrice(D_TOKEN);

        // 3. Calculate debt dAmt
        dAmt = (_cAmt * cPrice * uint256(_C_DEC_CONVERSION) * _ltv) / (100 * dPrice * uint256(_D_DEC_CONVERSION));

        // 4. Borrow
        IPool(AAVE_POOL).borrow(D_TOKEN, dAmt, 2, 0, address(this));
    }

    /**
     * @notice Repays debt token to Aave.
     * @param _dAmt The amount of debt token to repay to Aave.
     */
    function _repay(uint256 _dAmt) internal {
        IERC20(D_TOKEN).approve(AAVE_POOL, _dAmt);
        IPool(AAVE_POOL).repay(D_TOKEN, _dAmt, 2, address(this));
    }

    /**
     * @notice Withdraws collateral token from Aave to specified recipient.
     * @param _recipient The recipient of the funds.
     * @param _buffer The amount of collateral left as safety buffer for tx to go through (default = 10, units: 8 decimals).
     */
    function _withdraw(address _recipient, uint256 _buffer) internal {
        IPool(AAVE_POOL).withdraw(C_TOKEN, _getMaxWithdrawAmt(_buffer), _recipient);
    }

    /**
     * @notice Calculates maximum withdraw amount.
     * uint256 cNeededUSD = (dTotalUSD * 1e4) / liqThreshold;
     * uint256 maxWithdrawUSD = cTotalUSD - cNeededUSD - _buffer; (units: 8 decimals)
     * maxWithdrawAmt = (maxWithdrawUSD * 10 ** (C_DECIMALS)) / cPriceUSD; (units: C_DECIMALS decimals)
     * Docs: https://docs.aave.com/developers/guides/liquidations#how-is-health-factor-calculated
     */
    function _getMaxWithdrawAmt(uint256 _buffer) internal view returns (uint256 maxWithdrawAmt) {
        (uint256 cTotalUSD, uint256 dTotalUSD,, uint256 liqThreshold,,) =
            IPool(AAVE_POOL).getUserAccountData(address(this));
        uint256 cPriceUSD = IAaveOracle(AAVE_ORACLE).getAssetPrice(C_TOKEN);

        if (dTotalUSD == 0) {
            maxWithdrawAmt = type(uint256).max;
        } else {
            maxWithdrawAmt =
                ((cTotalUSD - ((dTotalUSD * 1e4) / liqThreshold) - _buffer) * 10 ** (C_DECIMALS)) / cPriceUSD;
        }
    }

    /**
     * @notice Returns this contract's total debt (principle + interest).
     * @return outstandingDebt This contract's total debt (units: D_DECIMALS).
     */
    function _getDebtAmt() internal view returns (uint256) {
        address variableDebtTokenAddress = IPool(AAVE_POOL).getReserveData(D_TOKEN).variableDebtTokenAddress;
        return IERC20(variableDebtTokenAddress).balanceOf(address(this));
    }
}

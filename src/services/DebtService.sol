// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { IPool } from "src/interfaces/aave/IPool.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IERC20Metadata } from "src/interfaces/token/IERC20Metadata.sol";

contract DebtService {
    // Constants: no SLOAD to save gas
    address private constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address private constant AAVE_ORACLE = 0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7;

    // Immutables: no SLOAD to save gas
    uint8 public immutable cDecimals;
    uint8 public immutable dDecimals;
    uint64 internal immutable _cDecimalConversion;
    uint64 internal immutable _dDecimalConversion;
    address public immutable cToken;
    address public immutable dToken;

    constructor(address _cToken, address _dToken) {
        cToken = _cToken;
        dToken = _dToken;
        cDecimals = IERC20Metadata(_cToken).decimals();
        dDecimals = IERC20Metadata(_dToken).decimals();
        _cDecimalConversion = uint64(10 ** (18 - cDecimals));
        _dDecimalConversion = uint64(10 ** (18 - dDecimals));
    }

    /**
     * @notice Borrows debt token from Aave.
     * @param _cAmt The dAmt of collateral to be supplied (units: collateral token decimals).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @return dAmt The dAmt of the debt token borrowed (units: debt token decimals).
     * @dev Debt dAmt is calculated as follows:
     * col_amt_wei = _cAmt * _cDecimalConversion (decimals: 18)
     * col_amt_usd = col_amt_wei * cPrice (decimals: 18 + 8 => 26)
     * debt_amt_usd = col_amt_usd * _ltv / 100 (decimals: 26)
     * debt_amt_usd_d_decimals = debt_amt_usd / _dDecimalConversion (decimals: 26 - (18 - dDecimals))
     * dAmt = debt_amt_d_decimals = debt_amt_usd_d_decimals / dPrice (decimals: dDecimals)
     */
    function _borrow(uint256 _cAmt, uint256 _ltv) internal returns (uint256 dAmt) {
        // 1. Supply collateral to Aave
        IERC20(cToken).approve(AAVE_POOL, _cAmt);
        IPool(AAVE_POOL).supply(cToken, _cAmt, address(this), 0);

        // 2. Get asset prices USD
        uint256 cPrice = IAaveOracle(AAVE_ORACLE).getAssetPrice(cToken);
        uint256 dPrice = IAaveOracle(AAVE_ORACLE).getAssetPrice(dToken);

        // 3. Calculate debt dAmt
        dAmt = (_cAmt * cPrice * uint256(_cDecimalConversion) * _ltv) / (100 * dPrice * uint256(_dDecimalConversion));

        // 4. Borrow
        IPool(AAVE_POOL).borrow(dToken, dAmt, 2, 0, address(this));
    }
}

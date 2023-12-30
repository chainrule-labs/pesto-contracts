// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

contract DebtUtils {
    function _getDAmt(
        uint256 _cPrice,
        uint256 _dPrice,
        uint256 _cDecimalConversion,
        uint256 _dDecimalConversion,
        uint256 _cAmt,
        uint256 _ltv
    ) internal pure returns (uint256) {
        return (_cAmt * _cPrice * uint256(_cDecimalConversion) * _ltv) / (100 * _dPrice * uint256(_dDecimalConversion));
    }
}

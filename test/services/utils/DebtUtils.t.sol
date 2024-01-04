// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

contract DebtUtils {
    function _getDAmt(
        uint256 _cPrice,
        uint256 _dPrice,
        uint256 _C_DEC_CONVERSION,
        uint256 _D_DEC_CONVERSION,
        uint256 _cAmt,
        uint256 _ltv
    ) internal pure returns (uint256) {
        return (_cAmt * _cPrice * uint256(_C_DEC_CONVERSION) * _ltv) / (100 * _dPrice * uint256(_D_DEC_CONVERSION));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local file imports
import { DebtService } from "src/services/DebtService.sol";

contract DebtServiceHarness is DebtService {
    /* solhint-disable func-name-mixedcase */

    constructor(address _cToken, address _dToken) DebtService(address(this), _cToken, _dToken) { }

    function exposed_cDecimalConversion() external view returns (uint64) {
        return _C_DEC_CONVERSION;
    }

    function exposed_dDecimalConversion() external view returns (uint64) {
        return _D_DEC_CONVERSION;
    }

    function exposed_borrow(uint256 _cAmt, uint256 _ltv) external returns (uint256 amount) {
        return _borrow(_cAmt, _ltv);
    }

    function exposed_repay(uint256 _dAmt) external {
        _repay(_dAmt);
    }

    function exposed_withdraw(address _recipient, uint256 _buffer) external {
        _withdraw(_recipient, _buffer);
    }

    function exposed_getMaxWithdrawAmt(uint256 _buffer) external view returns (uint256) {
        return _getMaxWithdrawAmt(_buffer);
    }

    function exposed_getDebtAmt() external view returns (uint256) {
        return _getDebtAmt();
    }
}

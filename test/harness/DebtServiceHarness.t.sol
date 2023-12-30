// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local file imports
import { DebtService } from "src/services/DebtService.sol";

contract DebtServiceHarness is DebtService {
    /* solhint-disable func-name-mixedcase */

    constructor(address _cToken, address _dToken) DebtService(_cToken, _dToken) { }

    function exposed_cDecimalConversion() external view returns (uint64) {
        return _cDecimalConversion;
    }

    function exposed_dDecimalConversion() external view returns (uint64) {
        return _dDecimalConversion;
    }

    function exposed_borrow(uint256 _cAmt, uint256 _ltv) external returns (uint256 amount) {
        return _borrow(_cAmt, _ltv);
    }
}

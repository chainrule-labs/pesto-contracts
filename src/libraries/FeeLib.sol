// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";

/// @title FeeLib
/// @author Chain Rule, LLC
/// @notice Manages all protocol-fee-related interactions
library FeeLib {
    // Constants: no SLOAD to save gas
    uint256 public constant PROTOCOL_FEE_RATE = 3;
    address public constant FEE_COLLECTOR = 0x7A7AbDb9E12F3a9845E2433958Eef8FB9C8489Ee;

    /**
     * @notice Takes protocol fee from the amount of collateral supplied.
     * @param _cAmt The amount of collateral to be supplied (units: C_DECIMALS).
     * @param _client The address where a client operator will receive protocols fees.
     * @return cAmtNet The resulting amount of collateral to be supplied after fees are taken.
     */
    function takeProtocolFee(address _token, uint256 _cAmt, address _client) internal returns (uint256 cAmtNet) {
        uint256 maxFee = (_cAmt * PROTOCOL_FEE_RATE) / 1000;
        uint256 userSavings = IFeeCollector(FEE_COLLECTOR).getUserSavings(_client, maxFee);
        uint256 fee = maxFee - userSavings;
        cAmtNet = _cAmt - fee;
        SafeTransferLib.safeApprove(ERC20(_token), FEE_COLLECTOR, fee);
        IFeeCollector(FEE_COLLECTOR).collectFees(_client, _token, fee);
    }
}

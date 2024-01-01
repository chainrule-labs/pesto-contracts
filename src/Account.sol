// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { DebtService } from "src/services/DebtService.sol";
import { SwapService } from "src/services/SwapService.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract Account is DebtService, SwapService {
    // Immutable: no SLOAD to save gas
    address public immutable owner;
    address public immutable bToken;

    // Events
    event Short(uint256 cAmt, uint256 dAmt, uint256 bAmt);

    constructor(address _owner, address _cToken, address _dToken, address _bToken) DebtService(_cToken, _dToken) {
        owner = _owner;
        bToken = _bToken;
    }

    /**
     * @notice Adds to this contract's short position.
     * @param _cAmt The amount of collateral to be supplied for this transaction-specific loan (units: collateral token decimals).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     */
    function short(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee) public payable {
        // 1. Transfer col to this contact
        IERC20(cToken).transferFrom(msg.sender, address(this), _cAmt);

        // 2. Borrow asset
        uint256 dAmt = _borrow(_cAmt, _ltv);

        // 3. Swap debt token for base token
        (, uint256 bAmt) = _swapExactInput(dToken, bToken, dAmt, _swapAmtOutMin, _poolFee);

        // 4. Emit event
        emit Short(_cAmt, dAmt, bAmt);
    }
}

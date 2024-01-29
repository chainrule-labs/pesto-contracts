// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { DebtService } from "src/services/DebtService.sol";
import { SwapService } from "src/services/SwapService.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { FeeLib } from "src/libraries/FeeLib.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IERC20Permit } from "src/interfaces/token/IERC20Permit.sol";

/// @title Position
/// @author Chain Rule, LLC
/// @notice Manages the owner's individual position
contract Position is DebtService, SwapService {
    // Immutables: no SLOAD to save gas
    address public immutable B_TOKEN;

    // Events
    event Short(uint256 cAmt, uint256 dAmt, uint256 bAmt);
    event Close(uint256 gains);

    constructor(address _owner, address _cToken, address _dToken, address _bToken)
        DebtService(_owner, _cToken, _dToken)
    {
        B_TOKEN = _bToken;
    }

    /**
     * @notice Adds to this contract's short position.
     * @param _cAmt The amount of collateral to be supplied for this transaction-specific loan (units: C_DECIMALS).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _client The address where a client operator will receive protocols fees. (use address(0) if no client).
     */
    function short(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee, address _client)
        public
        payable
        onlyOwner
    {
        // 1. Transfer collateral to this contract
        SafeTransferLib.safeTransferFrom(ERC20(C_TOKEN), msg.sender, address(this), _cAmt);

        // 2. Take protocol fee
        uint256 cAmtNet = FeeLib.takeProtocolFee(C_TOKEN, _cAmt, _client);

        // 3. Borrow debt token
        uint256 dAmt = _borrow(cAmtNet, _ltv);

        // 4. Swap debt token for base token
        (, uint256 bAmt) = _swapExactInput(D_TOKEN, B_TOKEN, dAmt, _swapAmtOutMin, _poolFee);

        // 5. Emit event
        emit Short(cAmtNet, dAmt, bAmt);
    }

    /**
     * @notice Adds to this contract's short position with permit, obviating the need for a separate approve tx.
     * @param _cAmt The amount of collateral to be supplied for this transaction-specific loan (units: C_DECIMALS).
     * @param _ltv The desired loan-to-value ratio for this transaction-specific loan (ex: 75 is 75%).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _client The address where a client operator will receive protocols fees. (use address(0) if no client).
     * @param _deadline The deadline timestamp that the permit is valid.
     * @param _v The V parameter of ERC712 permit signature.
     * @param _r The R parameter of ERC712 permit signature.
     * @param _s The S parameter of ERC712 permit signature.
     */
    function shortWithPermit(
        uint256 _cAmt,
        uint256 _ltv,
        uint256 _swapAmtOutMin,
        uint24 _poolFee,
        address _client,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public payable onlyOwner {
        // 1. Approve with permit
        IERC20Permit(C_TOKEN).permit(msg.sender, address(this), _cAmt, _deadline, _v, _r, _s);

        // 2. Short
        short(_cAmt, _ltv, _swapAmtOutMin, _poolFee, _client);
    }

    /**
     * @notice Fully closes the short position.
     * @param _poolFee The fee of the Uniswap pool.
     * @param _exactOutput Whether to swap exact output or exact input (true for exact output, false for exact input).
     * @param _swapAmtOutMin The minimum amount of output tokens from swap for the tx to go through (only used if _exactOutput is false, supply 0 if true).
     * @param _withdrawBuffer The amount of collateral left as safety buffer for tx to go through (default = 100_000, units: 8 decimals).
     */
    function close(uint24 _poolFee, bool _exactOutput, uint256 _swapAmtOutMin, uint256 _withdrawBuffer)
        public
        payable
        onlyOwner
    {
        uint256 bTokenBalance = IERC20(B_TOKEN).balanceOf(address(this));

        // 1. Swap base token for debt token
        uint256 bAmtIn;
        uint256 dAmtOut;
        if (_exactOutput) {
            (bAmtIn, dAmtOut) = _swapExactOutput(B_TOKEN, D_TOKEN, _getDebtAmt(), bTokenBalance, _poolFee);
        } else {
            (bAmtIn, dAmtOut) = _swapExactInput(B_TOKEN, D_TOKEN, bTokenBalance, _swapAmtOutMin, _poolFee);
        }

        // 2. Repay debt token
        _repay(dAmtOut);

        // 3. Withdraw collateral to owner
        _withdraw(OWNER, _withdrawBuffer);

        // 4. Pay gains if any
        uint256 gains = bTokenBalance - bAmtIn;

        if (gains > 0) {
            SafeTransferLib.safeTransfer(ERC20(B_TOKEN), OWNER, gains);
        }

        // 5. Emit event
        emit Close(gains);
    }
}

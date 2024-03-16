// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// Local Imports
import { DebtService } from "src/services/DebtService.sol";
import { SwapService } from "src/services/SwapService.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { FeeLib } from "src/libraries/FeeLib.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";
import { IERC20Permit } from "src/interfaces/token/IERC20Permit.sol";
import { IERC20Metadata } from "src/interfaces/token/IERC20Metadata.sol";

/// @title The position contract
/// @author Chain Rule, LLC
/// @notice Allows an owner account to manage its individual position
contract Position is DebtService, SwapService, IPosition {
    // Immutables: no SLOAD to save gas

    /// @inheritdoc IPosition
    uint8 public immutable B_DECIMALS;

    /// @inheritdoc IPosition
    address public immutable B_TOKEN;

    // Events
    /// @notice An event emitted when a position is created or added to.
    /// @param cAmt The amount of collateral token supplied (units: C_DECIMALS).
    /// @param dAmt The amount of debt token borrowed (units: D_DECIMALS).
    /// @param bAmt The amount of base token received and subsequently supplied as collateral (units: B_DECIMALS).
    event Add(uint256 cAmt, uint256 dAmt, uint256 bAmt);

    /// @notice An event emitted when leverage is added to a position.
    /// @param dAmt The amount of debt token borrowed (units: D_DECIMALS).
    /// @param bAmt The amount of base token received and subsequently supplied as collateral (units: B_DECIMALS).
    event AddLeverage(uint256 dAmt, uint256 bAmt);

    /// @notice An event emitted when a position is closed.
    /// @param gains The amount of base token gained from the position (units: B_DECIMALS).
    event Close(uint256 gains);

    /// @notice This function is called when a Position contract is deployed.
    /// @param _owner The account address of the Position contract's owner.
    /// @param _cToken The address of the token to be used as collateral.
    /// @param _dToken The address of the token to be borrowed.
    /// @param _bToken The address of the token to swap _dToken for.
    constructor(address _owner, address _cToken, address _dToken, address _bToken)
        DebtService(_owner, _cToken, _dToken)
    {
        B_TOKEN = _bToken;
        B_DECIMALS = IERC20Metadata(_bToken).decimals();
    }

    /// @inheritdoc IPosition
    function add(uint256 _cAmt, uint256 _ltv, uint256 _swapAmtOutMin, uint24 _poolFee, address _client)
        public
        payable
        onlyOwner
    {
        // 1. Transfer collateral to this contract
        SafeTransferLib.safeTransferFrom(ERC20(C_TOKEN), msg.sender, address(this), _cAmt);

        // 2. Take protocol fee
        uint256 cAmtNet = FeeLib.takeProtocolFee(C_TOKEN, _cAmt, _client);

        // 3. Borrow debt token
        uint256 dAmt = _takeLoan(cAmtNet, _ltv);

        // 4. Swap debt token for base token
        (, uint256 bAmt) = _swapExactInput(D_TOKEN, B_TOKEN, dAmt, _swapAmtOutMin, _poolFee);

        // 5. Supply base token as collateral
        _supplyBase(B_TOKEN, bAmt);

        emit Add(cAmtNet, dAmt, bAmt);
    }

    /// @inheritdoc IPosition
    function addWithPermit(
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
        IERC20Permit(C_TOKEN).permit(msg.sender, address(this), _cAmt, _deadline, _v, _r, _s);
        add(_cAmt, _ltv, _swapAmtOutMin, _poolFee, _client);
    }

    /// @inheritdoc IPosition
    function addLeverage(uint256 _dAmt, uint256 _swapAmtOutMin, uint24 _poolFee, address _client)
        public
        payable
        onlyOwner
    {
        // 1. Borrow debt token
        _borrow(_dAmt);

        // 2. Take protocol fee
        uint256 dAmtNet = FeeLib.takeProtocolFee(D_TOKEN, IERC20(D_TOKEN).balanceOf(address(this)), _client);

        // 3. Swap debt token for base token
        (, uint256 bAmt) = _swapExactInput(D_TOKEN, B_TOKEN, dAmtNet, _swapAmtOutMin, _poolFee);

        // 4. Supply base token as collateral
        _supplyBase(B_TOKEN, bAmt);

        emit AddLeverage(dAmtNet, bAmt);
    }

    /// @inheritdoc IPosition
    function close(
        uint24 _poolFee,
        bool _exactOutput,
        uint256 _swapAmtOutMin,
        uint256 _withdrawCAmt,
        uint256 _withdrawBAmt
    ) public payable onlyOwner {
        // 1. Withdraw base token
        withdraw(B_TOKEN, _withdrawBAmt, address(this));

        // 2. Swap base token for debt token
        uint256 bAmtIn;
        uint256 dAmtOut;
        if (_exactOutput) {
            (bAmtIn, dAmtOut) = _swapExactOutput(B_TOKEN, D_TOKEN, _getDebtAmt(), _withdrawBAmt, _poolFee);
        } else {
            (bAmtIn, dAmtOut) = _swapExactInput(B_TOKEN, D_TOKEN, _withdrawBAmt, _swapAmtOutMin, _poolFee);
        }

        // 3. Repay debt token
        _repay(dAmtOut);

        // 4. Withdraw collateral to owner
        if (_withdrawCAmt != 0) {
            withdraw(C_TOKEN, _withdrawCAmt, OWNER);
        }

        // 5. pay gains if any
        uint256 gains;
        unchecked {
            gains = _withdrawBAmt - bAmtIn; // unchecked because bAmtIn will never be greater than _withdrawBAmt
        }

        if (gains != 0) {
            SafeTransferLib.safeTransfer(ERC20(B_TOKEN), OWNER, gains);
        }

        emit Close(gains);
    }
}

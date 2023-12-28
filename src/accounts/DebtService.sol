// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Package Imports
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Local Imports
import { IPool } from "src/interfaces/aave/IPool.sol";

contract DebtService {
    // Constant: no SLOAD to save gas
    address private constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address private constant AAVE_ORACLE = 0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7;

    // Immutable: no SLOAD to save gas
    address public immutable col;
    address public immutable debt;

    // Events
    event Borrow(uint256 amount);

    constructor(address _col, address _debt) {
        col = _col;
        debt = _debt;
    }
}

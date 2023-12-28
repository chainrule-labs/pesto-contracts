// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Package Imports
import { ERC20, SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

// Local Imports
import { DebtService } from "src/accounts/DebtService.sol";

contract Account is DebtService {
    // Immutable: no SLOAD to save gas
    address public immutable owner;
    address public immutable col;
    address public immutable debt;
    address public immutable base;

    // Account Storage

    constructor(address _owner, address _col, address _debt, address _base) DebtService(_col, _debt) { }

    function addToPosition() public payable {
        // 1. Transfer col to this contact

        // TODO: how much col?
        SafeTransferLib.safeTransferFrom(ERC20(col), msg.sender, address(this), SOME_AMOUNT);

        // 2. Borrow
        uint256 borrowAmount = borrowAsset();
    }
}

# shAave

On-chain shorting via Aave and Uniswap.

## Principles

1. Immutable
2. No Governance
3. No Admin Keys

## To-Do

Contract Logic

-   [x] Add a onlyOwner modifier
-   [x] Add repayOutstandingDebt
-   [x] Add ability to retreive all positions by owner (getPositions)
-   [x] Add extractNative
    -   [x] PositionFactory
    -   [x] Position
-   [x] Add extractERC20
    -   [x] PositionFactory
    -   [x] Position
-   [x] Increase collateral (addCollateral)
-   [ ] Add read-only methods for Position owners to get info about their position (i.e., debt, collateral, ltv, etc.)
-   [ ] Consider removing Solmate entirely and using OpenZeppelin’s SafeERC20 lib:
-   [ ] Consider emitting events through position factory
-   [ ] Consider adding a require statement in Position constructor to make sure only the PositionFactory can deploy Position contracts
-   [ ] Consider inheriting OpenZeppelin's Ownable contract, since both PositionFactory and PositionAdmin need to be ownable

Unit Tests:

-   [ ] test_RepayOutstandingDebt
-   [ ] test_GetPositions
-   [ ] test_AddCollateral
-   [x] test_ExtractNative
-   [x] test_CannotExtractNative
-   [x] test_ExtractERC20
-   [x] test_CannotExtractERC20
-   [ ] test_receive
-   [ ] test_fallback
-   [ ] Consider moving TokenUtils from `test/services/utils` to `/common`

Security Considerations:

-   A vulnerability was recently found in Solmate's safeTransferLib
    -   Does not check for token contract's existence
-   The default ERC20 functionality has drawbacks:
    -   The transfer() & transferFrom() functions do not revert - they just return a boolean value
    -   Allowance front-running is possible (even if it's unlikely)
    -   Does not take into account tokens that deduct fees from transfer amounts, resulting in the recipient receiving less than the expected transfer amount
    -   ERC20 Resources:
        -   https://detectors.auditbase.com/solmates-safetransferlib-token-existence
        -   https://medium.com/@deliriusz/ten-issues-with-erc20s-that-can-ruin-you-smart-contract-6c06c44948e0
        -   https://forum.openzeppelin.com/t/making-sure-i-understand-how-safeerc20-works/2940
        -   https://blog.openzeppelin.com/how-to-ensure-web3-users-are-safe-from-zero-transfer-attacks

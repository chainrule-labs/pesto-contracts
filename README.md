# shAave

[![license-badge](https://img.shields.io/badge/license-MIT-yellow)](https://github.com/chainrule-labs/shaave-contracts/blob/main/LICENSE.md)
[![ci-badge](https://img.shields.io/github/actions/workflow/status/chainrule-labs/shaave-contracts/ci.yml?branch=main&logo=github&label=CI)](https://github.com/chainrule-labs/shaave-contracts/actions)
[![coverage](https://img.shields.io/codecov/c/github/chainrule-labs/shaave-contracts?token=K4Q3GAWUPJ&label=coverage&logo=codecov)](https://codecov.io/gh/chainrule-labs/shaave-contracts)

On-chain shorting via Aave and Uniswap.

## Principles

1. Immutable
2. No Governance
3. No Admin Keys

## To-Do

Contract Logic:

-   [ ] Add Ownable and inherit in PositionFactory and PositionAdmin
-   [ ] Implement safe versions of ERC20 transfers (either Solmate's safeTransferLib or OpenZeppelin's safeERC20)
-   [ ] Add a require statement in Position constructor to make sure only the PositionFactory can deploy Position contracts

Considerations:

-   [ ] Consider emitting events through position factory

Security Notes:

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

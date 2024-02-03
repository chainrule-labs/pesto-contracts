# shAave

[![license-badge](https://img.shields.io/badge/license-MIT-yellow)](https://github.com/chainrule-labs/shaave-contracts/blob/main/LICENSE.md)
[![ci-badge](https://img.shields.io/github/actions/workflow/status/chainrule-labs/shaave-contracts/ci.yml?branch=main&logo=github&label=CI)](https://github.com/chainrule-labs/shaave-contracts/actions)
[![coverage](https://img.shields.io/codecov/c/github/chainrule-labs/shaave-contracts?token=K4Q3GAWUPJ&label=coverage&logo=codecov)](https://codecov.io/gh/chainrule-labs/shaave-contracts)

On-chain shorting via Aave and Uniswap.

## Principles

The following outlines principles for core protocol funcitonality.

1. Immutable.
2. No Governance.
3. No Admin Keys.

## To-Do

Logic:

-   [x] Change name of `repayAfterClose` and `repayAfterCloseWithPermit` to `repayAndWithdraw` and `repayAndWithdrawWithPermit`, respectively.
-   [x] Add ability for Position owners to withdraw collateral.
    -   [x] Make `_getMaxWithdrawAmt` and `_withdraw` public functions.
    -   [x] Update `repayAndWithdraw` and `close`.
-   [x] Update `IPosition`

Tests:

-   [x] Fix `withdraw` test
-   [x] Remove `_getMaxWithdrawAmt` and `_withdraw` from `DebtServiceHarness`
-   [x] Update all unit tests related to `_getMaxWithdrawAmt` and `_withdraw`

Considerations:

-   Add function that lets users supply bToken to Aave to earn interest

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

-   [x] Add function that lets users supply bToken to Aave to earn interest
-   [ ] Consider changing `close()` to `reduce()`, since now users can send in the withdraw amount, which may or may not be the full amount necessary to close the position.
-   [ ] Why repay and withdraw in 2 TXs instead of 1?
    -   Maybe let the user send a boolean flag specifying whether to withdraw collateral.
    -   If withdraw = true, the user is likely repaying all debt to close out position

Tests:

-   [x] Test position close integration test with gains
-   [x] Test position close integration test with gains
-   [x] Update addLeverage integration tests
-   [x] Update add integration tests
-   [x] Update addWithPermit integration tests
-   [x] Test newly added, internal \_borrow function in debt service
-   [x] Update add leverage fee collector integration tests (fee is now taken from D_TOKEN in this function)
-   [ ] For testing `close()` in the case the position is not entirely closed

-   None at the moment🙂

Considerations:

-   None at the moment🙂

# REMOVE

NOTES:

-   Fee is taken in C_TOKEN in `add()`
-   Fee is taken in D_TOKEN in `addLeverage()`

Update docs accordingly.

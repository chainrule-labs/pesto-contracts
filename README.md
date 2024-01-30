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

-   Move PositionAdmin to services, rename
-   [ ] Consider changing short() to add()
-   [ ] Emit event when a position is created (get clear on whether or not an implicit event is emitted when creating a contract)
-   [ ] Add comment in permit functions specifying that only ERC-2612 compliant tokens can use this functionality.

Tests:

-   [ ] Invariant: the clientTakeRate + userTakeRate = clientRate
-   [ ] Invariant: TotalClientCollectedFees / TotalCollectedProtocolFees = clientRate \* clientTakeRate
-   [x] Unit test setClientTakeRate()
-   [x] Unit test getClientAllocations()
-   [x] Unit test FeeLib via Test Harness
-   [x] Account for userSavings in all affected FeeCollector unit and integration tests

Considerations:

-   None at the moment🙂

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

-   [x] Add ERC712 permits to functions that use transferFrom

Tests:

-   [ ] Unit test shortWithPermit()
-   [ ] Unit test addCollateralWithPermit()
-   [ ] Unit test repayAfterCloseWithPermit()
-   [ ] Separate integration tests from unit tests (separate PR)

Considerations:

-   [ ] Consider emitting Position events through another contract
-   [ ] Consider adding a function to short with signatures, via `ERCRecover`.

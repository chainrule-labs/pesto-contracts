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

-   [x] Impelemnt protocol fee
-   [x] Implement frontend incentive
-   [x] Account for case where there is no client (if no frontend, they would be able to pass their own address...)
-   [x] Should not repay more to Aave than what is owed when closing a position

Unit Tests:

-   [x] Mock feel collector in tests
-   [x] Should not repay more to Aave than what is owed when closing a position

Considerations:

-   [ ] Consider emitting events through position factory

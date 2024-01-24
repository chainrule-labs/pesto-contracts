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
-   [ ] Test that the client's collected fee balance increased by the correct amount
-   [ ] Test that the totalClientBalance increased by the correct amount
-   [ ] Test that an admin you can set a clientRate
-   [ ] Test that a non-admin cannot set a clientRate
-   [ ] Test that a client can withdraw their collected fees
-   [ ] Test that extractERC20 works correctly on FeeCollector (it has different logic than the other contracts)
-   [ ] Test that a non-admin cannot extractERC20
-   [ ] Test that an admin can withdraw native
-   [ ] Test that a non-admin cannot withdraw native
-   [ ] Test that FeeCollector can recieve native
-   [ ] Test Fallback on FeeCollector
-   [ ] Test that the correct protocol fee is collected during a short (proabably separate test from Position.t.sol)

Considerations:

-   [ ] Consider emitting events through position factory

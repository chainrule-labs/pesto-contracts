# Pesto

[![license-badge](https://img.shields.io/badge/license-MIT-yellow)](https://github.com/chainrule-labs/pesto-contracts/blob/main/LICENSE.md)
[![ci-badge](https://img.shields.io/github/actions/workflow/status/chainrule-labs/pesto-contracts/ci.yml?branch=main&logo=github&label=CI)](https://github.com/chainrule-labs/pesto-contracts/actions)
[![coverage](https://img.shields.io/codecov/c/github/chainrule-labs/pesto-contracts?token=K4Q3GAWUPJ&label=coverage&logo=codecov)](https://codecov.io/gh/chainrule-labs/pesto-contracts)

Pesto is a minimalist, on-chain derivatives protocol that enables users to create independent positions with varying degrees of exposure and hedging strategies.

## Principles

The following outlines principles for **core** protocol funcitonality.

1. Immutable.
2. No Governance on the core protocol.
3. No Admin Keys on the core protocol.

## To-Do

Logic:

-   None at the moment🙂

Tests:

-   None at the moment🙂

Considerations:

-   [ ] Consider moving the protocol fee rate to the fee collector contract.

Cleanup:

-   [ ] Change `close()` to `reduce()` in `Position.sol`
-   [ ] Change all relevant test names related from `close` to `reduce`
-   [ ] Ensure terminology and variable references are consistent across all comments
-   [ ] Ensure full NatSpec comliance

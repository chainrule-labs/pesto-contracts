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

Logic:

-   [x] Make `FEE_COLLECTOR` an immutable variable in Position.sol and PositionFactory.sol
-   [x] Add `owner()` and `clientRate()` to IFeeCollector

Tests:

-   [ ] Separate integration tests from unit tests (separate PR)
-   [x] testFuzz_CollectFeesWithClient
-   [x] testFuzz_CollectFeesNoClient
-   [x] testFuzz_CollectFeesWithClientIntegrated
-   [x] testFuzz_CollectFeesNoClientIntegrated
-   [x] testFuzz_ClientWithdraw
-   [x] testFuzz_SetClientRate
-   [x] testFuzz_CannotSetClientRateOutOfRange
-   [x] testFuzz_CannotSetClientRateUnauthorized
-   [x] testFuzz_ExtractNative
-   [x] testFuzz_CannotExtractNative
-   [x] testFuzz_ExtractERC20
-   [x] testFuzz_CannotExtractERC20
-   [x] testFuzz_Receive
-   [x] testFuzz_Fallback

Considerations:

-   [ ] Consider emitting Position events through another contract
-   [ ] Consider adding a function to short with signatures, via `ERCRecover`.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { DebtServiceHarness } from "test/harness/DebtServiceHarness.t.sol";
import { DebtUtils } from "test/services/utils/DebtUtils.t.sol";
import { Assets, AAVE_ORACLE, USDC, USDC_HOLDER } from "test/common/Constants.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract DebtServiceTest is Test, DebtUtils {
    /* solhint-disable func-name-mixedcase */

    // Test Contracts
    Assets public assets;

    // Test Storage
    DebtServiceHarness[] public debtServices;
    address[4] public supportedAssets;
    uint256 public mainnetFork;

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        assets = new Assets();
        supportedAssets = assets.getSupported();

        // Construct list of all possible debt services
        for (uint256 i; i < supportedAssets.length; i++) {
            for (uint256 j; j < supportedAssets.length; j++) {
                if (i != j) {
                    // Create DebtService
                    address cToken = supportedAssets[i];
                    address dToken = supportedAssets[j];
                    DebtServiceHarness debtService = new DebtServiceHarness(cToken, dToken);
                    debtServices.push(debtService);

                    // Fund DebtService with collateral
                    if (cToken != USDC) {
                        deal(cToken, address(debtService), assets.maxCAmts(cToken));
                    } else {
                        // Work around deal not working for USDC
                        vm.startPrank(USDC_HOLDER);
                        IERC20(USDC).transfer(address(debtService), assets.maxCAmts(cToken));
                        vm.stopPrank();
                    }
                }
            }
        }

        // Mock AaveOracle
        for (uint256 i; i < supportedAssets.length; i++) {
            vm.mockCall(
                AAVE_ORACLE,
                abi.encodeWithSelector(IAaveOracle(AAVE_ORACLE).getAssetPrice.selector, supportedAssets[i]),
                abi.encode(assets.prices(supportedAssets[i]))
            );
        }
    }

    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - cToken should have correct decimals.
    // - dToken should have correct decimals.
    // - cDecimalConversion should be correct.
    // - dDecimalConversion should be correct.
    // - cToken decimals multiplied by cDecimalConversion should equal 10^18 for all cases.
    // - dToken decimals multiplied by dDecimalConversion should equal 10^18 for all cases.

    function test_SetUpState() public {
        assertEq(debtServices.length, 12);

        // Assert correct decimals and conversions
        for (uint256 i; i < debtServices.length; i++) {
            uint8 cDecimals = assets.decimals(debtServices[i].cToken());
            uint8 dDecimals = assets.decimals(debtServices[i].dToken());
            uint64 cDecimalConversion = uint64(10 ** (18 - cDecimals));
            uint64 dDecimalConversion = uint64(10 ** (18 - dDecimals));
            uint256 cresult = 10 ** uint256(cDecimals) * uint256(cDecimalConversion);
            uint256 dresult = 10 ** uint256(dDecimals) * uint256(dDecimalConversion);

            assertEq(debtServices[i].cDecimals(), cDecimals);
            assertEq(debtServices[i].dDecimals(), dDecimals);
            assertEq(debtServices[i].exposed_cDecimalConversion(), cDecimalConversion);
            assertEq(debtServices[i].exposed_dDecimalConversion(), dDecimalConversion);
            assertEq(cresult, 10 ** 18);
            assertEq(dresult, 10 ** 18);
        }
    }

    /// @dev
    // - It's cToken balance should decrease by the amount of collateral supplied.
    // - It's dToken balance should increase by the amount of debt borrowed.
    // - It should borrow the correct amount, given mocked token prices.

    function test_Borrow(uint256 ltv) public {
        for (uint256 i; i < debtServices.length; i++) {
            // Setup
            address debtService = address(debtServices[i]);
            address cToken = debtServices[i].cToken();
            address dToken = debtServices[i].dToken();
            uint256 cDecimalConversion = debtServices[i].exposed_cDecimalConversion();
            uint256 dDecimalConversion = debtServices[i].exposed_dDecimalConversion();
            uint256 cAmt = assets.maxCAmts(cToken);

            // Assumptions
            vm.assume(ltv > 0 && ltv <= 60);

            // Expectations
            uint256 dAmtExpected = _getDAmt(
                assets.prices(cToken), assets.prices(dToken), cDecimalConversion, dDecimalConversion, cAmt, ltv
            );

            // Pre-Act Assertions
            assertEq(IERC20(cToken).balanceOf(debtService), cAmt);
            assertEq(IERC20(dToken).balanceOf(debtService), 0);

            // Act
            uint256 dAmt = debtServices[i].exposed_borrow(cAmt, ltv);

            // Assertions
            assertEq(IERC20(cToken).balanceOf(debtService), 0);
            assertEq(IERC20(dToken).balanceOf(debtService), dAmt);
            assertEq(dAmt, dAmtExpected);
        }
    }
}

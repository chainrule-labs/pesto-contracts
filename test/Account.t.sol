// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { AccountFactory } from "src/AccountFactory.sol";
import { Assets, AAVE_ORACLE, CONTRACT_DEPLOYER, DAI, USDC, WBTC, WETH } from "test/common/Constants.t.sol";
import { TokenUtils } from "test/services/utils/TokenUtils.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IAccount } from "src/interfaces/IAccount.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract AccountTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    struct TestAccount {
        address addr;
        address cToken;
        address bToken;
    }

    // Test contracts
    AccountFactory public accountFactory;
    Assets public assets;
    TestAccount[] public accounts;

    // Test Storage
    address public accountAddr;
    uint256 public mainnetFork;

    // Events
    event Short(uint256 cAmt, uint256 dAmt, uint256 bAmt);

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy AccountFactory
        vm.prank(CONTRACT_DEPLOYER);
        accountFactory = new AccountFactory();

        // Deploy and store all possible accounts
        for (uint256 i; i < supportedAssets.length; i++) {
            address cToken = supportedAssets[i];
            for (uint256 j; j < supportedAssets.length; j++) {
                if (j != i) {
                    address dToken = supportedAssets[j];
                    for (uint256 k; k < supportedAssets.length; k++) {
                        address bToken = supportedAssets[k];
                        // Exclude accounts with no pool
                        bool noPool = (dToken == USDC && bToken == DAI) || (dToken == DAI && bToken == USDC);
                        bool poolExists = !noPool;
                        if (k != j && poolExists) {
                            accountAddr = accountFactory.createAccount(cToken, dToken, bToken);
                            TestAccount memory newAccount =
                                TestAccount({ addr: accountAddr, cToken: cToken, bToken: bToken });
                            accounts.push(newAccount);
                        }
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
    // - User's cToken balance should decrease by collateral amount supplied.
    // - Account's bToken balance should increase by amount receieved from swap.
    // - The above should be true for a wide range of LTVs.
    // - The above should be true for a wide range of collateral amounts.
    // - The above should be true for all supported tokens.

    function testFuzz_Short(uint256 _ltv, uint256 _cAmt) public {
        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < accounts.length; i++) {
            // Test variables
            address addr = accounts[i].addr;
            address cToken = accounts[i].cToken;
            address bToken = accounts[i].bToken;

            // Bound fuzzed variables
            _ltv = bound(_ltv, 1, 60);
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Fund user with collateral
            _fund(address(this), cToken, _cAmt);

            // Approve account to spend collateral
            IERC20(cToken).approve(addr, _cAmt);

            // Pre-act balances
            uint256 colPreBal = IERC20(cToken).balanceOf(address(this));
            uint256 basePreBal = IERC20(cToken).balanceOf(addr);

            // Act
            vm.recordLogs();
            IAccount(addr).short(_cAmt, _ltv, 0, 3000);
            VmSafe.Log[] memory entries = vm.getRecordedLogs();

            // Post-act balances
            uint256 colPostBal = IERC20(cToken).balanceOf(address(this));
            uint256 basePostBal = IERC20(bToken).balanceOf(addr);
            bytes memory shortEvent = entries[entries.length - 1].data;
            uint256 bAmt;

            assembly {
                let startPos := sub(mload(shortEvent), 32)
                bAmt := mload(add(shortEvent, add(0x20, startPos)))
            }

            // Assertions
            assertEq(colPostBal, colPreBal - _cAmt);
            assertEq(basePostBal, basePreBal + bAmt);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }
}

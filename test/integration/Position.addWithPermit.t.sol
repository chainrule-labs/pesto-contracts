// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import {
    Assets,
    AAVE_ORACLE,
    CLIENT_RATE,
    CLIENT_TAKE_RATE,
    CONTRACT_DEPLOYER,
    DAI,
    FEE_COLLECTOR,
    TEST_CLIENT,
    TEST_POOL_FEE,
    PROTOCOL_FEE_RATE,
    USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { FeeUtils } from "test/common/utils/FeeUtils.t.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract PositionAddPermitTest is Test, TokenUtils, DebtUtils, FeeUtils {
    /* solhint-disable func-name-mixedcase */

    struct TestPosition {
        address addr;
        address cToken;
        address dToken;
        address bToken;
    }

    struct PositionBalances {
        uint256 preBToken;
        uint256 postBToken;
        uint256 preVDToken;
        uint256 postVDToken;
        uint256 preCAToken;
        uint256 preBAToken;
        uint256 postCAToken;
        uint256 postBAToken;
    }

    struct OwnerBalances {
        uint256 preCToken;
        uint256 postCToken;
    }

    struct FeeData {
        uint256 maxFee;
        uint256 userSavings;
        uint256 protocolFee;
    }

    struct Permit {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    VmSafe.Wallet public wallet;
    address public positionAddr;
    address public owner;

    // Events
    event Add(uint256 cAmt, uint256 dAmt, uint256 bAmt);

    function setUp() public {
        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        deployCodeTo("FeeCollector.sol", abi.encode(CONTRACT_DEPLOYER), FEE_COLLECTOR);

        // Set client rate
        vm.prank(CONTRACT_DEPLOYER);
        IFeeCollector(FEE_COLLECTOR).setClientRate(CLIENT_RATE);

        // Set client take rate
        vm.prank(TEST_CLIENT);
        IFeeCollector(FEE_COLLECTOR).setClientTakeRate(CLIENT_TAKE_RATE);

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER);

        // Set contract owner
        wallet = vm.createWallet(uint256(keccak256(abi.encodePacked(uint256(1)))));
        owner = wallet.addr;

        // Deploy and store all possible positions
        for (uint256 i; i < supportedAssets.length; i++) {
            address cToken = supportedAssets[i];
            for (uint256 j; j < supportedAssets.length; j++) {
                if (j != i) {
                    address dToken = supportedAssets[j];
                    for (uint256 k; k < supportedAssets.length; k++) {
                        address bToken = supportedAssets[k];
                        // Exclude positions with no pool
                        bool poolExists = !((dToken == USDC && bToken == DAI) || (dToken == DAI && bToken == USDC));
                        if (k != j && poolExists) {
                            vm.prank(owner);
                            positionAddr = positionFactory.createPosition(cToken, dToken, bToken);
                            TestPosition memory newPosition =
                                TestPosition({ addr: positionAddr, cToken: cToken, dToken: dToken, bToken: bToken });
                            positions.push(newPosition);
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

    /// @dev Tests that addWithPermit function works when the collateral token and base token are different.
    /// @notice Assertions:
    // - The Position contract's (B_TOKEN) aToken balance on Aave should increase by bAmt receieved from swap.
    // - The Position contract's (C_TOKEN) aToken balance should increase by (collateral - protocolFee).
    // - The Position contract's B_TOKEN balance should remain 0.
    // - The Position contract's variableDebtToken balance should increase by dAmt received from swap.
    // - The Owner's C_TOKEN balance should decrease by collateral amount supplied.
    // - The above should be true for a wide range of LTVs.
    // - The above should be true for a wide range of collateral amounts.
    // - The above should be true for all supported tokens.
    // - The act should be accomplished without a separate approve tx.
    function testFuzz_AddWithPermitDiffCAndB(uint256 _ltv, uint256 _cAmt) public {
        PositionBalances memory positionBalances;
        OwnerBalances memory ownerBalances;
        FeeData memory feeData;
        TestPosition memory p;
        Permit memory permit;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken != p.bToken) {
                // Bound fuzzed variables
                _ltv = bound(_ltv, 1, 60);
                _cAmt = bound(_cAmt, assets.minCAmts(p.cToken), assets.maxCAmts(p.cToken));

                // Fund owner with collateral
                _fund(owner, p.cToken, _cAmt);

                // Expectations
                feeData.maxFee = (_cAmt * PROTOCOL_FEE_RATE) / 1000;
                (feeData.userSavings,) = _getExpectedClientAllocations(feeData.maxFee, CLIENT_TAKE_RATE);
                feeData.protocolFee = feeData.maxFee - feeData.userSavings;

                // Pre-act balances
                ownerBalances.preCToken = IERC20(p.cToken).balanceOf(owner);
                positionBalances.preBToken = IERC20(p.bToken).balanceOf(p.addr);
                positionBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.preBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);

                // Setup Assertions:
                assertEq(positionBalances.preCAToken, 0);
                assertEq(positionBalances.preBAToken, 0);
                assertEq(positionBalances.preVDToken, 0);
                assertEq(positionBalances.preBToken, 0);

                // Get permit
                uint256 permitTimestamp = block.timestamp + 1000;
                (permit.v, permit.r, permit.s) = _getPermit(p.cToken, wallet, positions[i].addr, _cAmt, permitTimestamp);

                // Act
                vm.recordLogs();
                vm.prank(owner);
                IPosition(positions[i].addr).addWithPermit(
                    _cAmt, _ltv, 0, TEST_POOL_FEE, TEST_CLIENT, permitTimestamp, permit.v, permit.r, permit.s
                );

                // Post-act balances
                VmSafe.Log[] memory entries = vm.getRecordedLogs();
                ownerBalances.postCToken = IERC20(p.cToken).balanceOf(owner);
                positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                positionBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);

                // Retrieve bAmt and dAmt from Add event
                bytes memory addEvent = entries[entries.length - 1].data;
                uint256 dAmt;
                uint256 bAmt;
                assembly {
                    dAmt := mload(add(addEvent, 0x40))
                    bAmt := mload(add(addEvent, 0x60))
                }

                // Assertions
                assertApproxEqAbs(positionBalances.postBAToken, positionBalances.preBAToken + bAmt, 1);
                assertApproxEqAbs(positionBalances.postCAToken, _cAmt - feeData.protocolFee, 1);
                assertEq(positionBalances.postBToken, 0);
                assertApproxEqAbs(positionBalances.postVDToken, positionBalances.preVDToken + dAmt, 1);
                assertEq(ownerBalances.postCToken, ownerBalances.preCToken - _cAmt);

                // Revert to snapshot to standardize chain state for each position
                vm.revertTo(id);
            }
        }
    }

    /// @dev Tests that addWithPermit function works when the collateral token and base token are same.
    /// @notice Assertions:
    // - The Position contract's (C_TOKEN) aToken balance should increase by
    //   bAmt + (collateral - protocolFee), where bAmt is the amount received from swap.
    // - The Position contract's (B_TOKEN) aToken balance should equal its (C_TOKEN) aToken balance.
    // - The Position contract's B_TOKEN balance should remain 0.
    // - The Position contract's variableDebtToken balance should increase by dAmt received from swap.
    // - The Owner's C_TOKEN balance should decrease by collateral amount supplied.
    // - The above should be true for a wide range of LTVs.
    // - The above should be true for a wide range of collateral amounts.
    // - The above should be true for all supported tokens.
    // - The act should be accomplished without a separate approve tx.
    function testFuzz_AddWithPermitSameCAndB(uint256 _ltv, uint256 _cAmt) public {
        PositionBalances memory positionBalances;
        OwnerBalances memory ownerBalances;
        FeeData memory feeData;
        TestPosition memory p;
        Permit memory permit;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            p.addr = positions[i].addr;
            p.cToken = positions[i].cToken;
            p.dToken = positions[i].dToken;
            p.bToken = positions[i].bToken;

            if (p.cToken == p.bToken) {
                // Bound fuzzed variables
                _ltv = bound(_ltv, 1, 60);
                _cAmt = bound(_cAmt, assets.minCAmts(p.cToken), assets.maxCAmts(p.cToken));

                // Fund owner with collateral
                _fund(owner, p.cToken, _cAmt);

                // Expectations
                feeData.maxFee = (_cAmt * PROTOCOL_FEE_RATE) / 1000;
                (feeData.userSavings,) = _getExpectedClientAllocations(feeData.maxFee, CLIENT_TAKE_RATE);
                feeData.protocolFee = feeData.maxFee - feeData.userSavings;

                // Pre-act balances
                ownerBalances.preCToken = IERC20(p.cToken).balanceOf(owner);
                positionBalances.preBToken = IERC20(p.bToken).balanceOf(p.addr);
                positionBalances.preCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.preBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.preVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);

                // Setup Assertions:
                assertEq(positionBalances.preCAToken, 0);
                assertEq(positionBalances.preBAToken, 0);
                assertEq(positionBalances.preVDToken, 0);
                assertEq(positionBalances.preBToken, 0);

                // Get permit
                uint256 permitTimestamp = block.timestamp + 1000;
                (permit.v, permit.r, permit.s) = _getPermit(p.cToken, wallet, positions[i].addr, _cAmt, permitTimestamp);

                // Act
                vm.recordLogs();
                vm.prank(owner);
                IPosition(positions[i].addr).addWithPermit(
                    _cAmt, _ltv, 0, TEST_POOL_FEE, TEST_CLIENT, permitTimestamp, permit.v, permit.r, permit.s
                );

                // Post-act balances
                VmSafe.Log[] memory entries = vm.getRecordedLogs();
                ownerBalances.postCToken = IERC20(p.cToken).balanceOf(owner);
                positionBalances.postBToken = IERC20(p.bToken).balanceOf(p.addr);
                positionBalances.postCAToken = _getATokenBalance(p.addr, p.cToken);
                positionBalances.postBAToken = _getATokenBalance(p.addr, p.bToken);
                positionBalances.postVDToken = _getVariableDebtTokenBalance(p.addr, p.dToken);

                // Retrieve bAmt and dAmt from Add event
                bytes memory addEvent = entries[entries.length - 1].data;
                uint256 dAmt;
                uint256 bAmt;
                assembly {
                    dAmt := mload(add(addEvent, 0x40))
                    bAmt := mload(add(addEvent, 0x60))
                }

                // Assertions
                assertApproxEqAbs(positionBalances.postCAToken, bAmt + _cAmt - feeData.protocolFee, 1);
                assertEq(positionBalances.postBAToken, positionBalances.postCAToken);
                assertEq(positionBalances.postBToken, 0);
                assertApproxEqAbs(positionBalances.postVDToken, positionBalances.preVDToken + dAmt, 1);
                assertEq(ownerBalances.postCToken, ownerBalances.preCToken - _cAmt);

                // Revert to snapshot to standardize chain state for each position
                vm.revertTo(id);
            }
        }
    }
}

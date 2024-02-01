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
    CONTRACT_DEPLOYER,
    DAI,
    FEE_COLLECTOR,
    PROTOCOL_FEE_RATE,
    TEST_POOL_FEE,
    CLIENT_RATE,
    USDC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { FeeUtils } from "test/common/utils/FeeUtils.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract FeeCollectorAddLeverageTest is Test, TokenUtils, DebtUtils, FeeUtils {
    /* solhint-disable func-name-mixedcase */

    struct TestPosition {
        address addr;
        address cToken;
        address dToken;
        address bToken;
    }

    struct FeeCollectorBalances {
        uint256 preFeeTokenBal;
        uint256 postFeeTokenBal;
        uint256 preClientFeeTokenBal;
        uint256 postClientFeeTokenBal;
        uint256 preTotalClientsFeeTokenBal;
        uint256 postTotalClientsFeeTokenBal;
    }

    struct PositionBalances {
        uint256 preATokenBal;
        uint256 postATokenBal;
    }

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    address public positionAddr;
    uint256 public mainnetFork;

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        deployCodeTo("FeeCollector.sol", abi.encode(CONTRACT_DEPLOYER), FEE_COLLECTOR);

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER);

        // Set client rate
        vm.prank(CONTRACT_DEPLOYER);
        IFeeCollector(FEE_COLLECTOR).setClientRate(CLIENT_RATE);

        // Deploy and store all possible positions where cToken and bToken are the same
        for (uint256 i; i < supportedAssets.length; i++) {
            address cToken = supportedAssets[i];
            for (uint256 j; j < supportedAssets.length; j++) {
                if (j != i) {
                    address dToken = supportedAssets[j];
                    address bToken = cToken;
                    // Exclude positions with no pool
                    bool poolExists = !((dToken == USDC && bToken == DAI) || (dToken == DAI && bToken == USDC));
                    if (poolExists) {
                        positionAddr = positionFactory.createPosition(cToken, dToken, bToken);
                        TestPosition memory newPosition =
                            TestPosition({ addr: positionAddr, cToken: cToken, dToken: dToken, bToken: bToken });
                        positions.push(newPosition);
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

    /// @dev
    // - The active fork should be the forked network created in the setup
    function test_ActiveFork() public {
        assertEq(vm.activeFork(), mainnetFork, "vm.activeFork() != mainnetFork");
    }

    /// @dev
    // - The FeeCollector's feeToken balance should increase by (maxFee - userSavings).
    // - The feeToken amount supplied as collateral should be _bAmt - (maxFee - userSavings).
    // - The feeToken totalClientBalances should increase by clientFee.
    // - The client's feeToken balance on the FeeCollector contract should increase by clientFee.
    function testFuzz_AddLeverageWithClient(uint256 _ltv, uint256 _bAmt, uint256 _clientTakeRate, address _client)
        public
    {
        // Assumptions
        vm.assume(_client != address(0));
        _ltv = bound(_ltv, 1, 60);
        _clientTakeRate = bound(_clientTakeRate, 0, 100);

        // Setup
        FeeCollectorBalances memory feeCollectorBalances;
        PositionBalances memory positionBalances;
        vm.prank(_client);
        IFeeCollector(FEE_COLLECTOR).setClientTakeRate(_clientTakeRate);

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;
            address feeToken = positions[i].bToken;

            // Bound fuzzed variables
            _bAmt = bound(_bAmt, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));

            // Fund contract with feeToken
            _fund(addr, feeToken, _bAmt);

            // Expectations
            uint256 maxFee = (_bAmt * PROTOCOL_FEE_RATE) / 1000;
            (uint256 userSavings, uint256 clientFee) = _getExpectedClientAllocations(maxFee, _clientTakeRate);
            uint256 protocolFee = maxFee - userSavings;

            // Pre-act balances
            feeCollectorBalances.preFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.preClientFeeTokenBal = IFeeCollector(FEE_COLLECTOR).balances(_client, feeToken);
            feeCollectorBalances.preTotalClientsFeeTokenBal = IFeeCollector(FEE_COLLECTOR).totalClientBalances(feeToken);
            positionBalances.preATokenBal = _getATokenBalance(addr, feeToken);
            assertEq(positionBalances.preATokenBal, 0);

            // Act
            IPosition(addr).addLeverage(_ltv, 0, TEST_POOL_FEE, _client);

            // Post-act balances
            feeCollectorBalances.postFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.postClientFeeTokenBal = IFeeCollector(FEE_COLLECTOR).balances(_client, feeToken);
            feeCollectorBalances.postTotalClientsFeeTokenBal =
                IFeeCollector(FEE_COLLECTOR).totalClientBalances(feeToken);
            positionBalances.postATokenBal = _getATokenBalance(addr, feeToken);

            // Assertions
            assertEq(feeCollectorBalances.postFeeTokenBal, feeCollectorBalances.preFeeTokenBal + protocolFee);
            assertEq(feeCollectorBalances.postClientFeeTokenBal, feeCollectorBalances.preClientFeeTokenBal + clientFee);
            assertEq(
                feeCollectorBalances.postTotalClientsFeeTokenBal,
                feeCollectorBalances.preTotalClientsFeeTokenBal + clientFee
            );
            assertApproxEqAbs(positionBalances.postATokenBal, _bAmt - protocolFee, 1);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - The FeeCollector's feeToken balance should increase by (maxFee - userSavings).
    // - The feeToken amount supplied as collateral should be _bAmt - (maxFee - userSavings).
    // - The feeToken totalClientBalances should not change
    // - The above should be true when _client is sent as address(0)
    function testFuzz_AddLeverageNoClient(uint256 _ltv, uint256 _bAmt) public {
        // Assumptions
        _ltv = bound(_ltv, 1, 60);

        // Setup
        FeeCollectorBalances memory feeCollectorBalances;
        PositionBalances memory positionBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address addr = positions[i].addr;
            address feeToken = positions[i].bToken;

            // Bound fuzzed variables
            _bAmt = bound(_bAmt, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));

            // Fund contract with feeToken
            _fund(addr, feeToken, _bAmt);

            // Expectations
            uint256 maxFee = (_bAmt * PROTOCOL_FEE_RATE) / 1000;
            (uint256 userSavings,) = _getExpectedClientAllocations(maxFee, 0);
            uint256 protocolFee = maxFee - userSavings;

            // Pre-act balances
            feeCollectorBalances.preFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.preTotalClientsFeeTokenBal = IFeeCollector(FEE_COLLECTOR).totalClientBalances(feeToken);
            positionBalances.preATokenBal = _getATokenBalance(addr, feeToken);
            assertEq(positionBalances.preATokenBal, 0);

            // Act
            IPosition(addr).addLeverage(_ltv, 0, TEST_POOL_FEE, address(0));

            // Post-act balances
            feeCollectorBalances.postFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.postTotalClientsFeeTokenBal =
                IFeeCollector(FEE_COLLECTOR).totalClientBalances(feeToken);
            uint256 postPositionATokenBal = _getATokenBalance(addr, feeToken);

            // Assertions
            assertEq(feeCollectorBalances.postFeeTokenBal, feeCollectorBalances.preFeeTokenBal + protocolFee);
            assertEq(feeCollectorBalances.postTotalClientsFeeTokenBal, feeCollectorBalances.preTotalClientsFeeTokenBal);
            assertApproxEqAbs(postPositionATokenBal, _bAmt - protocolFee, 1);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }
}

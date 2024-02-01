// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import {
    AAVE_ORACLE,
    Assets,
    CONTRACT_DEPLOYER,
    CLIENT_RATE,
    FEE_COLLECTOR,
    PROTOCOL_FEE_RATE,
    TEST_CLIENT,
    TEST_POOL_FEE,
    USDC,
    WBTC,
    WETH
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { FeeUtils } from "test/common/utils/FeeUtils.t.sol";
import { DebtUtils } from "test/common/utils/DebtUtils.t.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract FeeCollectorAddTest is Test, TokenUtils, FeeUtils, DebtUtils {
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

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    uint256 public mainnetFork;
    address public positionOwner = address(this);

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

        // Deploy and store four position contracts - one for each supported asset as collateral
        address positionAddr;
        TestPosition memory newPosition;
        for (uint256 i; i < supportedAssets.length; i++) {
            if (supportedAssets[i] != WETH) {
                positionAddr = positionFactory.createPosition(supportedAssets[i], WETH, WBTC);
                newPosition =
                    TestPosition({ addr: positionAddr, cToken: supportedAssets[i], dToken: WETH, bToken: WBTC });
                positions.push(newPosition);
            }
        }
        positionAddr = positionFactory.createPosition(WETH, USDC, WETH);
        newPosition = TestPosition({ addr: positionAddr, cToken: WETH, dToken: USDC, bToken: WETH });
        positions.push(newPosition);

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
    // - The FeeCollector's cToken balance should increase by (maxFee - userSavings).
    // - The cToken amount supplied as collateral should be cAmt - (maxFee - userSavings).
    // - The cToken totalClientBalances should increase by clientFee.
    // - The client's cToken balance on the FeeCollector contract should increase by clientFee.
    function testFuzz_AddCollectFeesWithClient(uint256 _cAmt, uint256 _clientTakeRate) external payable {
        // Setup
        FeeCollectorBalances memory feeCollectorBalances;

        // Bound fuzzed inputs
        _clientTakeRate = bound(_clientTakeRate, 0, 100);

        // Setup
        vm.prank(TEST_CLIENT);
        IFeeCollector(FEE_COLLECTOR).setClientTakeRate(_clientTakeRate);

        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address positionAddr = positions[i].addr;
            address cToken = positions[i].cToken;

            // Bound fuzzed variables
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Expectations
            uint256 maxFee = (_cAmt * PROTOCOL_FEE_RATE) / 1000;
            (uint256 userSavings, uint256 clientFee) = _getExpectedClientAllocations(maxFee, _clientTakeRate);
            uint256 protocolFee = maxFee - userSavings;

            // Fund positionOwner with _cAmt of cToken
            _fund(positionOwner, cToken, _cAmt);

            // Approve Position contract to spend collateral
            IERC20(cToken).approve(positionAddr, _cAmt);

            // Pre-act balances
            feeCollectorBalances.preFeeTokenBal = IERC20(cToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.preClientFeeTokenBal = IFeeCollector(FEE_COLLECTOR).balances(TEST_CLIENT, cToken);
            feeCollectorBalances.preTotalClientsFeeTokenBal = IFeeCollector(FEE_COLLECTOR).totalClientBalances(cToken);
            uint256 prePositionATokenBal = _getATokenBalance(positionAddr, cToken);
            assertEq(prePositionATokenBal, 0);

            // Act: increase short position
            IPosition(positionAddr).add(_cAmt, 50, 0, TEST_POOL_FEE, TEST_CLIENT);

            // Post-act balances
            feeCollectorBalances.postFeeTokenBal = IERC20(cToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.postClientFeeTokenBal = IFeeCollector(FEE_COLLECTOR).balances(TEST_CLIENT, cToken);
            feeCollectorBalances.postTotalClientsFeeTokenBal = IFeeCollector(FEE_COLLECTOR).totalClientBalances(cToken);
            uint256 postPositionATokenBal = _getATokenBalance(positionAddr, cToken);

            // Assertions
            assertEq(feeCollectorBalances.postFeeTokenBal, feeCollectorBalances.preFeeTokenBal + protocolFee);
            assertEq(feeCollectorBalances.postClientFeeTokenBal, feeCollectorBalances.preClientFeeTokenBal + clientFee);
            assertEq(
                feeCollectorBalances.postTotalClientsFeeTokenBal,
                feeCollectorBalances.preTotalClientsFeeTokenBal + clientFee
            );
            assertApproxEqAbs(postPositionATokenBal, _cAmt - protocolFee, 1);
        }
    }

    /// @dev
    // - The FeeCollector's cToken balance should increase by (maxFee - userSavings).
    // - The cToken amount supplied as collateral should be cAmt - (maxFee - userSavings).
    // - The cToken totalClientBalances should not change
    // - The above should be true when _client is sent as address(0)
    function testFuzz_AddCollectFeesNoClient(uint256 _cAmt) external payable {
        // Setup
        FeeCollectorBalances memory feeCollectorBalances;

        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address positionAddr = positions[i].addr;
            address cToken = positions[i].cToken;

            // Bound fuzzed variables
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Expectations
            uint256 maxFee = (_cAmt * PROTOCOL_FEE_RATE) / 1000;
            (uint256 userSavings,) = _getExpectedClientAllocations(maxFee, 0);
            uint256 protocolFee = maxFee - userSavings;

            // Fund positionOwner with _cAmt of cToken
            _fund(positionOwner, cToken, _cAmt);

            // Approve Position contract to spend collateral
            IERC20(cToken).approve(positionAddr, _cAmt);

            // Pre-act balances
            feeCollectorBalances.preFeeTokenBal = IERC20(cToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.preTotalClientsFeeTokenBal = IFeeCollector(FEE_COLLECTOR).totalClientBalances(cToken);
            uint256 prePositionATokenBal = _getATokenBalance(positionAddr, cToken);
            assertEq(prePositionATokenBal, 0);

            // Act: increase short position
            IPosition(positionAddr).add(_cAmt, 50, 0, TEST_POOL_FEE, address(0));

            // Post-act balances
            feeCollectorBalances.postFeeTokenBal = IERC20(cToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.postTotalClientsFeeTokenBal = IFeeCollector(FEE_COLLECTOR).totalClientBalances(cToken);
            uint256 postPositionATokenBal = _getATokenBalance(positionAddr, cToken);

            // Assertions
            assertEq(feeCollectorBalances.postFeeTokenBal, feeCollectorBalances.preFeeTokenBal + protocolFee);
            assertEq(feeCollectorBalances.postTotalClientsFeeTokenBal, feeCollectorBalances.preTotalClientsFeeTokenBal);
            assertApproxEqAbs(postPositionATokenBal, _cAmt - protocolFee, 1);
        }
    }
}

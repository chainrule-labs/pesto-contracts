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
    TEST_LTV,
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

    // Test contracts
    PositionFactory public positionFactory;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    address public owner = address(this);
    address public positionAddr;

    function setUp() public {
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

    /// @dev
    // - The FeeCollector's feeToken balance should increase by (maxFee - userSavings).
    // - The feeToken totalClientBalances should increase by clientFee.
    // - The client's feeToken balance on the FeeCollector contract should increase by clientFee.
    function testFuzz_AddLeverageWithClient(uint256 _dAmt, uint256 _clientTakeRate, address _client) public {
        // Assumptions
        vm.assume(_client != address(0));
        _clientTakeRate = bound(_clientTakeRate, 0, 100);

        // Setup
        FeeCollectorBalances memory feeCollectorBalances;
        vm.prank(_client);
        IFeeCollector(FEE_COLLECTOR).setClientTakeRate(_clientTakeRate);

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address posAddr = positions[i].addr;
            address feeToken = positions[i].dToken;

            // Add to position
            _fund(owner, positions[i].cToken, assets.maxCAmts(positions[i].cToken));
            IERC20(positions[i].cToken).approve(posAddr, assets.maxCAmts(positions[i].cToken));
            IPosition(posAddr).add(assets.maxCAmts(positions[i].cToken), TEST_LTV, 0, TEST_POOL_FEE, _client);

            // Bound fuzzed variables
            _dAmt = bound(_dAmt, assets.minDAmts(feeToken), _getMaxBorrow(posAddr, feeToken, assets.decimals(feeToken)));

            // Expectations
            uint256 maxFee = (_dAmt * PROTOCOL_FEE_RATE) / 1000;
            (uint256 userSavings, uint256 clientFee) = _getExpectedClientAllocations(maxFee, _clientTakeRate);
            uint256 protocolFee = maxFee - userSavings;

            // Pre-act balances
            feeCollectorBalances.preFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.preClientFeeTokenBal = IFeeCollector(FEE_COLLECTOR).balances(_client, feeToken);
            feeCollectorBalances.preTotalClientsFeeTokenBal = IFeeCollector(FEE_COLLECTOR).totalClientBalances(feeToken);

            // Act
            IPosition(posAddr).addLeverage(_dAmt, 0, TEST_POOL_FEE, _client);

            // Post-act balances
            feeCollectorBalances.postFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.postClientFeeTokenBal = IFeeCollector(FEE_COLLECTOR).balances(_client, feeToken);
            feeCollectorBalances.postTotalClientsFeeTokenBal =
                IFeeCollector(FEE_COLLECTOR).totalClientBalances(feeToken);

            // Assertions
            assertEq(feeCollectorBalances.postFeeTokenBal, feeCollectorBalances.preFeeTokenBal + protocolFee);
            assertEq(feeCollectorBalances.postClientFeeTokenBal, feeCollectorBalances.preClientFeeTokenBal + clientFee);
            assertEq(
                feeCollectorBalances.postTotalClientsFeeTokenBal,
                feeCollectorBalances.preTotalClientsFeeTokenBal + clientFee
            );

            // Revert to snapshot
            vm.revertTo(id);
        }
    }

    /// @dev
    // - The FeeCollector's feeToken balance should increase by (maxFee - userSavings).
    // - The feeToken totalClientBalances should not change
    // - The above should be true when _client is sent as address(0)
    function testFuzz_AddLeverageNoClient(uint256 _dAmt) public {
        // Setup
        FeeCollectorBalances memory feeCollectorBalances;

        // Take snapshot
        uint256 id = vm.snapshot();

        for (uint256 i; i < positions.length; i++) {
            // Test variables
            address posAddr = positions[i].addr;
            address cToken = positions[i].cToken;
            address feeToken = positions[i].dToken;

            // Add to position
            _fund(owner, cToken, assets.maxCAmts(cToken));
            IERC20(cToken).approve(posAddr, assets.maxCAmts(cToken));
            IPosition(posAddr).add(assets.maxCAmts(cToken), TEST_LTV, 0, TEST_POOL_FEE, address(0));

            // Bound fuzzed variables
            _dAmt = bound(_dAmt, assets.minDAmts(feeToken), _getMaxBorrow(posAddr, feeToken, assets.decimals(feeToken)));

            // Expectations
            uint256 maxFee = (_dAmt * PROTOCOL_FEE_RATE) / 1000;
            (uint256 userSavings,) = _getExpectedClientAllocations(maxFee, 0);
            uint256 protocolFee = maxFee - userSavings;

            // Pre-act balances
            feeCollectorBalances.preFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.preTotalClientsFeeTokenBal = IFeeCollector(FEE_COLLECTOR).totalClientBalances(feeToken);

            // Act
            IPosition(posAddr).addLeverage(_dAmt, 0, TEST_POOL_FEE, address(0));

            // Post-act balances
            feeCollectorBalances.postFeeTokenBal = IERC20(feeToken).balanceOf(FEE_COLLECTOR);
            feeCollectorBalances.postTotalClientsFeeTokenBal =
                IFeeCollector(FEE_COLLECTOR).totalClientBalances(feeToken);

            // Assertions
            assertEq(feeCollectorBalances.postFeeTokenBal, feeCollectorBalances.preFeeTokenBal + protocolFee);
            assertEq(feeCollectorBalances.postTotalClientsFeeTokenBal, feeCollectorBalances.preTotalClientsFeeTokenBal);

            // Revert to snapshot
            vm.revertTo(id);
        }
    }
}

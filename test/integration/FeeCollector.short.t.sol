// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

// External Imports
import { Test } from "forge-std/Test.sol";

// Local Imports
import { PositionFactory } from "src/PositionFactory.sol";
import { FeeCollector } from "src/FeeCollector.sol";
import {
    Assets,
    AAVE_ORACLE,
    CONTRACT_DEPLOYER,
    FEE_COLLECTOR,
    TEST_CLIENT,
    PROTOCOL_FEE_RATE,
    CLIENT_RATE,
    USDC,
    WETH,
    WBTC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { IFeeCollector } from "src/interfaces/IFeeCollector.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract FeeCollectorShortTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    struct TestPosition {
        address addr;
        address cToken;
        address dToken;
        address bToken;
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
    // - The FeeCollector's cToken balance should increase by protocolFee
    // - The cToken totalClientBalances should increase by clientFee
    // - The client's cToken balance on the FeeCollector contract should increase by clientFee
    function testFuzz_ShortCollectFeesWithClient(uint256 _cAmt) external payable {
        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address positionAddr = positions[i].addr;
            address cToken = positions[i].cToken;

            // Bound fuzzed variables
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Expectations
            uint256 protocolFee = (_cAmt * PROTOCOL_FEE_RATE) / 1000;
            uint256 clientFee = (protocolFee * CLIENT_RATE) / 100;

            // Fund positionOwner with _cAmt of cToken
            _fund(positionOwner, cToken, _cAmt);

            // Approve Position contract to spend collateral
            IERC20(cToken).approve(positionAddr, _cAmt);

            // Pre-act balances
            uint256 preContractBalance = IERC20(cToken).balanceOf(FEE_COLLECTOR);
            uint256 preTotalClientBalances = IFeeCollector(FEE_COLLECTOR).totalClientBalances(cToken);
            uint256 preClientFeeBalance = IFeeCollector(FEE_COLLECTOR).balances(TEST_CLIENT, cToken);

            // Act: increase short position
            IPosition(positionAddr).short(_cAmt, 50, 0, 3000, TEST_CLIENT);

            // Post-act balances
            uint256 postContractBalance = IERC20(cToken).balanceOf(FEE_COLLECTOR);
            uint256 postTotalClientBalances = IFeeCollector(FEE_COLLECTOR).totalClientBalances(cToken);
            uint256 postClientFeeBalance = IFeeCollector(FEE_COLLECTOR).balances(TEST_CLIENT, cToken);

            // Assertions
            assertEq(postContractBalance, preContractBalance + protocolFee);
            assertEq(postTotalClientBalances, preTotalClientBalances + clientFee);
            assertEq(postClientFeeBalance, preClientFeeBalance + clientFee);
        }
    }

    /// @dev
    // - The FeeCollector's cToken balance should increase by protocolFee
    // - The cToken totalClientBalances should not change
    // - The above should be true when _client is sent as address(0)
    function testFuzz_ShortCollectFeesNoClient(uint256 _cAmt) external payable {
        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address positionAddr = positions[i].addr;
            address cToken = positions[i].cToken;

            // Bound fuzzed variables
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Expectations
            uint256 protocolFee = (_cAmt * PROTOCOL_FEE_RATE) / 1000;

            // Fund positionOwner with _cAmt of cToken
            _fund(positionOwner, cToken, _cAmt);

            // Approve Position contract to spend collateral
            IERC20(cToken).approve(positionAddr, _cAmt);

            // Pre-act balances
            uint256 preContractBalance = IERC20(cToken).balanceOf(FEE_COLLECTOR);
            uint256 preTotalClientBalances = IFeeCollector(FEE_COLLECTOR).totalClientBalances(cToken);

            // Act: increase short position
            IPosition(positionAddr).short(_cAmt, 50, 0, 3000, address(0));

            // Post-act balances
            uint256 postContractBalance = IERC20(cToken).balanceOf(FEE_COLLECTOR);
            uint256 postTotalClientBalances = IFeeCollector(FEE_COLLECTOR).totalClientBalances(cToken);

            // Assertions
            assertEq(postContractBalance, preContractBalance + protocolFee);
            assertEq(postTotalClientBalances, preTotalClientBalances);
        }
    }
}

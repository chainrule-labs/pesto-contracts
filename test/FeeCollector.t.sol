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
    TEST_CLIENT,
    PROTOCOL_FEE,
    CLIENT_RATE,
    USDC,
    WETH,
    WBTC
} from "test/common/Constants.t.sol";
import { TokenUtils } from "test/common/utils/TokenUtils.t.sol";
import { IAaveOracle } from "src/interfaces/aave/IAaveOracle.sol";
import { IPosition } from "src/interfaces/IPosition.sol";
import { IERC20 } from "src/interfaces/token/IERC20.sol";

contract FeeCollectorTest is Test, TokenUtils {
    /* solhint-disable func-name-mixedcase */

    struct TestPosition {
        address addr;
        address cToken;
        address dToken;
        address bToken;
    }

    // Errors
    error OwnableUnauthorizedAccount(address account);

    // Test contracts
    PositionFactory public positionFactory;
    FeeCollector public feeCollector;
    Assets public assets;
    TestPosition[] public positions;

    // Test Storage
    uint256 public mainnetFork;
    address public feeCollectorAddr;
    address public positionOwner = address(this);

    // Events
    event Short(uint256 cAmt, uint256 dAmt, uint256 bAmt);

    function setUp() public {
        // Setup: use mainnet fork
        mainnetFork = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(mainnetFork);

        // Deploy assets
        assets = new Assets();
        address[4] memory supportedAssets = assets.getSupported();

        // Deploy FeeCollector
        vm.prank(CONTRACT_DEPLOYER);
        feeCollector = new FeeCollector(CONTRACT_DEPLOYER);
        feeCollectorAddr = address(feeCollector);

        // Deploy PositionFactory
        vm.prank(CONTRACT_DEPLOYER);
        positionFactory = new PositionFactory(CONTRACT_DEPLOYER, feeCollectorAddr);

        // Set client rate
        vm.prank(CONTRACT_DEPLOYER);
        feeCollector.setClientRate(CLIENT_RATE);

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
    // - The FeeCollector's feeToken balance should increase by _protocolFee
    // - The feeToken totalClientBalances should increase by clientFee
    // - The client's feeToken balance on the FeeCollector contract should increase by clientFee
    function testFuzz_CollectFeesWithClient(uint256 _protocolFee) external payable {
        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address feeToken = positions[i].cToken;

            // Bound fuzzed variables
            _protocolFee = bound(_protocolFee, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));

            // Expectations
            uint256 clientFee = (_protocolFee * CLIENT_RATE) / 100;

            // Fund positionOwner with _protocolFee amount of feeToken
            _fund(positionOwner, feeToken, _protocolFee);

            // Approve FeeCollector contract to spend feeToken
            IERC20(feeToken).approve(feeCollectorAddr, _protocolFee);

            // Pre-act balances
            uint256 preContractBalance = IERC20(feeToken).balanceOf(feeCollectorAddr);
            uint256 preTotalClientBalances = feeCollector.totalClientBalances(feeToken);
            uint256 preClientFeeBalance = feeCollector.balances(TEST_CLIENT, feeToken);

            // Act: collect fees
            feeCollector.collectFees(TEST_CLIENT, feeToken, _protocolFee);

            // Post-act balances
            uint256 postContractBalance = IERC20(feeToken).balanceOf(feeCollectorAddr);
            uint256 postTotalClientBalances = feeCollector.totalClientBalances(feeToken);
            uint256 postClientFeeBalance = feeCollector.balances(TEST_CLIENT, feeToken);

            // Assertions
            assertEq(postContractBalance, preContractBalance + _protocolFee);
            assertEq(postTotalClientBalances, preTotalClientBalances + clientFee);
            assertEq(postClientFeeBalance, preClientFeeBalance + clientFee);
        }
    }

    /// @dev
    // - The FeeCollector's feeToken balance should increase by _protocolFee
    // - The feeToken totalClientBalances should not change
    // - The above should be true when _client is sent as address(0)
    function testFuzz_CollectFeesNoClient(uint256 _protocolFee) external payable {
        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address feeToken = positions[i].cToken;

            // Bound fuzzed variables
            _protocolFee = bound(_protocolFee, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));

            // Fund positionOwner with _protocolFee amount of feeToken
            _fund(positionOwner, feeToken, _protocolFee);

            // Approve FeeCollector contract to spend feeToken
            IERC20(feeToken).approve(feeCollectorAddr, _protocolFee);

            // Pre-act balances
            uint256 preContractBalance = IERC20(feeToken).balanceOf(feeCollectorAddr);
            uint256 preTotalClientBalances = feeCollector.totalClientBalances(feeToken);

            // Act: collect fees
            feeCollector.collectFees(address(0), feeToken, _protocolFee);

            // Post-act balances
            uint256 postContractBalance = IERC20(feeToken).balanceOf(feeCollectorAddr);
            uint256 postTotalClientBalances = feeCollector.totalClientBalances(feeToken);

            // Assertions
            assertEq(postContractBalance, preContractBalance + _protocolFee);
            assertEq(postTotalClientBalances, preTotalClientBalances);
        }
    }

    /// @dev
    // - The FeeCollector's cToken balance should increase by protocolFee
    // - The cToken totalClientBalances should increase by clientFee
    // - The client's cToken balance on the FeeCollector contract should increase by clientFee
    function testFuzz_CollectFeesWithClientIntegrated(uint256 _cAmt) external payable {
        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address positionAddr = positions[i].addr;
            address cToken = positions[i].cToken;

            // Bound fuzzed variables
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Expectations
            uint256 protocolFee = (_cAmt * PROTOCOL_FEE) / 1000;
            uint256 clientFee = (protocolFee * CLIENT_RATE) / 100;

            // Fund positionOwner with _cAmt of cToken
            _fund(positionOwner, cToken, _cAmt);

            // Approve Position contract to spend collateral
            IERC20(cToken).approve(positionAddr, _cAmt);

            // Pre-act balances
            uint256 preContractBalance = IERC20(cToken).balanceOf(feeCollectorAddr);
            uint256 preTotalClientBalances = feeCollector.totalClientBalances(cToken);
            uint256 preClientCTokenFeeBalance = feeCollector.balances(TEST_CLIENT, cToken);

            // Act: increase short position
            IPosition(positionAddr).short(_cAmt, 50, 0, 3000, TEST_CLIENT);

            // Post-act balances
            uint256 postContractBalance = IERC20(cToken).balanceOf(feeCollectorAddr);
            uint256 postTotalClientBalances = feeCollector.totalClientBalances(cToken);
            uint256 postClientCTokenFeeBalance = feeCollector.balances(TEST_CLIENT, cToken);

            // Assertions
            assertEq(postContractBalance, preContractBalance + protocolFee);
            assertEq(postTotalClientBalances, preTotalClientBalances + clientFee);
            assertEq(postClientCTokenFeeBalance, preClientCTokenFeeBalance + clientFee);
        }
    }

    /// @dev
    // - The FeeCollector's cToken balance should increase by protocolFee
    // - The cToken totalClientBalances should not change
    // - The above should be true when _client is sent as address(0)
    function testFuzz_CollectFeesNoClientIntegrated(uint256 _cAmt) external payable {
        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address positionAddr = positions[i].addr;
            address cToken = positions[i].cToken;

            // Bound fuzzed variables
            _cAmt = bound(_cAmt, assets.minCAmts(cToken), assets.maxCAmts(cToken));

            // Expectations
            uint256 protocolFee = (_cAmt * PROTOCOL_FEE) / 1000;

            // Fund positionOwner with _cAmt of cToken
            _fund(positionOwner, cToken, _cAmt);

            // Approve Position contract to spend collateral
            IERC20(cToken).approve(positionAddr, _cAmt);

            // Pre-act balances
            uint256 preContractBalance = IERC20(cToken).balanceOf(feeCollectorAddr);
            uint256 preTotalClientBalances = feeCollector.totalClientBalances(cToken);

            // Act: increase short position
            IPosition(positionAddr).short(_cAmt, 50, 0, 3000, address(0));

            // Post-act balances
            uint256 postContractBalance = IERC20(cToken).balanceOf(feeCollectorAddr);
            uint256 postTotalClientBalances = feeCollector.totalClientBalances(cToken);

            // Assertions
            assertEq(postContractBalance, preContractBalance + protocolFee);
            assertEq(postTotalClientBalances, preTotalClientBalances);
        }
    }

    /// @dev
    // - The FeeCollector's feeToken balance should decrease by amount withdrawn
    // - The feeToken totalClientBalances should decrease by amount withdrawn
    // - The client's feeToken balance on the FeeCollector contract should decrease by amount withdrawn
    // - The feeToken balance of client's account should increase by amount withdrawn
    function testFuzz_ClientWithdraw(uint256 _amount) external payable {
        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address feeToken = positions[i].cToken;

            // Bound fuzzed variables
            _amount = bound(_amount, assets.minCAmts(feeToken), assets.maxCAmts(feeToken));

            // Fund positionOwner with _amount of feeToken
            _fund(positionOwner, feeToken, _amount);

            // Approve FeeCollector contract to spend feeToken
            IERC20(feeToken).approve(feeCollectorAddr, _amount);

            // Collect fees
            feeCollector.collectFees(TEST_CLIENT, feeToken, _amount);

            // Pre-act balances
            uint256 preContractBalance = IERC20(feeToken).balanceOf(feeCollectorAddr);
            uint256 preTotalClientBalances = feeCollector.totalClientBalances(feeToken);
            uint256 preClientContractBalance = feeCollector.balances(TEST_CLIENT, feeToken);
            uint256 preClientAccountBalance = IERC20(feeToken).balanceOf(TEST_CLIENT);

            // Act: client withdraws fees
            vm.prank(TEST_CLIENT);
            feeCollector.clientWithdraw(feeToken);

            // Post-act balances
            uint256 postContractBalance = IERC20(feeToken).balanceOf(feeCollectorAddr);
            uint256 postTotalClientBalances = feeCollector.totalClientBalances(feeToken);
            uint256 postClientContractBalance = feeCollector.balances(TEST_CLIENT, feeToken);
            uint256 postClientAccountBalance = IERC20(feeToken).balanceOf(TEST_CLIENT);

            // Assertions
            assertEq(postContractBalance, preContractBalance - preClientContractBalance);
            assertEq(postTotalClientBalances, preTotalClientBalances - preClientContractBalance);
            assertEq(postClientContractBalance, 0);
            assertEq(postClientAccountBalance, preClientAccountBalance + preClientContractBalance);
        }
    }

    /// @dev
    // - The current client rate should be updated to new client rate
    function testFuzz_SetClientRate(uint256 _clientRate) external payable {
        // Bound fuzzed variables
        _clientRate = bound(_clientRate, 30, 100);

        // Pre-act data
        uint256 preClientRate = feeCollector.clientRate();

        // Assertions
        assertEq(preClientRate, CLIENT_RATE);

        // Act
        vm.prank(CONTRACT_DEPLOYER);
        feeCollector.setClientRate(_clientRate);

        // Post-act data
        uint256 postClientRate = feeCollector.clientRate();

        // Assertions
        assertEq(postClientRate, _clientRate);
    }

    /// @dev
    // - The clientRate in FeeCollector contract cannot be < 30 or > 100
    function testFuzz_CannotSetClientRateOutOfRange(uint256 _clientRate) external payable {
        // Assumptions
        vm.assume(_clientRate < 30 || _clientRate > 100);

        // Act
        vm.prank(CONTRACT_DEPLOYER);
        vm.expectRevert(FeeCollector.OutOfRange.selector);
        feeCollector.setClientRate(_clientRate);
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotSetClientRateUnauthorized(uint256 _clientRate, address _sender) external payable {
        // Assumptions
        _clientRate = bound(_clientRate, 30, 100);
        vm.assume(_sender != CONTRACT_DEPLOYER);

        // Act
        vm.prank(_sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, _sender));
        feeCollector.setClientRate(_clientRate);
    }

    /// @dev
    // - The FeeCollector's native balance should decrease by the amount transferred.
    // - The owner's native balance should increase by the amount transferred.
    function testFuzz_ExtractNative(uint256 _amount) public {
        // Setup: fund contract with _amount of native token
        _amount = bound(_amount, 1, 1e22);
        vm.deal(feeCollectorAddr, _amount);

        // Get pre-act balances
        uint256 preContractBalance = feeCollectorAddr.balance;
        uint256 preOwnerBalance = CONTRACT_DEPLOYER.balance;

        // Assertions
        assertEq(preContractBalance, _amount);

        // Act
        vm.prank(CONTRACT_DEPLOYER);
        feeCollector.extractNative();

        // Ge post-act balances
        uint256 postContractBalance = feeCollectorAddr.balance;
        uint256 postOwnerBalance = CONTRACT_DEPLOYER.balance;

        // Assertions
        assertEq(postContractBalance, 0);
        assertEq(postOwnerBalance, preOwnerBalance + _amount);
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotExtractNative(uint256 _amount, address _sender) public {
        // Setup: fund contract with _amount of native token
        _amount = bound(_amount, 1, 1e22);
        vm.assume(_sender != CONTRACT_DEPLOYER);
        vm.deal(feeCollectorAddr, _amount);

        // Act: attempt to extract native
        vm.prank(_sender);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, _sender));
        feeCollector.extractNative();
    }

    /// @dev
    // - For the specified feeToken, the owner's balance should increase by (total balance - totalClientBalances).
    // - For the specified feeToken, the FeeCollector's balance should decrease by (total balance - totalClientBalances).
    // - The token totalClientBalances should not change
    function testFuzz_ExtractERC20(uint256 _amount) public {
        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address token = positions[i].cToken;

            // Bound fuzzed variables
            _amount = bound(_amount, assets.minCAmts(token), assets.maxCAmts(token));

            // Fund positionOwner with _amount of token
            _fund(positionOwner, token, _amount);

            // Approve FeeCollector contract to spend token
            IERC20(token).approve(feeCollectorAddr, _amount);

            // Collect fees
            feeCollector.collectFees(TEST_CLIENT, token, _amount);

            // Pre-act balances
            uint256 preContractTokenBalance = IERC20(token).balanceOf(feeCollectorAddr);
            uint256 preOwnerTokenBalance = IERC20(token).balanceOf(CONTRACT_DEPLOYER);
            uint256 preTotalClientBalances = feeCollector.totalClientBalances(token);

            // Act: owner withraws fees
            vm.prank(CONTRACT_DEPLOYER);
            feeCollector.extractERC20(token);

            // Post-act balances
            uint256 postContractTokenBalance = IERC20(token).balanceOf(feeCollectorAddr);
            uint256 postOwnerTokenBalance = IERC20(token).balanceOf(CONTRACT_DEPLOYER);
            uint256 postTotalClientBalances = feeCollector.totalClientBalances(token);

            // Assertions
            assertEq(postContractTokenBalance, preTotalClientBalances);
            assertEq(postOwnerTokenBalance, preOwnerTokenBalance + (preContractTokenBalance - preTotalClientBalances));
            assertEq(postTotalClientBalances, preTotalClientBalances);
        }
    }

    /// @dev
    // - It should revert with Unauthorized() error when called by an unauthorized sender.
    function testFuzz_CannotExtractERC20(uint256 _amount, address _sender) public {
        // Assumptions
        vm.assume(_sender != CONTRACT_DEPLOYER);

        for (uint256 i; i < positions.length; i++) {
            // Test Variables
            address token = positions[i].cToken;

            // Bound fuzzed variables
            _amount = bound(_amount, assets.minCAmts(token), assets.maxCAmts(token));

            // Fund positionOwner with _amount of token
            _fund(positionOwner, token, _amount);

            // Approve FeeCollector contract to spend token
            IERC20(token).approve(feeCollectorAddr, _amount);

            // Collect fees
            feeCollector.collectFees(TEST_CLIENT, token, _amount);

            // Act: attempt to extract ERC20 token
            vm.prank(_sender);
            vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, _sender));
            feeCollector.extractERC20(token);
        }
    }

    /// @dev
    // - The FeeCollector's native balance should increase by the amount transferred.
    function testFuzz_Receive(uint256 _amount, address _sender) public {
        // Assumptions
        _amount = bound(_amount, 1, 1_000 ether);
        uint256 gasMoney = 1 ether;
        vm.deal(_sender, _amount + gasMoney);

        // Pre-Act Data
        uint256 preContractBalance = feeCollectorAddr.balance;

        // Act
        vm.prank(_sender);
        (bool success,) = payable(feeCollectorAddr).call{ value: _amount }("");

        // Post-Act Data
        uint256 postContractBalance = feeCollectorAddr.balance;

        // Assertions
        assertTrue(success);
        assertEq(postContractBalance, preContractBalance + _amount);
    }

    /// @dev
    // - The FeeCollector's native balance should increase by the amount transferred.
    function testFuzz_Fallback(uint256 _amount, address _sender) public {
        // Assumptions
        vm.assume(_amount != 0 && _amount <= 1000 ether);
        uint256 gasMoney = 1 ether;
        vm.deal(_sender, _amount + gasMoney);

        // Pre-Act Data
        uint256 preSenderBalance = _sender.balance;
        uint256 preContractBalance = feeCollectorAddr.balance;

        // Act
        vm.prank(_sender);
        (bool success,) = feeCollectorAddr.call{ value: _amount }(abi.encodeWithSignature("nonExistentFn()"));

        // Post-Act Data
        uint256 postSenderBalance = _sender.balance;
        uint256 postContractBalance = feeCollectorAddr.balance;

        // Assertions
        assertTrue(success);
        assertEq(postSenderBalance, preSenderBalance - _amount);
        assertEq(postContractBalance, preContractBalance + _amount);
    }
}

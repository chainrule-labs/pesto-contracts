// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

address constant CONTRACT_DEPLOYER = 0x0a5B347509621337cDDf44CBCf6B6E7C9C908CD2;
address constant AAVE_ORACLE = 0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7;

// Supported Assets
address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

// Largest USDC holder (GMX)
address constant USDC_HOLDER = 0x47c031236e19d024b42f8AE6780E44A573170703;

// Supported

contract Assets {
    address[4] public supported = [USDC, DAI, WETH, WBTC];
    mapping(address => uint8) public decimals;
    mapping(address => uint256) public maxCAmts;
    mapping(address => uint256) public prices;

    constructor() {
        // Set decimals
        decimals[USDC] = 6;
        decimals[DAI] = 18;
        decimals[WETH] = 18;
        decimals[WBTC] = 8;

        // Set max collateral amounts
        maxCAmts[USDC] = 100_000 * 10 ** 6;
        maxCAmts[DAI] = 100_000 * 10 ** 18;
        maxCAmts[WETH] = 50 * 10 ** 18;
        maxCAmts[WBTC] = 2 * 10 ** 8;

        // Set prices
        prices[USDC] = 1 * 10 ** 8;
        prices[DAI] = 1 * 10 ** 8;
        prices[WETH] = 2_000 * 10 ** 8;
        prices[WBTC] = 50_000 * 10 ** 8;
    }

    function getSupported() external view returns (address[4] memory) {
        return supported;
    }
}

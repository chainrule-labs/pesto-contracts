// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

address constant CONTRACT_DEPLOYER = 0x0a5B347509621337cDDf44CBCf6B6E7C9C908CD2;

// Supported Assets (not including native ETH)
address constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;

// Supported

contract Assets {
    address[4] public supported = [USDC, DAI, WETH, WBTC];

    function getSupported() external view returns (address[4] memory) {
        return supported;
    }
}

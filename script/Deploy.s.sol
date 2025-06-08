// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {StrategyExecutor} from "../src/StrategyExecutor.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";

/**
 * @title Deploy
 * @dev Production deployment script for DeFi MVP
 * Deploys shared StrategyExecutor and ProxyFactory for all users
 */
contract Deploy is Script {
    // ============ Polygon Mainnet Addresses ============
    address constant POLYGON_USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant POLYGON_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant POLYGON_AUSDT = 0x6ab707Aca953eDAeFBc4fD23bA73294241490620;
    address constant POLYGON_AUSDC = 0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD;
    address constant POLYGON_AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant POLYGON_UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant PAPAYA = 0x444a597c2DcaDF71187b4c7034D73B8Fa80744E2;
    address constant FEE_RECIPIENT = 0x7bfc84257b6D818c4e49Eeb7B9422569154EE5a6;
    
    // ============ Configuration ============
    uint256 constant FEE_BPS = 100; // 1%

    function run() external {
        vm.startBroadcast();

        // Deploy shared StrategyExecutor (works with any ProxyAccount)
        StrategyExecutor sharedStrategy = new StrategyExecutor(
            POLYGON_USDT,              // USDT token
            POLYGON_USDC,              // USDC token
            POLYGON_AAVE_POOL,         // Aave lending pool
            POLYGON_UNISWAP_ROUTER     // Uniswap V3 router
        );

        // Deploy ProxyFactory (shared contract for all users)
        ProxyFactory proxyFactory = new ProxyFactory(
            address(sharedStrategy),   // Shared strategy executor
            PAPAYA,                    // Papaya contract
            FEE_RECIPIENT,             // Fee recipient
            FEE_BPS,                   // 1% fee
            POLYGON_USDT,              // USDT token
            POLYGON_USDC,              // USDC token
            POLYGON_AAVE_POOL,         // Aave lending pool
            POLYGON_AUSDT,             // aUSDT token
            POLYGON_AUSDC,             // aUSDC token
            POLYGON_UNISWAP_ROUTER     // Uniswap V3 router
        );

        vm.stopBroadcast();

        console.log("ProxyFactory deployed at:", address(proxyFactory));
        
        // ============ MVP Deployment Summary ============
        console.log("\n=== DeFi MVP Deployment Complete ===");
        console.log("Shared StrategyExecutor:", address(sharedStrategy));
        console.log("ProxyFactory:", address(proxyFactory));
        console.log("Fee Recipient:", FEE_RECIPIENT);
        console.log("Fee Rate: 1%");
        console.log("\n=== User Flow ===");
        console.log("1. Users call proxyFactory.createProxy()");
        console.log("2. Users approve USDT to their proxy");
        console.log("3. Users call proxy.runStrategy(sharedStrategy, amount)");
        console.log("4. Users call proxy.claim() to withdraw yields");
    }
} 
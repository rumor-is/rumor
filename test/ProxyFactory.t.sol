// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import {ProxyAccount} from "../src/ProxyAccount.sol";

// Mock StrategyExecutor contract
contract MockStrategyExecutor {
    function execute(uint256 amount) external {
        // Mock implementation - just accepts the call
    }
}

// Mock Papaya contract
contract MockPapaya {
    function withdraw(address token) external {
        // Mock implementation - just accepts the call
    }
}

contract ProxyFactoryTest is Test {
    ProxyFactory public factory;
    MockStrategyExecutor public mockStrategy;
    MockPapaya public mockPapaya;
    
    // Mock protocol addresses (using dummy addresses for testing)
    address constant MOCK_USDT = 0x1000000000000000000000000000000000000001;
    address constant MOCK_USDC = 0x1000000000000000000000000000000000000002;
    address constant MOCK_AAVE_POOL = 0x1000000000000000000000000000000000000003;
    address constant MOCK_AUSDT = 0x1000000000000000000000000000000000000004;
    address constant MOCK_AUSDC = 0x1000000000000000000000000000000000000005;
    address constant MOCK_UNISWAP_ROUTER = 0x1000000000000000000000000000000000000006;
    
    function setUp() public {
        // Deploy mock contracts
        mockStrategy = new MockStrategyExecutor();
        mockPapaya = new MockPapaya();
        
        // Deploy ProxyFactory with mock addresses
        factory = new ProxyFactory(
            address(mockStrategy),    // strategyExecutor
            address(mockPapaya),      // papayaContract
            MOCK_USDT,               // usdt
            MOCK_USDC,               // usdc
            MOCK_AAVE_POOL,          // aavePool
            MOCK_AUSDT,              // aUsdt
            MOCK_AUSDC,              // aUsdc
            MOCK_UNISWAP_ROUTER      // uniswapRouter
        );
    }
    
    function testCreateProxy() public {
        address user = address(this);
        
        // Log initial state
        console.log("User address:", user);
        console.log("Initial proxy for user:", factory.proxies(user));
        
        // Verify user doesn't have a proxy initially
        assertEq(factory.proxies(user), address(0), "User should not have a proxy initially");
        
        // Create proxy
        address proxyAddress = factory.createProxy();
        
        // Log results
        console.log("Created proxy address:", proxyAddress);
        console.log("Factory proxies mapping:", factory.proxies(user));
        
        // Check: factory.proxies(user) is not zero
        assertNotEq(factory.proxies(user), address(0), "User should have a proxy after creation");
        assertEq(factory.proxies(user), proxyAddress, "Factory mapping should match returned address");
        
        // Get the ProxyAccount instance
        ProxyAccount proxy = ProxyAccount(factory.proxies(user));
        
        // Check: ProxyAccount(factory.proxies(user)).owner() == user
        assertEq(proxy.owner(), user, "Proxy owner should be the user");
        console.log("Proxy owner:", proxy.owner());
        
        // Check: ProxyAccount(factory.proxies(user)).strategy() == passed strategy
        assertEq(proxy.strategy(), address(mockStrategy), "Proxy strategy should match factory's strategy");
        console.log("Proxy strategy:", proxy.strategy());
        console.log("Expected strategy:", address(mockStrategy));
        
        // Check: ProxyAccount(factory.proxies(user)).papaya() == passed papaya
        assertEq(proxy.papaya(), address(mockPapaya), "Proxy papaya should match factory's papaya");
        console.log("Proxy papaya:", proxy.papaya());
        console.log("Expected papaya:", address(mockPapaya));
        
        // Verify protocol addresses are set correctly
        assertEq(proxy.usdt(), MOCK_USDT, "USDT address should be set correctly");
        assertEq(proxy.usdc(), MOCK_USDC, "USDC address should be set correctly");
        assertEq(proxy.aavePool(), MOCK_AAVE_POOL, "Aave pool address should be set correctly");
        assertEq(proxy.aUsdt(), MOCK_AUSDT, "aUSDT address should be set correctly");
        assertEq(proxy.aUsdc(), MOCK_AUSDC, "aUSDC address should be set correctly");
        assertEq(proxy.uniswapRouter(), MOCK_UNISWAP_ROUTER, "Uniswap router address should be set correctly");
        
        console.log("All checks passed!");
    }
    
    function testCreateProxyTwiceFails() public {
        // Create first proxy successfully
        factory.createProxy();
        
        // Try to create second proxy - should fail
        vm.expectRevert("ProxyFactory: user already has a proxy");
        factory.createProxy();
    }
    
    function testCreateProxyFromDifferentUser() public {
        address user1 = address(this);
        address user2 = address(0x123);
        
        // Create proxy for user1
        address proxy1 = factory.createProxy();
        
        // Create proxy for user2
        vm.prank(user2);
        address proxy2 = factory.createProxy();
        
        // Verify both users have different proxies
        assertNotEq(proxy1, proxy2, "Different users should have different proxies");
        assertEq(factory.proxies(user1), proxy1, "User1 should have proxy1");
        assertEq(factory.proxies(user2), proxy2, "User2 should have proxy2");
        
        // Verify owners are correct
        assertEq(ProxyAccount(proxy1).owner(), user1, "Proxy1 should be owned by user1");
        assertEq(ProxyAccount(proxy2).owner(), user2, "Proxy2 should be owned by user2");
    }
    
    function testProxyCreatedEvent() public {
        address user = address(this);
        
        // Expect ProxyCreated event
        vm.expectEmit(true, false, false, false);
        emit ProxyFactory.ProxyCreated(user, address(0)); // We don't know the proxy address yet
        
        factory.createProxy();
    }
} 
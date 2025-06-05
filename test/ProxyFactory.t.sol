// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import {ProxyAccount} from "../src/ProxyAccount.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock StrategyExecutor contract
contract MockStrategyExecutor {
    function execute(uint256 amount) external {
        // Mock implementation - just accepts the call
    }
    
    function run(uint256 amount) external {
        // Mock implementation for LendingStrategy interface
    }
}

// Mock Papaya contract
contract MockPapaya {
    function withdraw(address token) external {
        // Mock implementation - just accepts the call
    }
}

// Mock ERC20 token for testing
contract MockERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }
}

contract ProxyFactoryTest is Test {
    ProxyFactory public factory;
    MockStrategyExecutor public mockStrategy;
    MockPapaya public mockPapaya;
    MockERC20 public mockUSDT;
    
    // Mock protocol addresses (using dummy addresses for testing)
    address constant MOCK_USDC = 0x1000000000000000000000000000000000000002;
    address constant MOCK_AAVE_POOL = 0x1000000000000000000000000000000000000003;
    address constant MOCK_AUSDT = 0x1000000000000000000000000000000000000004;
    address constant MOCK_AUSDC = 0x1000000000000000000000000000000000000005;
    address constant MOCK_UNISWAP_ROUTER = 0x1000000000000000000000000000000000000006;
    
    // Fee configuration
    address constant FEE_RECIPIENT = 0x7bfc84257b6D818c4e49Eeb7B9422569154EE5a6;
    uint256 constant FEE_BPS = 100; // 1%
    
    function setUp() public {
        // Deploy mock contracts
        mockStrategy = new MockStrategyExecutor();
        mockPapaya = new MockPapaya();
        mockUSDT = new MockERC20();
        
        // Deploy ProxyFactory with mock addresses
        factory = new ProxyFactory(
            address(mockStrategy),    // strategyExecutor
            address(mockPapaya),      // papayaContract
            FEE_RECIPIENT,           // feeRecipient
            FEE_BPS,                 // feeBps
            address(mockUSDT),       // usdt
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
        
        // Check fee configuration
        assertEq(proxy.feeRecipient(), FEE_RECIPIENT, "Fee recipient should be set correctly");
        assertEq(proxy.feeBps(), FEE_BPS, "Fee BPS should be set correctly");
        
        // Verify protocol addresses are set correctly
        assertEq(proxy.usdt(), address(mockUSDT), "USDT address should be set correctly");
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
    
    function testFeeTransferAndInvestmentTracking() public {
        address user = address(this);
        
        // Create proxy
        address proxyAddress = factory.createProxy();
        ProxyAccount proxy = ProxyAccount(proxyAddress);
        
        // Mint USDT to proxy
        uint256 investmentAmount = 1000 * 1e18; // 1000 USDT
        mockUSDT.mint(proxyAddress, investmentAmount);
        
        // Calculate expected fee and investment
        uint256 expectedFee = (investmentAmount * FEE_BPS) / 10000; // 1% of 1000 = 10 USDT
        uint256 expectedInvestment = investmentAmount - expectedFee; // 990 USDT
        
        // Get initial balances
        uint256 initialFeeRecipientBalance = mockUSDT.balanceOf(FEE_RECIPIENT);
        uint256 initialTotalInvested = proxy.totalInvested(user);
        
        // Run strategy
        proxy.runStrategy(address(mockStrategy), investmentAmount);
        
        // Verify fee was transferred
        uint256 finalFeeRecipientBalance = mockUSDT.balanceOf(FEE_RECIPIENT);
        assertEq(finalFeeRecipientBalance - initialFeeRecipientBalance, expectedFee, "Fee should be transferred to fee recipient");
        
        // Verify investment tracking
        uint256 finalTotalInvested = proxy.totalInvested(user);
        assertEq(finalTotalInvested - initialTotalInvested, expectedInvestment, "Investment amount should be tracked correctly");
        
        console.log("Fee transferred:", expectedFee);
        console.log("Investment tracked:", expectedInvestment);
    }
    
    function testDefaultStrategyWithFees() public {
        address user = address(this);
        
        // Create proxy
        address proxyAddress = factory.createProxy();
        ProxyAccount proxy = ProxyAccount(proxyAddress);
        
        // Mint USDT to proxy
        uint256 investmentAmount = 500 * 1e18; // 500 USDT
        mockUSDT.mint(proxyAddress, investmentAmount);
        
        // Calculate expected fee and investment
        uint256 expectedFee = (investmentAmount * FEE_BPS) / 10000; // 1% of 500 = 5 USDT
        uint256 expectedInvestment = investmentAmount - expectedFee; // 495 USDT
        
        // Get initial balances
        uint256 initialFeeRecipientBalance = mockUSDT.balanceOf(FEE_RECIPIENT);
        uint256 initialTotalInvested = proxy.totalInvested(user);
        
        // Run default strategy
        proxy.runDefaultStrategy(investmentAmount);
        
        // Verify fee was transferred
        uint256 finalFeeRecipientBalance = mockUSDT.balanceOf(FEE_RECIPIENT);
        assertEq(finalFeeRecipientBalance - initialFeeRecipientBalance, expectedFee, "Fee should be transferred to fee recipient");
        
        // Verify investment tracking
        uint256 finalTotalInvested = proxy.totalInvested(user);
        assertEq(finalTotalInvested - initialTotalInvested, expectedInvestment, "Investment amount should be tracked correctly");
        
        console.log("Default strategy fee transferred:", expectedFee);
        console.log("Default strategy investment tracked:", expectedInvestment);
    }
    
    function testZeroFeeConfiguration() public {
        // Deploy factory with zero fee
        ProxyFactory zeroFeeFactory = new ProxyFactory(
            address(mockStrategy),
            address(mockPapaya),
            FEE_RECIPIENT,
            0, // 0% fee
            address(mockUSDT),
            MOCK_USDC,
            MOCK_AAVE_POOL,
            MOCK_AUSDT,
            MOCK_AUSDC,
            MOCK_UNISWAP_ROUTER
        );
        
        address user = address(this);
        
        // Create proxy with zero fee
        address proxyAddress = zeroFeeFactory.createProxy();
        ProxyAccount proxy = ProxyAccount(proxyAddress);
        
        // Mint USDT to proxy
        uint256 investmentAmount = 1000 * 1e18;
        mockUSDT.mint(proxyAddress, investmentAmount);
        
        // Get initial balances
        uint256 initialFeeRecipientBalance = mockUSDT.balanceOf(FEE_RECIPIENT);
        uint256 initialTotalInvested = proxy.totalInvested(user);
        
        // Run strategy
        proxy.runStrategy(address(mockStrategy), investmentAmount);
        
        // Verify no fee was transferred
        uint256 finalFeeRecipientBalance = mockUSDT.balanceOf(FEE_RECIPIENT);
        assertEq(finalFeeRecipientBalance, initialFeeRecipientBalance, "No fee should be transferred with 0% fee");
        
        // Verify full amount is tracked as investment
        uint256 finalTotalInvested = proxy.totalInvested(user);
        assertEq(finalTotalInvested - initialTotalInvested, investmentAmount, "Full amount should be tracked as investment with 0% fee");
    }
} 
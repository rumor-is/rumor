// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import {ProxyAccount} from "../src/ProxyAccount.sol";
import {StrategyExecutor} from "../src/StrategyExecutor.sol";

/**
 * @title ProxyFactoryTest
 * @dev Test suite for ProxyFactory contract functionality with shared StrategyExecutor
 */
contract ProxyFactoryTest is Test {
    // ============ Constants ============
    address constant PAPAYA = address(0x2);
    address constant FEE_RECIPIENT = address(0x3);
    uint256 constant FEE_BPS = 100; // 1%
    
    address constant USDT = address(0x4);
    address constant USDC = address(0x5);
    address constant AAVE_POOL = address(0x6);
    address constant AUSDT = address(0x7);
    address constant AUSDC = address(0x8);
    address constant UNISWAP_ROUTER = address(0x9);
    
    // ============ Test Contracts ============
    ProxyFactory public factory;
    StrategyExecutor public sharedStrategy;
    
    function setUp() public {
        // Deploy shared strategy executor first
        sharedStrategy = new StrategyExecutor(
            USDT,
            USDC,
            AAVE_POOL,
            UNISWAP_ROUTER
        );
        
        // Deploy factory with shared strategy
        factory = new ProxyFactory(
            address(sharedStrategy),
            PAPAYA,
            FEE_RECIPIENT,
            FEE_BPS,
            USDT,
            USDC,
            AAVE_POOL,
            AUSDT,
            AUSDC,
            UNISWAP_ROUTER
        );
    }

    // ============ Constructor Tests ============
    function testConstructorSetsCorrectValues() public view {
        assertEq(factory.strategyExecutor(), address(sharedStrategy));
        assertEq(factory.papayaContract(), PAPAYA);
        assertEq(factory.feeRecipient(), FEE_RECIPIENT);
        assertEq(factory.feeBps(), FEE_BPS);
        assertEq(factory.usdt(), USDT);
        assertEq(factory.usdc(), USDC);
        assertEq(factory.aavePool(), AAVE_POOL);
        assertEq(factory.aUsdt(), AUSDT);
        assertEq(factory.aUsdc(), AUSDC);
        assertEq(factory.uniswapRouter(), UNISWAP_ROUTER);
    }

    function testRevertsWhenStrategyExecutorIsZero() public {
        vm.expectRevert("ProxyFactory: strategyExecutor is zero address");
        new ProxyFactory(
            address(0), PAPAYA, FEE_RECIPIENT, FEE_BPS,
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testRevertsWhenPapayaIsZero() public {
        vm.expectRevert("ProxyFactory: papayaContract is zero address");
        new ProxyFactory(
            address(sharedStrategy), address(0), FEE_RECIPIENT, FEE_BPS,
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testRevertsWhenUsdtIsZero() public {
        vm.expectRevert("ProxyFactory: USDT is zero address");
        new ProxyFactory(
            address(sharedStrategy), PAPAYA, FEE_RECIPIENT, FEE_BPS,
            address(0), USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testRevertsWhenUsdcIsZero() public {
        vm.expectRevert("ProxyFactory: USDC is zero address");
        new ProxyFactory(
            address(sharedStrategy), PAPAYA, FEE_RECIPIENT, FEE_BPS,
            USDT, address(0), AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testRevertsWhenAavePoolIsZero() public {
        vm.expectRevert("ProxyFactory: aavePool is zero address");
        new ProxyFactory(
            address(sharedStrategy), PAPAYA, FEE_RECIPIENT, FEE_BPS,
            USDT, USDC, address(0), AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testRevertsWhenAUsdtIsZero() public {
        vm.expectRevert("ProxyFactory: aUSDT is zero address");
        new ProxyFactory(
            address(sharedStrategy), PAPAYA, FEE_RECIPIENT, FEE_BPS,
            USDT, USDC, AAVE_POOL, address(0), AUSDC, UNISWAP_ROUTER
        );
    }

    function testRevertsWhenAUsdcIsZero() public {
        vm.expectRevert("ProxyFactory: aUSDC is zero address");
        new ProxyFactory(
            address(sharedStrategy), PAPAYA, FEE_RECIPIENT, FEE_BPS,
            USDT, USDC, AAVE_POOL, AUSDT, address(0), UNISWAP_ROUTER
        );
    }

    function testRevertsWhenUniswapRouterIsZero() public {
        vm.expectRevert("ProxyFactory: uniswapRouter is zero address");
        new ProxyFactory(
            address(sharedStrategy), PAPAYA, FEE_RECIPIENT, FEE_BPS,
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, address(0)
        );
    }

    function testRevertsWhenFeeBpsExceedsMaximum() public {
        vm.expectRevert("ProxyFactory: fee BPS cannot exceed 100%");
        new ProxyFactory(
            address(sharedStrategy), PAPAYA, FEE_RECIPIENT, 10001, // > 100%
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testAllowsZeroFeeRecipient() public {
        ProxyFactory factoryWithZeroFee = new ProxyFactory(
            address(sharedStrategy), PAPAYA, address(0), 0,
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
        
        assertEq(factoryWithZeroFee.feeRecipient(), address(0));
        assertEq(factoryWithZeroFee.feeBps(), 0);
    }

    function testAllowsMaximumFeeBps() public {
        ProxyFactory factoryWithMaxFee = new ProxyFactory(
            address(sharedStrategy), PAPAYA, FEE_RECIPIENT, 10000, // 100%
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
        
        assertEq(factoryWithMaxFee.feeBps(), 10000);
    }

    // ============ Proxy Creation Tests ============
    function testCreateProxySuccessfully() public {
        address proxyAddress = factory.createProxy();
        
        assertNotEq(proxyAddress, address(0));
        assertEq(factory.proxies(address(this)), proxyAddress);
        
        ProxyAccount proxy = ProxyAccount(proxyAddress);
        assertEq(proxy.owner(), address(this));
        assertEq(proxy.strategy(), address(sharedStrategy));
        assertEq(proxy.papaya(), PAPAYA);
        assertEq(proxy.feeRecipient(), FEE_RECIPIENT);
        assertEq(proxy.feeBps(), FEE_BPS);
        assertEq(proxy.usdt(), USDT);
        assertEq(proxy.usdc(), USDC);
        assertEq(proxy.aavePool(), AAVE_POOL);
        assertEq(proxy.aUsdt(), AUSDT);
        assertEq(proxy.aUsdc(), AUSDC);
        assertEq(proxy.uniswapRouter(), UNISWAP_ROUTER);
    }

    function testRevertsWhenUserAlreadyHasProxy() public {
        factory.createProxy();
        
        vm.expectRevert("ProxyFactory: user already has a proxy");
        factory.createProxy();
    }
    
    function testGetProxyReturnsCorrectAddress() public {
        assertEq(factory.getProxy(address(this)), address(0));
        
        address proxyAddress = factory.createProxy();
        
        assertEq(factory.getProxy(address(this)), proxyAddress);
    }

    function testCreateProxyEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit ProxyCreated(address(this), address(0)); // We can't predict the exact address
        
        factory.createProxy();
    }
    
    function testMultipleUsersCanCreateProxies() public {
        address user1 = address(0x100);
        address user2 = address(0x200);
        
        vm.prank(user1);
        address proxy1 = factory.createProxy();
        
        vm.prank(user2);
        address proxy2 = factory.createProxy();
        
        assertNotEq(proxy1, proxy2);
        assertEq(factory.getProxy(user1), proxy1);
        assertEq(factory.getProxy(user2), proxy2);
        
        // Verify ownership and strategy assignment
        ProxyAccount proxyContract1 = ProxyAccount(proxy1);
        ProxyAccount proxyContract2 = ProxyAccount(proxy2);
        
        assertEq(proxyContract1.owner(), user1);
        assertEq(proxyContract2.owner(), user2);
        assertEq(proxyContract1.strategy(), address(sharedStrategy));
        assertEq(proxyContract2.strategy(), address(sharedStrategy));
    }

    function testProxiesShareSameStrategy() public {
        address user1 = address(0x100);
        address user2 = address(0x200);
        address user3 = address(0x300);
        
        vm.prank(user1);
        address proxy1 = factory.createProxy();
        
        vm.prank(user2);
        address proxy2 = factory.createProxy();
        
        vm.prank(user3);
        address proxy3 = factory.createProxy();
        
        // All proxies should reference the same shared strategy
        assertEq(ProxyAccount(proxy1).strategy(), address(sharedStrategy));
        assertEq(ProxyAccount(proxy2).strategy(), address(sharedStrategy));
        assertEq(ProxyAccount(proxy3).strategy(), address(sharedStrategy));
        
        // But they should have different owners
        assertEq(ProxyAccount(proxy1).owner(), user1);
        assertEq(ProxyAccount(proxy2).owner(), user2);
        assertEq(ProxyAccount(proxy3).owner(), user3);
    }

    function testFactoryWithDifferentFeeSettings() public {
        address feeRecipient2 = address(0x999);
        uint256 feeBps2 = 250; // 2.5%
        
        ProxyFactory factory2 = new ProxyFactory(
            address(sharedStrategy), PAPAYA, feeRecipient2, feeBps2,
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
        
        address proxy1 = factory.createProxy(); // 1% fee
        
        vm.prank(address(0x123));
        address proxy2 = factory2.createProxy(); // 2.5% fee
        
        assertEq(ProxyAccount(proxy1).feeBps(), FEE_BPS);
        assertEq(ProxyAccount(proxy1).feeRecipient(), FEE_RECIPIENT);
        
        assertEq(ProxyAccount(proxy2).feeBps(), feeBps2);
        assertEq(ProxyAccount(proxy2).feeRecipient(), feeRecipient2);
        
        // Both should use the same shared strategy
        assertEq(ProxyAccount(proxy1).strategy(), address(sharedStrategy));
        assertEq(ProxyAccount(proxy2).strategy(), address(sharedStrategy));
    }

    // ============ Integration Tests ============
    function testCreatedProxyCanInteractWithSharedStrategy() public {
        MockERC20 mockUSDT = new MockERC20();
        MockERC20 mockUSDC = new MockERC20();
        MockAavePool mockAavePool = new MockAavePool();
        MockUniswapRouter mockUniswapRouter = new MockUniswapRouter();
        
        StrategyExecutor testStrategy = new StrategyExecutor(
            address(mockUSDT),
            address(mockUSDC),
            address(mockAavePool),
            address(mockUniswapRouter)
        );
        
        ProxyFactory testFactory = new ProxyFactory(
            address(testStrategy), PAPAYA, FEE_RECIPIENT, FEE_BPS,
            address(mockUSDT), address(mockUSDC), address(mockAavePool), AUSDT, AUSDC, address(mockUniswapRouter)
        );
        
        address proxyAddress = testFactory.createProxy();
        ProxyAccount proxy = ProxyAccount(proxyAddress);
        
        // Mint some USDT to the proxy
        uint256 testAmount = 1000 * 10**6;
        mockUSDT.mint(proxyAddress, testAmount);
        
        // Approve strategy to spend USDT
        bytes memory approveData = abi.encodeWithSignature(
            "approve(address,uint256)", 
            address(testStrategy), 
            testAmount
        );
        proxy.executeStrategy(address(mockUSDT), approveData);
        
        // Run strategy through proxy
        proxy.runStrategy(address(testStrategy), testAmount);
        
        // Verify USDT was consumed
        assertEq(mockUSDT.balanceOf(proxyAddress), 0);
    }

    // ============ Events ============
    event ProxyCreated(address indexed user, address indexed proxy);
}

// ============ Mock Contracts ============
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
}

contract MockAavePool {
    function deposit(address asset, uint256 amount, address, uint16) external {
        // Mock implementation - just transfer tokens
        MockERC20(asset).transferFrom(msg.sender, address(this), amount);
    }
}

contract MockUniswapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
    
    function exactInputSingle(ExactInputSingleParams calldata params) 
        external 
        payable 
        returns (uint256) 
    {
        // Transfer input tokens from caller
        MockERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        
        // Mint output tokens to recipient (simulate 1:1 swap for simplicity)
        MockERC20(params.tokenOut).mint(params.recipient, params.amountIn);
        
        return params.amountIn;
    }
} 
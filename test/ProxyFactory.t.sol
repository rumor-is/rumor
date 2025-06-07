// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import {ProxyAccount} from "../src/ProxyAccount.sol";
import {StrategyExecutor} from "../src/StrategyExecutor.sol";

/**
 * @title ProxyFactoryTest
 * @dev Test suite for ProxyFactory contract functionality
 */
contract ProxyFactoryTest is Test {
    // ============ Constants ============
    address constant STRATEGY_EXECUTOR = address(0x1);
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
    
    function setUp() public {
        factory = new ProxyFactory(
            STRATEGY_EXECUTOR,
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
        assertEq(factory.strategyExecutor(), STRATEGY_EXECUTOR);
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
            STRATEGY_EXECUTOR, address(0), FEE_RECIPIENT, FEE_BPS,
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testRevertsWhenUsdtIsZero() public {
        vm.expectRevert("ProxyFactory: USDT is zero address");
        new ProxyFactory(
            STRATEGY_EXECUTOR, PAPAYA, FEE_RECIPIENT, FEE_BPS,
            address(0), USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testRevertsWhenFeeBpsExceedsMaximum() public {
        vm.expectRevert("ProxyFactory: fee BPS cannot exceed 100%");
        new ProxyFactory(
            STRATEGY_EXECUTOR, PAPAYA, FEE_RECIPIENT, 10001, // > 100%
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
    }

    function testAllowsZeroFeeRecipient() public {
        ProxyFactory factoryWithZeroFee = new ProxyFactory(
            STRATEGY_EXECUTOR, PAPAYA, address(0), 0,
            USDT, USDC, AAVE_POOL, AUSDT, AUSDC, UNISWAP_ROUTER
        );
        
        assertEq(factoryWithZeroFee.feeRecipient(), address(0));
        assertEq(factoryWithZeroFee.feeBps(), 0);
    }

    // ============ Proxy Creation Tests ============
    function testCreateProxySuccessfully() public {
        address proxyAddress = factory.createProxy();
        
        assertNotEq(proxyAddress, address(0));
        assertEq(factory.proxies(address(this)), proxyAddress);
        
        ProxyAccount proxy = ProxyAccount(proxyAddress);
        assertEq(proxy.owner(), address(this));
        assertEq(proxy.strategy(), STRATEGY_EXECUTOR);
        assertEq(proxy.papaya(), PAPAYA);
        assertEq(proxy.feeRecipient(), FEE_RECIPIENT);
        assertEq(proxy.feeBps(), FEE_BPS);
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
        
        // Verify ownership
        assertEq(ProxyAccount(proxy1).owner(), user1);
        assertEq(ProxyAccount(proxy2).owner(), user2);
    }

    // ============ Events ============
    event ProxyCreated(address indexed user, address indexed proxy);
} 
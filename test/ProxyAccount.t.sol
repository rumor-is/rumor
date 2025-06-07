// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProxyAccount} from "../src/ProxyAccount.sol";
import {StrategyExecutor} from "../src/StrategyExecutor.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ProxyAccountTest
 * @dev Test suite for ProxyAccount contract functionality
 */
contract ProxyAccountTest is Test {
    // ============ Constants ============
    address constant POLYGON_USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant POLYGON_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant POLYGON_AUSDT = 0x6ab707Aca953eDAeFBc4fD23bA73294241490620;
    address constant POLYGON_AUSDC = 0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD;
    address constant POLYGON_AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant POLYGON_UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant PAPAYA = 0x444a597c2DcaDF71187b4c7034D73B8Fa80744E2;
    
    uint256 constant TEST_AMOUNT = 100 * 10**6; // 100 USDT (6 decimals)
    
    // ============ Test Contracts ============
    ProxyAccount public proxy;
    StrategyExecutor public strategy;
    MockERC20 public mockToken;
    MockERC20 public mockUSDT;
    MockERC20 public mockUSDC;
    MockERC20 public mockAUSDT;
    MockERC20 public mockAUSDC;
    MockAavePool public mockAavePool;
    MockUniswapRouter public mockUniswapRouter;

    function setUp() public {
        _deployMockContracts();
        
        proxy = new ProxyAccount(
            address(this),              // owner
            address(0),                 // strategy
            address(0),                 // papaya
            address(0),                 // feeRecipient
            0,                          // feeBps
            address(mockUSDT),          // usdt
            address(mockUSDC),          // usdc
            address(mockAavePool),      // aavePool
            address(mockAUSDT),         // aUsdt
            address(mockAUSDC),         // aUsdc
            address(mockUniswapRouter)  // uniswapRouter
        );
    }

    // ============ Ownership Tests ============
    function testOwnerIsSetCorrectly() public view {
        assertEq(proxy.owner(), address(this));
    }

    function testOnlyOwnerCanTransferToken() public {
        address notOwner = address(0x123);
        
        vm.prank(notOwner);
        vm.expectRevert("ProxyAccount: caller is not the owner");
        proxy.transferToken(address(mockToken), 100);
    }

    function testOnlyOwnerCanExecuteStrategy() public {
        address notOwner = address(0x123);
        
        vm.prank(notOwner);
        vm.expectRevert("ProxyAccount: caller is not the owner");
        proxy.executeStrategy(address(mockToken), "");
    }

    function testOnlyOwnerCanClaim() public {
        address notOwner = address(0x123);
        
        vm.prank(notOwner);
        vm.expectRevert("ProxyAccount: caller is not the owner");
        proxy.claim();
    }

    // ============ Token Transfer Tests ============
    function testTransferToken() public {
        uint256 mintAmount = 1000 * 10**18;
        
        mockToken.mint(address(proxy), mintAmount);
        assertEq(mockToken.balanceOf(address(proxy)), mintAmount);
        
        uint256 initialBalance = mockToken.balanceOf(address(this));
        proxy.transferToken(address(mockToken), mintAmount);
        
        assertEq(mockToken.balanceOf(address(this)), initialBalance + mintAmount);
        assertEq(mockToken.balanceOf(address(proxy)), 0);
    }

    // ============ Strategy Execution Tests ============
    function testExecuteStrategySuccess() public {
        uint256 mintAmount = 1000 * 10**18;
        mockToken.mint(address(proxy), mintAmount);
        
        bytes memory data = abi.encodeWithSignature(
            "transfer(address,uint256)", 
            address(this), 
            mintAmount
        );
        
        proxy.executeStrategy(address(mockToken), data);
        
        assertEq(mockToken.balanceOf(address(this)), mintAmount);
        assertEq(mockToken.balanceOf(address(proxy)), 0);
    }

    function testRevertsWhenStrategyExecutionFails() public {
        bytes memory invalidData = abi.encodeWithSignature("nonExistentFunction()");
        
        vm.expectRevert("ProxyAccount: strategy execution failed");
        proxy.executeStrategy(address(mockToken), invalidData);
    }

    function testRunStrategyWithMockContracts() public {
        strategy = new StrategyExecutor(
            address(proxy),
            address(mockUSDT),
            address(mockUSDC),
            address(mockAavePool),
            address(mockUniswapRouter)
        );
        
        uint256 testAmount = 1000 * 10**6;
        mockUSDT.mint(address(proxy), testAmount);
        
        bytes memory approveData = abi.encodeWithSignature(
            "approve(address,uint256)", 
            address(strategy), 
            testAmount
        );
        proxy.executeStrategy(address(mockUSDT), approveData);
        
        proxy.runStrategy(address(strategy), testAmount);
        
        assertEq(mockUSDT.balanceOf(address(proxy)), 0);
    }

    // ============ Claim Tests ============
    function testClaimWithMockContracts() public {
        uint256 aUsdtAmount = 500 * 10**6;
        uint256 aUsdcAmount = 300 * 10**6;
        
        _setupMockAaveWithdrawals(aUsdtAmount, aUsdcAmount);
        
        mockAUSDT.mint(address(proxy), aUsdtAmount);
        mockAUSDC.mint(address(proxy), aUsdcAmount);
        
        uint256 initialOwnerBalance = mockUSDT.balanceOf(address(this));
        
        proxy.claim();
        
        uint256 expectedTotal = aUsdtAmount + aUsdcAmount;
        assertEq(
            mockUSDT.balanceOf(address(this)), 
            initialOwnerBalance + expectedTotal
        );
        assertEq(mockAUSDT.balanceOf(address(proxy)), 0);
        assertEq(mockAUSDC.balanceOf(address(proxy)), 0);
    }

    // ============ Meta-Transaction Tests ============
    function testMetaTxExecuteStrategy() public {
        vm.createSelectFork("https://polygon-rpc.com");
        require(block.number > 40000000, "Fork not working properly");
        
        uint256 ownerKey = 0x12345;
        ProxyAccount mainnetProxy = _deployMainnetProxy(vm.addr(ownerKey));
        StrategyExecutor mainnetStrategy = _deployMainnetStrategy(address(mainnetProxy));
        
        _setupMainnetProxyWithTokens(mainnetProxy, mainnetStrategy, ownerKey);
        
        uint256 nonceBefore = mainnetProxy.nonce();
        uint256 usdtBefore = IERC20(POLYGON_USDT).balanceOf(address(mainnetProxy));
        
        bytes memory data = abi.encodeWithSignature(
            "runStrategy(address,uint256)", 
            address(mainnetStrategy), 
            TEST_AMOUNT
        );
        uint256 deadline = block.timestamp + 3600;
        
        bytes32 hash = keccak256(abi.encodePacked(
            address(mainnetProxy), 
            data, 
            nonceBefore, 
            deadline
        ));
        bytes32 msgHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32", 
            hash
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, msgHash);
        
        mainnetProxy.executeMetaTx(data, abi.encodePacked(r, s, v), deadline);
        
        assertEq(mainnetProxy.nonce(), nonceBefore + 1);
        assertLt(IERC20(POLYGON_USDT).balanceOf(address(mainnetProxy)), usdtBefore);
        assertGt(IERC20(POLYGON_AUSDT).balanceOf(address(mainnetProxy)), 0);
    }

    // ============ Mainnet Integration Tests ============
    function testMainnetIntegrationStrategy() public {
        vm.createSelectFork("https://polygon-rpc.com");
        require(block.number > 40000000, "Fork not working properly");
        
        ProxyAccount mainnetProxy = _deployMainnetProxy(address(this));
        StrategyExecutor mainnetStrategy = _deployMainnetStrategy(address(mainnetProxy));
        
        _testFullMainnetFlow(mainnetProxy, mainnetStrategy);
    }

    function testMainnetFeeCollection() public {
        vm.createSelectFork("https://polygon-rpc.com");
        require(block.number > 40000000, "Fork not working properly");
        
        address feeRecipient = address(0x7bfc84257b6D818c4e49Eeb7B9422569154EE5a6);
        
        ProxyAccount feeProxy = new ProxyAccount(
            address(this), address(0), PAPAYA, feeRecipient, 100, // 1% fee
            POLYGON_USDT, POLYGON_USDC, POLYGON_AAVE_POOL,
            POLYGON_AUSDT, POLYGON_AUSDC, POLYGON_UNISWAP_ROUTER
        );
        
        StrategyExecutor feeStrategy = new StrategyExecutor(
            address(feeProxy), POLYGON_USDT, POLYGON_USDC,
            POLYGON_AAVE_POOL, POLYGON_UNISWAP_ROUTER
        );
        
        deal(POLYGON_USDT, address(feeProxy), TEST_AMOUNT);
        feeProxy.approveToken(POLYGON_USDT, address(feeStrategy), TEST_AMOUNT);
        
        uint256 feeBefore = IERC20(POLYGON_USDT).balanceOf(feeRecipient);
        
        feeProxy.runStrategy(address(feeStrategy), TEST_AMOUNT);
        
        uint256 feeAfter = IERC20(POLYGON_USDT).balanceOf(feeRecipient);
        uint256 expectedFee = TEST_AMOUNT * 100 / 10000; // 1%
        
        assertEq(feeAfter - feeBefore, expectedFee);
    }

    // ============ Helper Functions ============
    function _deployMockContracts() internal {
        mockToken = new MockERC20();
        mockUSDT = new MockERC20();
        mockUSDC = new MockERC20();
        mockAUSDT = new MockERC20();
        mockAUSDC = new MockERC20();
        mockAavePool = new MockAavePool();
        mockUniswapRouter = new MockUniswapRouter();
    }

    function _setupMockAaveWithdrawals(uint256 aUsdtAmount, uint256 aUsdcAmount) internal {
        mockAavePool.setWithdrawalAmount(address(mockUSDT), aUsdtAmount);
        mockAavePool.setWithdrawalAmount(address(mockUSDC), aUsdcAmount);
        mockAavePool.setATokenMapping(address(mockUSDT), address(mockAUSDT));
        mockAavePool.setATokenMapping(address(mockUSDC), address(mockAUSDC));
    }

    function _deployMainnetProxy(address owner) internal returns (ProxyAccount) {
        return new ProxyAccount(
            owner, address(0), PAPAYA, address(0), 0,
            POLYGON_USDT, POLYGON_USDC, POLYGON_AAVE_POOL,
            POLYGON_AUSDT, POLYGON_AUSDC, POLYGON_UNISWAP_ROUTER
        );
    }

    function _deployMainnetStrategy(address proxyAddr) internal returns (StrategyExecutor) {
        return new StrategyExecutor(
            proxyAddr, POLYGON_USDT, POLYGON_USDC,
            POLYGON_AAVE_POOL, POLYGON_UNISWAP_ROUTER
        );
    }

    function _setupMainnetProxyWithTokens(
        ProxyAccount mainnetProxy, 
        StrategyExecutor mainnetStrategy, 
        uint256 ownerKey
    ) internal {
        deal(POLYGON_USDT, address(mainnetProxy), TEST_AMOUNT);
        vm.prank(vm.addr(ownerKey));
        mainnetProxy.approveToken(POLYGON_USDT, address(mainnetStrategy), TEST_AMOUNT);
    }

    function _testFullMainnetFlow(ProxyAccount mainnetProxy, StrategyExecutor mainnetStrategy) internal {
        // Setup: Approve and deposit to Papaya
        deal(POLYGON_USDT, address(this), TEST_AMOUNT);
        IERC20(POLYGON_USDT).approve(PAPAYA, TEST_AMOUNT);
        
        (bool success, ) = PAPAYA.call(
            abi.encodeWithSignature(
                "depositFor(uint256,address,bool)", 
                TEST_AMOUNT, 
                address(mainnetProxy), 
                false
            )
        );
        require(success, "Failed to deposit to Papaya");

        // Get balance and pull from Papaya
        (bool success1, bytes memory data) = PAPAYA.call(
            abi.encodeWithSignature("users(address)", address(mainnetProxy))
        );
        require(success1, "Failed to get balance");
        (int256 ppBalance, , , ) = abi.decode(data, (int256, int256, int256, uint256));

        mainnetProxy.pullFromPapaya(uint256(ppBalance));
        
        uint256 proxyUsdtBalance = IERC20(POLYGON_USDT).balanceOf(address(mainnetProxy));
        assertGt(proxyUsdtBalance, 0);
        
        // Approve and run strategy
        mainnetProxy.approveToken(POLYGON_USDT, address(mainnetStrategy), proxyUsdtBalance);
        mainnetProxy.runStrategy(address(mainnetStrategy), proxyUsdtBalance);
        
        // Verify strategy results
        assertEq(IERC20(POLYGON_USDT).balanceOf(address(mainnetProxy)), 0);
        assertGt(IERC20(POLYGON_AUSDT).balanceOf(address(mainnetProxy)), 0);
        assertGt(IERC20(POLYGON_AUSDC).balanceOf(address(mainnetProxy)), 0);
        
        // Test claim
        uint256 initialOwnerBalance = IERC20(POLYGON_USDT).balanceOf(address(this));
        mainnetProxy.claim();
        uint256 finalOwnerBalance = IERC20(POLYGON_USDT).balanceOf(address(this));
        
        assertGt(finalOwnerBalance, initialOwnerBalance);
    }
}

// ============ Mock Contracts ============
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
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
    mapping(address => uint256) public withdrawalAmounts;
    mapping(address => address) public underlyingToAToken;
    
    function setWithdrawalAmount(address asset, uint256 amount) external {
        withdrawalAmounts[asset] = amount;
    }
    
    function setATokenMapping(address underlying, address aToken) external {
        underlyingToAToken[underlying] = aToken;
    }
    
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16) external {
        // Mock implementation
    }
    
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        address aToken = underlyingToAToken[asset];
        uint256 withdrawAmount = withdrawalAmounts[asset];
        
        if (withdrawAmount > 0 && aToken != address(0)) {
            MockERC20(aToken).transferFrom(msg.sender, address(this), withdrawAmount);
            MockERC20(asset).mint(to, withdrawAmount);
            return withdrawAmount;
        }
        
        uint256 actualAmount = amount == type(uint256).max ? 100 * 10**6 : amount;
        if (aToken != address(0)) {
            MockERC20(aToken).transferFrom(msg.sender, address(this), actualAmount);
        }
        MockERC20(asset).mint(to, actualAmount);
        return actualAmount;
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
        MockERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        MockERC20(params.tokenOut).mint(params.recipient, params.amountIn);
        return params.amountIn;
    }
} 
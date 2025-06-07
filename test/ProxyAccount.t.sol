// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProxyAccount} from "../src/ProxyAccount.sol";
import {StrategyExecutor} from "../src/StrategyExecutor.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock ERC20 contract for testing
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

// Mock contracts for StrategyExecutor dependencies
contract MockAavePool {
    // Track expected withdrawal amounts for each asset
    mapping(address => uint256) public withdrawalAmounts;
    // Map underlying assets to their corresponding aTokens
    mapping(address => address) public underlyingToAToken;
    
    function setWithdrawalAmount(address asset, uint256 amount) external {
        withdrawalAmounts[asset] = amount;
    }
    
    function setATokenMapping(address underlying, address aToken) external {
        underlyingToAToken[underlying] = aToken;
    }
    
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        // Mock implementation - just accept the call
    }
    
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        // Get the corresponding aToken for this underlying asset
        address aToken = underlyingToAToken[asset];
        
        // Get withdrawal amount
        uint256 withdrawAmount = withdrawalAmounts[asset];
        
        if (withdrawAmount > 0 && aToken != address(0)) {
            // Burn aTokens from the caller (ProxyAccount)
            // In our mock, we'll transfer aTokens from caller to this contract (simulating burn)
            MockERC20(aToken).transferFrom(msg.sender, address(this), withdrawAmount);
            
            // Mint underlying tokens to recipient
            MockERC20(asset).mint(to, withdrawAmount);
            return withdrawAmount;
        }
        
        // Fallback: if no predefined amount, use requested amount
        uint256 actualAmount;
        if (amount == type(uint256).max) {
            actualAmount = 100 * 10**6; // Default fallback
        } else {
            actualAmount = amount;
        }
        
        // If aToken mapping exists, burn aTokens
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

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        // Mock implementation - transfer tokenIn from caller and mint tokenOut to recipient
        MockERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        MockERC20(params.tokenOut).mint(params.recipient, params.amountIn); // 1:1 swap
        return params.amountIn;
    }
}

contract ProxyAccountTest is Test {
    ProxyAccount public proxyAccount;
    MockERC20 public mockToken;
    MockERC20 public mockUSDT;
    MockERC20 public mockUSDC;
    MockERC20 public mockAUSDT;  // Separate aToken contracts
    MockERC20 public mockAUSDC;  // Separate aToken contracts
    MockAavePool public mockAavePool;
    MockUniswapRouter public mockUniswapRouter;
    
    // Mainnet fork variables
    ProxyAccount public mainnetProxyAccount;
    StrategyExecutor public mainnetStrategyExecutor;
    
    // Real Polygon mainnet addresses
    address constant POLYGON_USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address constant POLYGON_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant POLYGON_AUSDT = 0x6ab707Aca953eDAeFBc4fD23bA73294241490620;
    address constant POLYGON_AUSDC = 0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD;
    address constant POLYGON_AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant POLYGON_UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    
    function setUp() public {
        // Create Polygon mainnet fork
        vm.createSelectFork("https://polygon-rpc.com");
        
        // Deploy mock ERC20 tokens
        mockToken = new MockERC20();
        mockUSDT = new MockERC20();
        mockUSDC = new MockERC20();
        mockAUSDT = new MockERC20();  // Separate aUSDT contract
        mockAUSDC = new MockERC20();  // Separate aUSDC contract
        
        // Deploy mock Aave pool and Uniswap router
        mockAavePool = new MockAavePool();
        mockUniswapRouter = new MockUniswapRouter();
        
        // Deploy ProxyAccount with all required constructor parameters
        proxyAccount = new ProxyAccount(
            address(this),              // owner
            address(0),                 // strategy (dummy for mock tests)
            address(0),                 // papaya (dummy for mock tests)
            address(0),                 // feeRecipient (dummy for mock tests)
            0,                          // feeBps (0% for mock tests)
            address(mockUSDT),          // usdt
            address(mockUSDC),          // usdc
            address(mockAavePool),      // aavePool
            address(mockAUSDT),         // aUsdt (separate contract)
            address(mockAUSDC),         // aUsdc (separate contract)
            address(mockUniswapRouter)  // uniswapRouter
        );
        
        // Note: mainnetProxyAccount and mainnetStrategyExecutor will be deployed in testMainnetForkStrategy
    }
    
    function testOwnerIsSetCorrectly() public view {
        // Check if the owner is set to address(this)
        assertEq(proxyAccount.owner(), address(this));
    }
    
    function testTransferToken() public {
        uint256 mintAmount = 1000 * 10**18; // 1000 tokens
        
        // Mint mock ERC20 tokens to the ProxyAccount
        mockToken.mint(address(proxyAccount), mintAmount);
        
        // Verify ProxyAccount received the tokens
        assertEq(mockToken.balanceOf(address(proxyAccount)), mintAmount);
        
        // Get initial balance of test contract
        uint256 initialBalance = mockToken.balanceOf(address(this));
        
        // Call transferToken() from the ProxyAccount to transfer tokens to owner (this test contract)
        proxyAccount.transferToken(address(mockToken), mintAmount);
        
        // Assert that the test contract received the tokens
        assertEq(mockToken.balanceOf(address(this)), initialBalance + mintAmount);
        
        // Assert that ProxyAccount no longer has the tokens
        assertEq(mockToken.balanceOf(address(proxyAccount)), 0);
    }
    
    function testOnlyOwnerCanExecuteStrategy() public {
        // Create a different address to test access control
        address notOwner = address(0x123);
        
        // Try to call executeStrategy from non-owner address
        vm.prank(notOwner);
        vm.expectRevert("ProxyAccount: caller is not the owner");
        proxyAccount.executeStrategy(address(mockToken), "");
    }
    
    function testOnlyOwnerCanTransferToken() public {
        // Create a different address to test access control
        address notOwner = address(0x123);
        
        // Try to call transferToken from non-owner address
        vm.prank(notOwner);
        vm.expectRevert("ProxyAccount: caller is not the owner");
        proxyAccount.transferToken(address(mockToken), 100);
    }
    
    function testExecuteStrategySuccess() public {
        uint256 mintAmount = 1000 * 10**18;
        
        // Mint tokens to ProxyAccount
        mockToken.mint(address(proxyAccount), mintAmount);
        
        // Encode transfer call data
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(this), mintAmount);
        
        // Execute strategy to transfer tokens
        proxyAccount.executeStrategy(address(mockToken), data);
        
        // Verify the strategy execution worked
        assertEq(mockToken.balanceOf(address(this)), mintAmount);
        assertEq(mockToken.balanceOf(address(proxyAccount)), 0);
    }
    
    function testExecuteStrategyFailure() public {
        // Try to execute a strategy that will fail (calling non-existent function)
        bytes memory invalidData = abi.encodeWithSignature("nonExistentFunction()");
        
        // Expect the call to revert
        vm.expectRevert("ProxyAccount: strategy execution failed");
        proxyAccount.executeStrategy(address(mockToken), invalidData);
    }
    
    function testRunStrategy() public {
        // Deploy StrategyExecutor with mock addresses
        StrategyExecutor strategyExecutor = new StrategyExecutor(
            address(proxyAccount),    // proxy
            address(mockUSDT),        // USDT
            address(mockUSDC),        // USDC
            address(mockAavePool),    // Aave pool
            address(mockUniswapRouter) // Uniswap router
        );
        
        uint256 testAmount = 1000 * 10**6; // 1000 USDT (6 decimals)
        
        // Mint USDT tokens to ProxyAccount
        mockUSDT.mint(address(proxyAccount), testAmount);
        
        // Verify ProxyAccount has USDT
        assertEq(mockUSDT.balanceOf(address(proxyAccount)), testAmount);
        
        // Approve the strategy to spend USDT from ProxyAccount
        // We need to do this via executeStrategy since we can't directly approve from ProxyAccount
        bytes memory approveData = abi.encodeWithSignature(
            "approve(address,uint256)", 
            address(strategyExecutor), 
            testAmount
        );
        proxyAccount.executeStrategy(address(mockUSDT), approveData);
        
        // Call runStrategy - this should execute without reverting
        proxyAccount.runStrategy(address(strategyExecutor), testAmount);
        
        // Assert that the function completed successfully (no revert occurred)
        // We can verify this by checking that the USDT balance changed
        assertEq(mockUSDT.balanceOf(address(proxyAccount)), 0, "ProxyAccount should have transferred all USDT");
    }
    
    function testClaim() public {
        uint256 aUsdtAmount = 500 * 10**6;  // 500 aUSDT
        uint256 aUsdcAmount = 300 * 10**6;  // 300 aUSDC
        
        // Configure MockAavePool to return specific amounts for each asset
        mockAavePool.setWithdrawalAmount(address(mockUSDT), aUsdtAmount);
        mockAavePool.setWithdrawalAmount(address(mockUSDC), aUsdcAmount);
        
        // Configure aToken mappings so the pool knows which aTokens to burn
        mockAavePool.setATokenMapping(address(mockUSDT), address(mockAUSDT));
        mockAavePool.setATokenMapping(address(mockUSDC), address(mockAUSDC));
        
        // Mint aTokens to ProxyAccount (using separate contracts)
        mockAUSDT.mint(address(proxyAccount), aUsdtAmount);
        mockAUSDC.mint(address(proxyAccount), aUsdcAmount);
        
        // Get initial owner USDT balance
        uint256 initialOwnerBalance = mockUSDT.balanceOf(address(this));
        
        // Call claim function
        proxyAccount.claim();
        
        // After claim, owner should receive:
        // - aUSDT amount (withdrawn as USDT)
        // - aUSDC amount (withdrawn as USDC, then swapped to USDT 1:1)
        uint256 expectedTotal = aUsdtAmount + aUsdcAmount; // 500 + 300 = 800
        assertEq(mockUSDT.balanceOf(address(this)), initialOwnerBalance + expectedTotal, "Owner should receive all USDT");
        
        // Verify ProxyAccount has no aTokens left (they should be burned during withdrawal)
        assertEq(mockAUSDT.balanceOf(address(proxyAccount)), 0, "ProxyAccount should have no aUSDT left");
        assertEq(mockAUSDC.balanceOf(address(proxyAccount)), 0, "ProxyAccount should have no aUSDC left");
    }
    
    function testOnlyOwnerCanClaim() public {
        // Create a different address to test access control
        address notOwner = address(0x123);
        
        // Try to call claim from non-owner address
        vm.prank(notOwner);
        vm.expectRevert("ProxyAccount: caller is not the owner");
        proxyAccount.claim();
    }
    
    function testMainnetForkStrategy() public {
        // Debug: Check if fork is working
        uint256 blockNumber = block.number;
        console.log("Current block number:", blockNumber);
        require(blockNumber > 40000000, "Fork not working properly"); // Polygon should have high block numbers
        
        // Define test amount
        uint256 testAmount = 100 * 10**6; // 100 USDT (6 decimals)
        
        // Real Papaya contract on Polygon
        address PAPAYA = 0x444a597c2DcaDF71187b4c7034D73B8Fa80744E2;
        
        // Deploy ProxyAccount with real Papaya integration and 1% fee
        ProxyAccount proxy = new ProxyAccount(
            address(this),              // owner
            address(0),                 // strategyExecutor
            PAPAYA,                     // papaya (real contract)
            address(0),               // feeRecipient
            0,                        // feeBps (0% fee)
            POLYGON_USDT,               // usdt
            POLYGON_USDC,               // usdc
            POLYGON_AAVE_POOL,          // aavePool
            POLYGON_AUSDT,              // aUsdt
            POLYGON_AUSDC,              // aUsdc
            POLYGON_UNISWAP_ROUTER      // uniswapRouter
        );

        // Deploy StrategyExecutor
        StrategyExecutor strategyExecutor = new StrategyExecutor(
            address(proxy),           // proxy
            POLYGON_USDT,             // USDT
            POLYGON_USDC,             // USDC
            POLYGON_AAVE_POOL,        // Aave pool
            POLYGON_UNISWAP_ROUTER    // Uniswap router
        );
        
        console.log("ProxyAccount deployed at:", address(proxy));
        console.log("Using real Papaya at:", PAPAYA);
        
        // Setup: Approve the Papaya contract to spend USDT from the test account
        deal(POLYGON_USDT, address(this), testAmount);
        IERC20(POLYGON_USDT).approve(PAPAYA, testAmount);
        
        // Call papaya.depositFor(address(proxy), POLYGON_USDT, testAmount)
        // Using low-level call since we don't have the exact interface imported
        (bool success, ) = PAPAYA.call(
            abi.encodeWithSignature("depositFor(uint256,address,bool)", testAmount, address(proxy), false)
        );
        require(success, "Failed to deposit to Papaya");
        
        console.log("Deposited USDT to Papaya for proxy"); 

        // Get the balance of the proxy in Papaya
        (bool success1, bytes memory data) = PAPAYA.call(
            abi.encodeWithSignature("users(address)", address(proxy))
        );
        require(success1, "Failed to get balance");
        (int256 ppBalance, , , ) = abi.decode(data, (int256, int256, int256, uint256));

        console.log("Step 1: Pulling USDT from Papaya...");
        proxy.pullFromPapaya(uint256(ppBalance));
        
        // Verify ProxyAccount received USDT from Papaya
        uint256 proxyUsdtBalance = IERC20(POLYGON_USDT).balanceOf(address(proxy));
        console.log("ProxyAccount USDT balance after pullFromPapaya:", proxyUsdtBalance);
        assertGt(proxyUsdtBalance, 0, "ProxyAccount should have received USDT from Papaya");
        
        // Approve the StrategyExecutor from the proxy
        console.log("Step 2: Approving StrategyExecutor to spend USDT...");
        proxy.approveToken(POLYGON_USDT, address(strategyExecutor), proxyUsdtBalance);
        
        // Verify allowance was set
        uint256 allowance = IERC20(POLYGON_USDT).allowance(address(proxy), address(strategyExecutor));
        console.log("StrategyExecutor allowance:", allowance);
        assertEq(allowance, proxyUsdtBalance, "StrategyExecutor should have allowance to spend USDT");
              
        // Run the strategy via runStrategy(...)
        console.log("Step 3: Running strategy...");
        proxy.runStrategy(address(strategyExecutor), proxyUsdtBalance);
        
        // Assertions: Proxy should receive aUSDT and aUSDC tokens
        uint256 finalProxyUsdtBalance = IERC20(POLYGON_USDT).balanceOf(address(proxy));
        console.log("ProxyAccount USDT balance after strategy:", finalProxyUsdtBalance);
        assertEq(finalProxyUsdtBalance, 0, "Proxy USDT balance should be 0 after run");
        
        // Proxy should hold aUSDT and aUSDC
        uint256 aUsdtBalance = IERC20(POLYGON_AUSDT).balanceOf(address(proxy));
        uint256 aUsdcBalance = IERC20(POLYGON_AUSDC).balanceOf(address(proxy));
        
        console.log("ProxyAccount aUSDT balance:", aUsdtBalance);
        console.log("ProxyAccount aUSDC balance:", aUsdcBalance);
        
        assertGt(aUsdtBalance, 0, "ProxyAccount should hold aUSDT");
        assertGt(aUsdcBalance, 0, "ProxyAccount should hold aUSDC");
        
        // Optionally check that claim() transfers funds to owner
        console.log("Step 4: Testing claim functionality...");
        uint256 initialOwnerBalance = IERC20(POLYGON_USDT).balanceOf(address(this));
        console.log("Initial owner USDT balance:", initialOwnerBalance);
        
        proxy.claim();
        
        uint256 finalOwnerBalance = IERC20(POLYGON_USDT).balanceOf(address(this));
        console.log("Final owner USDT balance:", finalOwnerBalance);
        assertGt(finalOwnerBalance, initialOwnerBalance, "Owner should have received USDT from claim");
        
        // Log final aToken balances for visual check
        console.log("=== Final Results ===");
        console.log("USDT gained from strategy:", finalOwnerBalance - initialOwnerBalance);
        console.log("Strategy executed successfully with real Papaya integration!");
    }

    function testMainnetForkFees() public {
        // Check fork
        require(block.number > 40000000, "Fork not working properly");
        
        uint256 testAmount = 100 * 10**6; // 100 USDT
        address PAPAYA = 0x444a597c2DcaDF71187b4c7034D73B8Fa80744E2;
        address feeRecipient = 0x7bfc84257b6D818c4e49Eeb7B9422569154EE5a6;
        
        // Deploy ProxyAccount with 1% fee
        ProxyAccount proxy = new ProxyAccount(
            address(this), address(0), PAPAYA, feeRecipient, 100,
            POLYGON_USDT, POLYGON_USDC, POLYGON_AAVE_POOL,
            POLYGON_AUSDT, POLYGON_AUSDC, POLYGON_UNISWAP_ROUTER
        );
        
        // Deploy StrategyExecutor  
        StrategyExecutor strategyExecutor = new StrategyExecutor(
            address(proxy), POLYGON_USDT, POLYGON_USDC,
            POLYGON_AAVE_POOL, POLYGON_UNISWAP_ROUTER
        );
        
        // Setup USDT in proxy (simplified)
        deal(POLYGON_USDT, address(proxy), testAmount);
        proxy.approveToken(POLYGON_USDT, address(strategyExecutor), testAmount);
        
        // Record fee recipient balance
        uint256 feeBefore = IERC20(POLYGON_USDT).balanceOf(feeRecipient);
        console.log("Fee recipient balance before runStrategy:", feeBefore);
        
        // Run strategy
        proxy.runStrategy(address(strategyExecutor), testAmount);
        
        // Check fee was collected
        uint256 feeAfter = IERC20(POLYGON_USDT).balanceOf(feeRecipient);
        console.log("Fee recipient balance after runStrategy:", feeAfter);
        uint256 expectedFee = testAmount * 100 / 10000; // 1%
        
        assertEq(feeAfter - feeBefore, expectedFee, "Fee should be exactly 1%");
        console.log("Fee collected:", feeAfter - feeBefore);
        console.log("Expected fee (1%):", expectedFee);
    }

    function testMetaTxExecuteStrategy() public {
        console.log("=== Meta-Transaction Test ===");
        
        // Fork and deploy
        vm.createSelectFork("https://polygon-rpc.com");
        require(block.number > 40000000, "Fork not working properly");
        
        uint256 ownerKey = 0x12345;
        ProxyAccount proxy = new ProxyAccount(
            vm.addr(ownerKey), address(0), address(0), address(0), 0,
            POLYGON_USDT, POLYGON_USDC, POLYGON_AAVE_POOL,
            POLYGON_AUSDT, POLYGON_AUSDC, POLYGON_UNISWAP_ROUTER
        );
        
        StrategyExecutor strategy = new StrategyExecutor(
            address(proxy), POLYGON_USDT, POLYGON_USDC,
            POLYGON_AAVE_POOL, POLYGON_UNISWAP_ROUTER
        );
        
        console.log("Deployed ProxyAccount:", address(proxy));
        console.log("Deployed StrategyExecutor:", address(strategy));
        
        // Setup
        deal(POLYGON_USDT, address(proxy), 100 * 10**6);
        vm.prank(vm.addr(ownerKey));
        proxy.approveToken(POLYGON_USDT, address(strategy), 100 * 10**6);
        console.log("Setup complete - USDT dealt and approved");
        
        // Record initial state
        uint256 nonceBefore = proxy.nonce();
        uint256 usdtBefore = IERC20(POLYGON_USDT).balanceOf(address(proxy));
        console.log("Initial nonce:", nonceBefore);
        console.log("Initial USDT:", usdtBefore);
        
        // Create and execute meta-transaction
        bytes memory data = abi.encodeWithSignature("runStrategy(address,uint256)", address(strategy), 100 * 10**6);
        uint256 deadline = block.timestamp + 3600; // 1 hour deadline
        bytes32 hash = keccak256(abi.encodePacked(address(proxy), data, nonceBefore, deadline));
        bytes32 msgHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, msgHash);
        console.log("Meta-transaction signed");
        
        proxy.executeMetaTx(data, abi.encodePacked(r, s, v), deadline);
        console.log("Meta-transaction executed!");
        
        // Verify results
        assertEq(proxy.nonce(), nonceBefore + 1, "Nonce should increment");
        assertLt(IERC20(POLYGON_USDT).balanceOf(address(proxy)), usdtBefore, "USDT should decrease");
        assertGt(IERC20(POLYGON_AUSDT).balanceOf(address(proxy)), 0, "Should receive aUSDT");
        
        console.log("Final nonce:", proxy.nonce());
        console.log("Final USDT:", IERC20(POLYGON_USDT).balanceOf(address(proxy)));
        console.log("aUSDT received:", IERC20(POLYGON_AUSDT).balanceOf(address(proxy)));
        console.log("Meta-transaction test successful!");
    }
} 
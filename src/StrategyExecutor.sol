// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LendingStrategy.sol";

// Aave V3 IPool interface
interface IPool {
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;
}

// Uniswap V3 SwapRouter interface
interface ISwapRouter {
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
        returns (uint256 amountOut);
}

/**
 * @title StrategyExecutor
 * @dev A contract that executes a strategy involving USDT/USDC splitting, Aave deposits, and Uniswap swaps
 * Uses Polygon addresses for Aave V3 and Uniswap V3
 */
contract StrategyExecutor is LendingStrategy {
    address public proxy;
    
    // Token addresses (public variables)
    address public usdt;
    address public usdc;
    
    // Protocol contract addresses (public variables)
    address public aavePool;
    address public uniswapRouter;
    
    // Internal contract interfaces
    IERC20 private immutable usdtToken;
    IERC20 private immutable usdcToken;
    IPool private immutable aavePoolContract;
    ISwapRouter private immutable uniswapRouterContract;
    
    // Uniswap V3 fee tier (0.05% = 500)
    uint24 public constant POOL_FEE = 500;

    /**
     * @dev Sets the proxy address and protocol addresses
     * @param _proxy The ProxyAccount contract address
     * @param _usdt The USDT token address (Polygon: 0x3813e82e6f7098b9583FC0F33a962D02018B6803)
     * @param _usdc The USDC token address (Polygon: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174)
     * @param _aavePool The Aave V3 Pool address (Polygon: 0x5345F03E4B7521c5346F3DdB464c898D5C0A2fB0)
     * @param _uniswapRouter The Uniswap V3 SwapRouter address (Polygon: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45)
     */
    constructor(
        address _proxy,
        address _usdt,
        address _usdc,
        address _aavePool,
        address _uniswapRouter
    ) {
        proxy = _proxy;
        usdt = _usdt;
        usdc = _usdc;
        aavePool = _aavePool;
        uniswapRouter = _uniswapRouter;
        
        // Initialize immutable contract interfaces
        usdtToken = IERC20(_usdt);
        usdcToken = IERC20(_usdc);
        aavePoolContract = IPool(_aavePool);
        uniswapRouterContract = ISwapRouter(_uniswapRouter);
    }

    /**
     * @dev Invest amount of token according to strategy
     * @param amount The amount of tokens to invest in the strategy
     */
    function run(uint256 amount) external override {
        execute(amount);
    }

    /**
     * @dev Convert strategy result back into base token (e.g. USDT)
     * Withdraws all positions and converts everything back to the base token
     */
    function claim() external override {
        // TODO: Implement claim logic to withdraw from Aave and convert back to USDT
        // For now, this is a placeholder
    }



    /**
     * @dev Executes the strategy:
     * 1. Transfers USDT from proxy to this contract
     * 2. Splits into two equal parts
     * 3. Deposits half into Aave USDT pool
     * 4. Swaps other half to USDC via Uniswap V3
     * 5. Deposits USDC into Aave USDC pool
     * @param amount The total amount of USDT to process
     */
    function execute(uint256 amount) public {
        // Step 1: Transfer USDT from proxy to this contract
        require(usdtToken.transferFrom(proxy, address(this), amount), "USDT transfer failed");
        
        // Step 2: Split amount into two equal parts
        uint256 halfAmount = amount / 2;
        uint256 remainingAmount = amount - halfAmount; // Handle odd amounts
        
        // Step 3: Approve and deposit half into Aave USDT pool
        usdtToken.approve(aavePool, halfAmount);
        aavePoolContract.deposit(usdt, halfAmount, proxy, 0);
        
        // Step 4: Swap remaining USDT to USDC via Uniswap V3
        usdtToken.approve(uniswapRouter, remainingAmount);
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: usdt,
            tokenOut: usdc,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp + 300, // 5 minutes from now
            amountIn: remainingAmount,
            amountOutMinimum: 0, // Accept any amount of USDC out
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        uint256 usdcReceived = uniswapRouterContract.exactInputSingle(params);
        
        // Step 5: Approve and deposit USDC into Aave USDC pool
        usdcToken.approve(aavePool, usdcReceived);
        aavePoolContract.deposit(usdc, usdcReceived, proxy, 0);
    }
    
    /**
     * @dev Emergency function to recover any tokens stuck in the contract
     * @param token The token address to recover
     * @param amount The amount to recover
     */
    function emergencyWithdraw(address token, uint256 amount) external {
        require(msg.sender == proxy, "Only proxy can call emergency withdraw");
        IERC20(token).transfer(proxy, amount);
    }
} 
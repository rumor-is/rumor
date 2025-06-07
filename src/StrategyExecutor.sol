// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using SafeERC20 for IERC20;
    
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
    
    // Constants for slippage protection (0.5% = 50 basis points)
    uint256 public constant SLIPPAGE_BPS = 50;

    /**
     * @dev Sets the proxy address and protocol addresses
     * @param _proxy The ProxyAccount contract address
     * @param _usdt The USDT token address (Polygon: 0xc2132D05D31c914a87C6611C10748AEb04B58e8F)
     * @param _usdc The USDC token address (Polygon: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359)
     * @param _aavePool The Aave V3 Pool address (Polygon: 0x794a61358D6845594F94dc1DB02A252b5b4814aD)
     * @param _uniswapRouter The Uniswap V3 SwapRouter address (Polygon: 0xE592427A0AEce92De3Edee1F18E0157C05861564)
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
     * @dev Modifier to restrict access to proxy only
     */
    modifier onlyProxy() {
        require(msg.sender == proxy, "StrategyExecutor: caller is not the proxy");
        _;
    }

    /**
     * @dev Invest amount of token according to strategy
     * @param amount The amount of tokens to invest in the strategy
     */
    function run(uint256 amount) external override onlyProxy {
        execute(amount);
    }

    /**
     * @dev Convert strategy result back into base token (e.g. USDT)
     * Withdraws all positions and converts everything back to the base token
     */
    function claim() external override onlyProxy {
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
    function execute(uint256 amount) public onlyProxy {
        // Step 1: Transfer USDT from proxy to this contract
        require(usdtToken.transferFrom(proxy, address(this), amount), "USDT transfer failed");
        
        // Step 2: Split amount into two equal parts
        uint256 halfAmount = amount / 2;
        uint256 remainingAmount = amount - halfAmount; // Handle odd amounts
        
        // Step 3: Approve and deposit half into Aave USDT pool
        usdtToken.forceApprove(aavePool, halfAmount);
        aavePoolContract.deposit(usdt, halfAmount, proxy, 0);
        
        // Step 4: Swap remaining USDT to USDC via Uniswap V3
        usdtToken.forceApprove(uniswapRouter, remainingAmount);
        
        // Calculate minimum amount out with slippage protection (assuming 1:1 ratio with 0.5% slippage)
        uint256 amountOutMinimum = (remainingAmount * (10000 - SLIPPAGE_BPS)) / 10000;
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: usdt,
            tokenOut: usdc,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp + 300, // 5 minutes from now
            amountIn: remainingAmount,
            amountOutMinimum: amountOutMinimum, // 0.5% slippage protection
            sqrtPriceLimitX96: 0 // No price limit
        });
        
        uint256 usdcReceived = uniswapRouterContract.exactInputSingle(params);
        
        // Step 5: Approve and deposit USDC into Aave USDC pool
        usdcToken.forceApprove(aavePool, usdcReceived);
        aavePoolContract.deposit(usdc, usdcReceived, proxy, 0);
    }
    
    /**
     * @dev Emergency function to recover any tokens stuck in the contract
     * @param token The token address to recover
     * @param amount The amount to recover
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyProxy {
        IERC20(token).safeTransfer(proxy, amount);
    }
} 
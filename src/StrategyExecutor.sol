// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./LendingStrategy.sol";

/**
 * @title StrategyExecutor
 * @dev Shared strategy executor for MVP: splits USDT 50/50, deposits half to Aave as USDT,
 *      swaps other half to USDC via Uniswap, then deposits USDC to Aave
 *      Works with any ProxyAccount that calls it
 */
contract StrategyExecutor is LendingStrategy {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint24 public constant POOL_FEE = 500; // 0.05%
    uint256 public constant SLIPPAGE_BPS = 50; // 0.5%
    uint256 public constant DEADLINE_BUFFER = 300; // 5 minutes
    uint16 public constant AAVE_REFERRAL_CODE = 0;

    // ============ Immutable Variables ============
    address public immutable usdt;
    address public immutable usdc;
    address public immutable aavePool;
    address public immutable uniswapRouter;

    // ============ Events ============
    event StrategyExecuted(address indexed proxy, uint256 usdtAmount, uint256 usdcAmount);
    event EmergencyWithdrawal(address indexed proxy, address indexed token, uint256 amount);

    // ============ Constructor ============
    /**
     * @dev Initializes the shared strategy executor with protocol addresses
     * @param _usdt The USDT token address
     * @param _usdc The USDC token address
     * @param _aavePool The Aave V3 Pool address
     * @param _uniswapRouter The Uniswap V3 SwapRouter address
     */
    constructor(
        address _usdt,
        address _usdc,
        address _aavePool,
        address _uniswapRouter
    ) {
        require(_usdt != address(0), "StrategyExecutor: USDT is zero address");
        require(_usdc != address(0), "StrategyExecutor: USDC is zero address");
        require(_aavePool != address(0), "StrategyExecutor: aavePool is zero address");
        require(_uniswapRouter != address(0), "StrategyExecutor: uniswapRouter is zero address");

        usdt = _usdt;
        usdc = _usdc;
        aavePool = _aavePool;
        uniswapRouter = _uniswapRouter;
    }

    // ============ External Functions ============
    /**
     * @dev Executes the lending strategy with the specified amount
     * @param amount The amount of USDT tokens to invest
     * @dev msg.sender must be a ProxyAccount that has approved this contract to spend USDT
     */
    function run(uint256 amount) external override {
        require(amount > 0, "StrategyExecutor: amount must be greater than 0");
        _execute(amount);
    }

    /**
     * @dev Emergency function to recover tokens stuck in the contract
     * @param token The token address to recover
     * @param amount The amount to recover
     */
    function emergencyWithdraw(address token, uint256 amount) external {
        IERC20(token).safeTransfer(msg.sender, amount);
        emit EmergencyWithdrawal(msg.sender, token, amount);
    }

    // ============ Internal Functions ============
    /**
     * @dev Internal function that executes the core strategy logic
     * @param amount The total amount of USDT to process
     */
    function _execute(uint256 amount) internal {
        address proxy = msg.sender; // The calling ProxyAccount
        
        // Cache token interfaces
        IERC20 usdtToken = IERC20(usdt);
        IERC20 usdcToken = IERC20(usdc);

        // Step 1: Transfer USDT from proxy to this contract
        usdtToken.safeTransferFrom(proxy, address(this), amount);

        // Step 2: Split amount into two parts
        uint256 halfAmount = amount / 2;
        uint256 remainingAmount = amount - halfAmount;

        // Step 3: Deposit half to Aave USDT pool
        _depositToAave(usdtToken, halfAmount, usdt, proxy);

        // Step 4: Swap remaining USDT to USDC
        uint256 usdcReceived = _swapTokens(usdtToken, remainingAmount, usdt, usdc);

        // Step 5: Deposit USDC to Aave USDC pool
        _depositToAave(usdcToken, usdcReceived, usdc, proxy);

        emit StrategyExecuted(proxy, halfAmount, usdcReceived);
    }

    /**
     * @dev Deposits tokens to Aave pool
     * @param token The token interface to deposit
     * @param amount The amount to deposit
     * @param asset The asset address for Aave
     * @param onBehalfOf The address to receive the aTokens
     */
    function _depositToAave(IERC20 token, uint256 amount, address asset, address onBehalfOf) internal {
        token.forceApprove(aavePool, amount);
        
        // Use low-level call to handle different Aave interfaces
        (bool success, ) = aavePool.call(
            abi.encodeWithSignature(
                "deposit(address,uint256,address,uint16)",
                asset,
                amount,
                onBehalfOf,
                AAVE_REFERRAL_CODE
            )
        );
        require(success, "StrategyExecutor: Aave deposit failed");
    }

    /**
     * @dev Swaps tokens via Uniswap V3
     * @param tokenIn The input token interface
     * @param amountIn The amount to swap
     * @param tokenInAddress The input token address
     * @param tokenOutAddress The output token address
     * @return amountOut The amount received from the swap
     */
    function _swapTokens(
        IERC20 tokenIn,
        uint256 amountIn,
        address tokenInAddress,
        address tokenOutAddress
    ) internal returns (uint256 amountOut) {
        tokenIn.forceApprove(uniswapRouter, amountIn);

        // Calculate minimum amount out with slippage protection
        uint256 amountOutMinimum = (amountIn * (10000 - SLIPPAGE_BPS)) / 10000;

        // Prepare swap parameters
        bytes memory swapData = abi.encodeWithSignature(
            "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
            tokenInAddress,      // tokenIn
            tokenOutAddress,     // tokenOut
            POOL_FEE,           // fee
            address(this),      // recipient
            block.timestamp + DEADLINE_BUFFER, // deadline
            amountIn,           // amountIn
            amountOutMinimum,   // amountOutMinimum
            uint160(0)          // sqrtPriceLimitX96
        );

        // Execute the swap
        (bool success, bytes memory result) = uniswapRouter.call(swapData);
        require(success, "StrategyExecutor: Uniswap swap failed");
        
        amountOut = abi.decode(result, (uint256));
    }
} 
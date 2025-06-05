// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LendingStrategy.sol";

// Papaya interface
interface IPapaya {
    function withdraw(uint256 amount) external;
    function withdrawTo(address to, uint256 amount) external;
    // Add other functions you need from the real Papaya contract
}

// Aave V3 IPool interface
interface IPool {
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
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
 * @title ProxyAccount
 * @dev A contract that allows the owner to execute strategies and transfer tokens
 */
contract ProxyAccount {
    address public owner;
    address public papaya;
    address public strategy;
    
    // Fee configuration
    address public feeRecipient;
    uint256 public feeBps; // e.g. 200 = 2%
    
    // Investment tracking
    mapping(address => uint256) public totalInvested;
    
    // Protocol contract addresses (public variables)
    address public usdt;
    address public usdc;
    address public aavePool;
    address public aUsdt;
    address public aUsdc;
    address public uniswapRouter;
    
    // Uniswap V3 fee tier (0.05% = 500)
    uint24 public constant POOL_FEE = 500;

    /**
     * @dev Sets the protocol addresses and owner
     * @param _owner The address that will own this ProxyAccount
     * @param _strategy The address of the strategy executor contract
     * @param _papaya The address of the papaya contract
     * @param _feeRecipient The address that will receive fees
     * @param _feeBps The fee in basis points (e.g. 200 = 2%)
     * @param _usdt The USDT token address (Polygon: 0x3813e82e6f7098b9583FC0F33a962D02018B6803)
     * @param _usdc The USDC token address (Polygon: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174)
     * @param _aavePool The Aave V3 Pool address (Polygon: 0x5345F03E4B7521c5346F3DdB464c898D5C0A2fB0)
     * @param _aUsdt The aUSDT token address (Polygon: 0x6ab707Aca953eDAeFBc4fD23bA73294241490620)
     * @param _aUsdc The aUSDC token address (Polygon: 0x625E7708f30cA75bfd92586e17077590C60eb4cD)
     * @param _uniswapRouter The Uniswap V3 SwapRouter address (Polygon: 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45)
     */
    constructor(
        address _owner,
        address _strategy,
        address _papaya,
        address _feeRecipient,
        uint256 _feeBps,
        address _usdt,
        address _usdc,
        address _aavePool,
        address _aUsdt,
        address _aUsdc,
        address _uniswapRouter
    ) {
        owner = _owner;
        strategy = _strategy;
        papaya = _papaya;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
        usdt = _usdt;
        usdc = _usdc;
        aavePool = _aavePool;
        aUsdt = _aUsdt;
        aUsdc = _aUsdc;
        uniswapRouter = _uniswapRouter;
    }

    /**
     * @dev Modifier to restrict access to owner only
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "ProxyAccount: caller is not the owner");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new address
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ProxyAccount: new owner is the zero address");
        owner = newOwner;
    }

    /**
     * @dev Executes a strategy by calling an external contract
     * @param strategyContract The address of the strategy contract to call
     * @param data The calldata to send to the strategy contract
     */
    function executeStrategy(address strategyContract, bytes memory data) public onlyOwner {
        (bool success, ) = strategyContract.call(data);
        require(success, "ProxyAccount: strategy execution failed");
    }

    /**
     * @dev Transfers ERC20 tokens to the owner
     * @param token The address of the ERC20 token contract
     * @param amount The amount of tokens to transfer
     */
    function transferToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner, amount);
    }

    /**
     * @dev Approves ERC20 tokens for spending by another contract
     * @param token The address of the ERC20 token contract
     * @param spender The address of the contract to approve
     * @param amount The amount of tokens to approve
     */
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
        IERC20(token).approve(spender, amount);
    }

    /**
     * @dev Runs a strategy by calling the LendingStrategy interface
     * @param strategyContract The address of the strategy contract to call
     * @param amount The amount parameter to pass to the run function
     */
    function runStrategy(address strategyContract, uint256 amount) external onlyOwner {
        // Calculate fee
        uint256 fee = (amount * feeBps) / 10000;
        uint256 investmentAmount = amount - fee;
        
        // Transfer fee to fee recipient if fee > 0
        if (fee > 0 && feeRecipient != address(0)) {
            IERC20(usdt).transfer(feeRecipient, fee);
        }
        
        // Run strategy with amount minus fee
        LendingStrategy(strategyContract).run(investmentAmount);
        
        // Track investment amount for user
        totalInvested[msg.sender] += investmentAmount;
    }

    /**
     * @dev Runs the default strategy stored in the contract
     * @param amount The amount parameter to pass to the run function
     */
    function runDefaultStrategy(uint256 amount) external onlyOwner {
        // Calculate fee
        uint256 fee = (amount * feeBps) / 10000;
        uint256 investmentAmount = amount - fee;
        
        // Transfer fee to fee recipient if fee > 0
        if (fee > 0 && feeRecipient != address(0)) {
            IERC20(usdt).transfer(feeRecipient, fee);
        }
        
        // Run strategy with amount minus fee
        LendingStrategy(strategy).run(investmentAmount);
        
        // Track investment amount for user
        totalInvested[msg.sender] += investmentAmount;
    }

    /**
     * @dev Claims from a specific strategy contract
     * @param strategyContract The address of the strategy contract to claim from
     */
    function claimFromStrategy(address strategyContract) external onlyOwner {
        LendingStrategy(strategyContract).claim();
    }

    /**
     * @dev Claims from the default strategy stored in the contract
     */
    function claimFromDefaultStrategy() external onlyOwner {
        LendingStrategy(strategy).claim();
    }

    /**
     * @dev Gets expected yield from a strategy
     * @param strategyContract The address of the strategy contract
     * @param amount The amount to calculate yield for
     * @param duration The duration in seconds
     * @return The expected yield amount
     */


    /**
     * @dev Claims all aUSDT and aUSDC from Aave, swaps USDC to USDT, and transfers total USDT to owner
     */
    function claim() external onlyOwner {
        // Step 1: Get balances of aTokens
        uint256 aUsdtBalance = IERC20(aUsdt).balanceOf(address(this));
        uint256 aUsdcBalance = IERC20(aUsdc).balanceOf(address(this));
        
        // Step 2: Withdraw all aUSDT from Aave (amount type(uint256).max means withdraw all)
        if (aUsdtBalance > 0) {
            IERC20(aUsdt).approve(aavePool, aUsdtBalance);
            IPool(aavePool).withdraw(usdt, type(uint256).max, address(this));
        }
        
        // Step 3: Withdraw all aUSDC from Aave
        if (aUsdcBalance > 0) {
            IERC20(aUsdc).approve(aavePool, aUsdcBalance);
            IPool(aavePool).withdraw(usdc, type(uint256).max, address(this));
        }
        
        // Step 4: Get USDC balance after withdrawal
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
        
        // Step 5: Swap all USDC to USDT via Uniswap V3
        if (usdcBalance > 0) {
            IERC20(usdc).approve(uniswapRouter, usdcBalance);
            
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: usdc,
                tokenOut: usdt,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp + 300, // 5 minutes from now
                amountIn: usdcBalance,
                amountOutMinimum: 0, // Accept any amount of USDT out
                sqrtPriceLimitX96: 0 // No price limit
            });
            
            ISwapRouter(uniswapRouter).exactInputSingle(params);
        }
        
        // Step 6: Transfer all USDT to owner
        uint256 totalUsdtBalance = IERC20(usdt).balanceOf(address(this));
        if (totalUsdtBalance > 0) {
            IERC20(usdt).transfer(owner, totalUsdtBalance);
        }
    }

    /**
     * @dev Sets the papaya contract address
     * @param _papaya The address of the papaya contract
     */
    function setPapaya(address _papaya) external onlyOwner {
        papaya = _papaya;
    }

    /**
     * @dev Pulls tokens from the papaya contract
     * @param amount The amount of the token to pull
     */
    function pullFromPapaya(uint256 amount) external onlyOwner {
        require(papaya != address(0), "ProxyAccount: papaya not set");
        IPapaya(papaya).withdraw(amount);
    }
} 
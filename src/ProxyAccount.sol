// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
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
contract ProxyAccount is ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    
    address public owner;
    address public papaya;
    address public strategy;
    
    // Meta-transaction support
    uint256 public nonce;
    bool private _inMetaTx; // Track if we're executing a meta-transaction
    
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
    
    // Constants for slippage protection (0.5% = 50 basis points)
    uint256 public constant SLIPPAGE_BPS = 50;
    
    // Events
    event StrategyExecuted(address indexed strategyContract, uint256 amount, uint256 fee);
    event TokensWithdrawn(address indexed token, uint256 amount, address indexed to);
    event ClaimExecuted(uint256 usdtAmount, uint256 usdcAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MetaTxExecuted(address indexed owner, uint256 nonce, bytes data);

    /**
     * @dev Sets the protocol addresses and owner
     * @param _owner The address that will own this ProxyAccount
     * @param _strategy The address of the strategy executor contract
     * @param _papaya The address of the papaya contract
     * @param _feeRecipient The address that will receive fees
     * @param _feeBps The fee in basis points (e.g. 200 = 2%)
     * @param _usdt The USDT token address (Polygon: 0x3813e82e6f7098b9583FC0F33a962D02018B6803)
     * @param _usdc The USDC token address (Polygon: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174)
     * @param _aavePool The Aave V3 Pool address (Polygon: 0x794a61358D6845594F94dc1DB02A252b5b4814aD)
     * @param _aUsdt The aUSDT token address (Polygon: 0x6ab707Aca953eDAeFBc4fD23bA73294241490620)
     * @param _aUsdc The aUSDC token address (Polygon: 0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD)
     * @param _uniswapRouter The Uniswap V3 SwapRouter address (Polygon: 0xE592427A0AEce92De3Edee1F18E0157C05861564)
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
        require(
            msg.sender == owner || (_inMetaTx && msg.sender == address(this)), 
            "ProxyAccount: caller is not the owner"
        );
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new address
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ProxyAccount: new owner is the zero address");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /**
     * @dev Executes a meta-transaction signed by the owner
     * @param data The calldata to execute
     * @param signature The signature from the owner
     * @param deadline The deadline timestamp for the meta-transaction
     */
    function executeMetaTx(bytes calldata data, bytes calldata signature, uint256 deadline) external {
        require(block.timestamp <= deadline, "ProxyAccount: meta-transaction expired");
        
        bytes32 hash = keccak256(abi.encodePacked(address(this), data, nonce, deadline));
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(hash);
        address signer = ECDSA.recover(messageHash, signature);
        require(signer == owner, "ProxyAccount: invalid signature");
        
        uint256 currentNonce = nonce;
        nonce++;
        
        _inMetaTx = true;
        (bool success, ) = address(this).call(data);
        _inMetaTx = false;
        
        require(success, "ProxyAccount: meta-transaction execution failed");
        
        emit MetaTxExecuted(signer, currentNonce, data);
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
        IERC20(token).safeTransfer(owner, amount);
        emit TokensWithdrawn(token, amount, owner);
    }

    /**
     * @dev Approves ERC20 tokens for spending by another contract
     * @param token The address of the ERC20 token contract
     * @param spender The address of the contract to approve
     * @param amount The amount of tokens to approve
     */
    function approveToken(address token, address spender, uint256 amount) external onlyOwner {
        IERC20(token).forceApprove(spender, amount);
    }

    /**
     * @dev Runs a strategy by calling the LendingStrategy interface
     * @param strategyContract The address of the strategy contract to call
     * @param amount The amount parameter to pass to the run function
     */
    function runStrategy(address strategyContract, uint256 amount) external onlyOwner {
        // Overflow protection for fee calculation
        require(amount > 0, "ProxyAccount: amount must be greater than 0");
        require(feeBps <= 10000, "ProxyAccount: fee BPS cannot exceed 100%");
        
        // Calculate fee with overflow protection
        uint256 fee = (amount * feeBps) / 10000;
        require(fee <= amount, "ProxyAccount: fee calculation overflow");
        
        uint256 investmentAmount = amount - fee;
        
        // Transfer fee to fee recipient if fee > 0
        if (fee > 0 && feeRecipient != address(0)) {
            IERC20(usdt).safeTransfer(feeRecipient, fee);
        }
        
        // Run strategy with amount minus fee
        LendingStrategy(strategyContract).run(investmentAmount);
        
        // Track investment amount for user
        totalInvested[msg.sender] += investmentAmount;
        
        emit StrategyExecuted(strategyContract, investmentAmount, fee);
    }

    /**
     * @dev Runs the default strategy stored in the contract
     * @param amount The amount parameter to pass to the run function
     */
    function runDefaultStrategy(uint256 amount) external onlyOwner {
        // Overflow protection for fee calculation
        require(amount > 0, "ProxyAccount: amount must be greater than 0");
        require(feeBps <= 10000, "ProxyAccount: fee BPS cannot exceed 100%");
        
        // Calculate fee with overflow protection
        uint256 fee = (amount * feeBps) / 10000;
        require(fee <= amount, "ProxyAccount: fee calculation overflow");
        
        uint256 investmentAmount = amount - fee;
        
        // Transfer fee to fee recipient if fee > 0
        if (fee > 0 && feeRecipient != address(0)) {
            IERC20(usdt).safeTransfer(feeRecipient, fee);
        }
        
        // Run strategy with amount minus fee
        LendingStrategy(strategy).run(investmentAmount);
        
        // Track investment amount for user
        totalInvested[msg.sender] += investmentAmount;
        
        emit StrategyExecuted(strategy, investmentAmount, fee);
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
     * @dev Claims all aUSDT and aUSDC from Aave, swaps USDC to USDT, and transfers total USDT to owner
     */
    function claim() external onlyOwner nonReentrant {
        // Step 1: Get balances of aTokens
        uint256 aUsdtBalance = IERC20(aUsdt).balanceOf(address(this));
        uint256 aUsdcBalance = IERC20(aUsdc).balanceOf(address(this));
        
        // Step 2: Withdraw all aUSDT from Aave (amount type(uint256).max means withdraw all)
        if (aUsdtBalance > 0) {
            IERC20(aUsdt).forceApprove(aavePool, aUsdtBalance);
            IPool(aavePool).withdraw(usdt, type(uint256).max, address(this));
        }
        
        // Step 3: Withdraw all aUSDC from Aave
        if (aUsdcBalance > 0) {
            IERC20(aUsdc).forceApprove(aavePool, aUsdcBalance);
            IPool(aavePool).withdraw(usdc, type(uint256).max, address(this));
        }
        
        // Step 4: Get USDC balance after withdrawal
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
        
        // Step 5: Swap all USDC to USDT via Uniswap V3
        if (usdcBalance > 0) {
            IERC20(usdc).forceApprove(uniswapRouter, usdcBalance);
            
            // Calculate minimum amount out with slippage protection (assuming 1:1 ratio with 0.5% slippage)
            uint256 amountOutMinimum = (usdcBalance * (10000 - SLIPPAGE_BPS)) / 10000;
            
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: usdc,
                tokenOut: usdt,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp + 300, // 5 minutes from now
                amountIn: usdcBalance,
                amountOutMinimum: amountOutMinimum, // 0.5% slippage protection
                sqrtPriceLimitX96: 0 // No price limit
            });
            
            ISwapRouter(uniswapRouter).exactInputSingle(params);
        }
        
        // Step 6: Transfer all USDT to owner
        uint256 totalUsdtBalance = IERC20(usdt).balanceOf(address(this));
        if (totalUsdtBalance > 0) {
            IERC20(usdt).safeTransfer(owner, totalUsdtBalance);
        }
        
        emit ClaimExecuted(aUsdtBalance, aUsdcBalance);
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
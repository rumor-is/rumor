// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./LendingStrategy.sol";

// ============ Interfaces ============
interface IPapaya {
    function withdraw(uint256 amount) external;
}

interface IPool {
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

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
 * @dev A contract that allows the owner to execute strategies and manage tokens
 */
contract ProxyAccount is ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint24 public constant POOL_FEE = 500; // 0.05%
    uint256 public constant SLIPPAGE_BPS = 50; // 0.5%
    uint256 public constant MAX_FEE_BPS = 10000; // 100%

    // ============ State Variables ============
    address public owner;
    address public immutable strategy;
    address public immutable papaya;
    address public immutable feeRecipient;
    uint256 public immutable feeBps;

    // Protocol addresses (immutable)
    address public immutable usdt;
    address public immutable usdc;
    address public immutable aavePool;
    address public immutable aUsdt;
    address public immutable aUsdc;
    address public immutable uniswapRouter;

    // Meta-transaction support
    uint256 public nonce;
    bool private _inMetaTx;

    // Investment tracking
    mapping(address => uint256) public totalInvested;

    // ============ Events ============
    event StrategyExecuted(address indexed strategyContract, uint256 amount, uint256 fee);
    event TokensWithdrawn(address indexed token, uint256 amount, address indexed to);
    event ClaimExecuted(uint256 usdtAmount, uint256 usdcAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MetaTxExecuted(address indexed owner, uint256 nonce, bytes data);

    // ============ Modifiers ============
    modifier onlyOwner() {
        require(
            msg.sender == owner || (_inMetaTx && msg.sender == address(this)), 
            "ProxyAccount: caller is not the owner"
        );
        _;
    }

    // ============ Constructor ============
    /**
     * @dev Initializes the ProxyAccount with required addresses and configuration
     * @param _owner The address that will own this ProxyAccount
     * @param _strategy The address of the strategy executor contract
     * @param _papaya The address of the papaya contract
     * @param _feeRecipient The address that will receive fees
     * @param _feeBps The fee in basis points (e.g. 100 = 1%)
     * @param _usdt The USDT token address
     * @param _usdc The USDC token address
     * @param _aavePool The Aave V3 Pool address
     * @param _aUsdt The aUSDT token address
     * @param _aUsdc The aUSDC token address
     * @param _uniswapRouter The Uniswap V3 SwapRouter address
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
        require(_owner != address(0), "ProxyAccount: owner is zero address");
        require(_feeBps <= MAX_FEE_BPS, "ProxyAccount: fee BPS exceeds maximum");

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

    // ============ External Functions ============
    /**
     * @dev Transfers ownership of the contract to a new address
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ProxyAccount: new owner is zero address");
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
    function executeStrategy(address strategyContract, bytes calldata data) external onlyOwner {
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
     * @dev Runs a strategy with the specified amount (unified function)
     * @param strategyContract The address of the strategy contract (use address(0) for default)
     * @param amount The amount parameter to pass to the run function
     */
    function runStrategy(address strategyContract, uint256 amount) external onlyOwner {
        address targetStrategy = strategyContract == address(0) ? strategy : strategyContract;
        require(targetStrategy != address(0), "ProxyAccount: no strategy specified");
        
        uint256 investmentAmount = _processStrategyFee(amount);
        
        LendingStrategy(targetStrategy).run(investmentAmount);
        totalInvested[msg.sender] += investmentAmount;
        
        emit StrategyExecuted(targetStrategy, investmentAmount, amount - investmentAmount);
    }

    /**
     * @dev Claims all aUSDT and aUSDC from Aave, swaps USDC to USDT, and transfers total USDT to owner
     */
    function claim() external onlyOwner nonReentrant {
        // Cache balances
        uint256 aUsdtBalance = IERC20(aUsdt).balanceOf(address(this));
        uint256 aUsdcBalance = IERC20(aUsdc).balanceOf(address(this));
        
        // Withdraw from Aave
        _withdrawFromAave(aUsdt, usdt, aUsdtBalance);
        _withdrawFromAave(aUsdc, usdc, aUsdcBalance);
        
        // Swap USDC to USDT
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
        if (usdcBalance > 0) {
            _swapUsdcToUsdt(usdcBalance);
        }
        
        // Transfer all USDT to owner
        uint256 totalUsdtBalance = IERC20(usdt).balanceOf(address(this));
        if (totalUsdtBalance > 0) {
            IERC20(usdt).safeTransfer(owner, totalUsdtBalance);
        }
        
        emit ClaimExecuted(aUsdtBalance, aUsdcBalance);
    }

    /**
     * @dev Pulls tokens from the papaya contract
     * @param amount The amount of the token to pull
     */
    function pullFromPapaya(uint256 amount) external onlyOwner {
        require(papaya != address(0), "ProxyAccount: papaya not set");
        IPapaya(papaya).withdraw(amount);
    }

    // ============ Internal Functions ============
    /**
     * @dev Processes strategy fee calculation and transfer
     * @param amount The total amount before fee deduction
     * @return investmentAmount The amount after fee deduction
     */
    function _processStrategyFee(uint256 amount) internal returns (uint256 investmentAmount) {
        require(amount > 0, "ProxyAccount: amount must be greater than 0");
        
        // Calculate fee with overflow protection
        uint256 fee = (amount * feeBps) / MAX_FEE_BPS;
        require(fee <= amount, "ProxyAccount: fee calculation overflow");
        
        investmentAmount = amount - fee;
        
        // Transfer fee to recipient if applicable
        if (fee > 0 && feeRecipient != address(0)) {
            IERC20(usdt).safeTransfer(feeRecipient, fee);
        }
    }

    /**
     * @dev Withdraws tokens from Aave pool
     * @param aToken The aToken address
     * @param underlying The underlying token address
     * @param balance The balance to withdraw
     */
    function _withdrawFromAave(address aToken, address underlying, uint256 balance) internal {
        if (balance > 0) {
            IERC20(aToken).forceApprove(aavePool, balance);
            IPool(aavePool).withdraw(underlying, type(uint256).max, address(this));
        }
    }

    /**
     * @dev Swaps USDC to USDT via Uniswap V3
     * @param usdcAmount The amount of USDC to swap
     */
    function _swapUsdcToUsdt(uint256 usdcAmount) internal {
        IERC20(usdc).forceApprove(uniswapRouter, usdcAmount);
        
        // Calculate minimum amount out with slippage protection
        uint256 amountOutMinimum = (usdcAmount * (MAX_FEE_BPS - SLIPPAGE_BPS)) / MAX_FEE_BPS;
        
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: usdc,
            tokenOut: usdt,
            fee: POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: usdcAmount,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });
        
        ISwapRouter(uniswapRouter).exactInputSingle(params);
    }
}
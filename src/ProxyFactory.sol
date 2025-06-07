// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ProxyAccount.sol";

/**
 * @title ProxyFactory
 * @dev Factory contract for creating ProxyAccount instances
 */
contract ProxyFactory {
    // ============ Constants ============
    uint256 public constant MAX_FEE_BPS = 10000; // 100%

    // ============ Immutable Variables ============
    address public immutable strategyExecutor;
    address public immutable papayaContract;
    address public immutable feeRecipient;
    uint256 public immutable feeBps;
    
    // Protocol addresses
    address public immutable usdt;
    address public immutable usdc;
    address public immutable aavePool;
    address public immutable aUsdt;
    address public immutable aUsdc;
    address public immutable uniswapRouter;
    
    // ============ State Variables ============
    mapping(address => address) public proxies;
    
    // ============ Events ============
    event ProxyCreated(address indexed user, address indexed proxy);
    
    // ============ Constructor ============
    /**
     * @dev Initializes the factory with required addresses for ProxyAccount deployment
     * @param _strategyExecutor The address of the StrategyExecutor contract
     * @param _papayaContract The address of the Papaya contract
     * @param _feeRecipient The address that will receive fees
     * @param _feeBps The fee in basis points (e.g. 200 = 2%)
     * @param _usdt The USDT token address
     * @param _usdc The USDC token address
     * @param _aavePool The Aave V3 Pool address
     * @param _aUsdt The aUSDT token address
     * @param _aUsdc The aUSDC token address
     * @param _uniswapRouter The Uniswap V3 SwapRouter address
     */
    constructor(
        address _strategyExecutor,
        address _papayaContract,
        address _feeRecipient,
        uint256 _feeBps,
        address _usdt,
        address _usdc,
        address _aavePool,
        address _aUsdt,
        address _aUsdc,
        address _uniswapRouter
    ) {
        // Validate critical addresses
        require(_strategyExecutor != address(0), "ProxyFactory: strategyExecutor is zero address");
        require(_papayaContract != address(0), "ProxyFactory: papayaContract is zero address");
        require(_usdt != address(0), "ProxyFactory: USDT is zero address");
        require(_usdc != address(0), "ProxyFactory: USDC is zero address");
        require(_aavePool != address(0), "ProxyFactory: aavePool is zero address");
        require(_aUsdt != address(0), "ProxyFactory: aUSDT is zero address");
        require(_aUsdc != address(0), "ProxyFactory: aUSDC is zero address");
        require(_uniswapRouter != address(0), "ProxyFactory: uniswapRouter is zero address");
        
        // Validate fee parameters
        require(_feeBps <= MAX_FEE_BPS, "ProxyFactory: fee BPS cannot exceed 100%");
        // Note: _feeRecipient can be zero address if no fees are intended
        
        strategyExecutor = _strategyExecutor;
        papayaContract = _papayaContract;
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
     * @dev Creates a new ProxyAccount for the caller
     * @return proxyAddress The address of the newly created ProxyAccount
     */
    function createProxy() external returns (address proxyAddress) {
        require(proxies[msg.sender] == address(0), "ProxyFactory: user already has a proxy");
        
        ProxyAccount newProxy = new ProxyAccount(
            msg.sender,         // owner
            strategyExecutor,   // strategy
            papayaContract,     // papaya
            feeRecipient,       // feeRecipient
            feeBps,            // feeBps
            usdt,
            usdc,
            aavePool,
            aUsdt,
            aUsdc,
            uniswapRouter
        );
        
        proxyAddress = address(newProxy);
        proxies[msg.sender] = proxyAddress;
        
        emit ProxyCreated(msg.sender, proxyAddress);
    }

    /**
     * @dev Returns the proxy address for a given user
     * @param user The user address to check
     * @return The proxy address (zero address if none exists)
     */
    function getProxy(address user) external view returns (address) {
        return proxies[user];
    }
} 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ProxyAccount.sol";

/**
 * @title ProxyFactory
 * @dev A factory contract for creating ProxyAccount instances
 */
contract ProxyFactory {
    // Immutable state variables
    address public immutable strategyExecutor;
    address public immutable papayaContract;
    
    // Fee configuration
    address public immutable feeRecipient;
    uint256 public immutable feeBps;
    
    // Protocol addresses (immutable)
    address public immutable usdt;
    address public immutable usdc;
    address public immutable aavePool;
    address public immutable aUsdt;
    address public immutable aUsdc;
    address public immutable uniswapRouter;
    
    // Mapping to track user proxies
    mapping(address => address) public proxies;
    
    // Events
    event ProxyCreated(address indexed user, address proxy);
    
    /**
     * @dev Constructor sets all required addresses for ProxyAccount deployment
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
    
    /**
     * @dev Creates a new ProxyAccount for the caller
     * @return The address of the newly created ProxyAccount
     */
    function createProxy() external returns (address) {
        // Check that user doesn't already have a proxy
        require(proxies[msg.sender] == address(0), "ProxyFactory: user already has a proxy");
        
        // Deploy new ProxyAccount
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
        
        // Store the proxy address in mapping
        proxies[msg.sender] = address(newProxy);
        
        // Emit event
        emit ProxyCreated(msg.sender, address(newProxy));
        
        return address(newProxy);
    }
} 
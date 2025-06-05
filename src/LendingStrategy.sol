// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LendingStrategy
 * @dev Abstract contract defining the interface for lending strategies
 */
abstract contract LendingStrategy {
    
    /**
     * @dev Invest amount of token according to strategy
     * @param amount The amount of tokens to invest in the strategy
     */
    function run(uint256 amount) external virtual;
    
    /**
     * @dev Convert strategy result back into base token (e.g. USDT)
     * Withdraws all positions and converts everything back to the base token
     */
    function claim() external virtual;
    

} 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title LendingStrategy
 * @dev Abstract contract defining the interface for lending strategies
 */
abstract contract LendingStrategy {
    
    /**
     * @dev Executes the lending strategy with the specified amount
     * @param amount The amount of tokens to invest in the strategy
     */
    function run(uint256 amount) external virtual;
} 
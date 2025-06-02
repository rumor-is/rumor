// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ProxyAccount} from "../src/ProxyAccount.sol";

// Mock ERC20 contract for testing
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
}

contract ProxyAccountTest is Test {
    ProxyAccount public proxyAccount;
    MockERC20 public mockToken;
    
    function setUp() public {
        // Deploy ProxyAccount with this test contract as owner
        proxyAccount = new ProxyAccount(address(this));
        
        // Deploy mock ERC20 token
        mockToken = new MockERC20();
    }
    
    function testOwnerIsSetCorrectly() public {
        // Check if the owner is set to address(this)
        assertEq(proxyAccount.owner(), address(this));
    }
    
    function testTransferToken() public {
        uint256 mintAmount = 1000 * 10**18; // 1000 tokens
        
        // Mint mock ERC20 tokens to the ProxyAccount
        mockToken.mint(address(proxyAccount), mintAmount);
        
        // Verify ProxyAccount received the tokens
        assertEq(mockToken.balanceOf(address(proxyAccount)), mintAmount);
        
        // Get initial balance of test contract
        uint256 initialBalance = mockToken.balanceOf(address(this));
        
        // Call transferToken() from the ProxyAccount to transfer tokens to owner (this test contract)
        proxyAccount.transferToken(address(mockToken), mintAmount);
        
        // Assert that the test contract received the tokens
        assertEq(mockToken.balanceOf(address(this)), initialBalance + mintAmount);
        
        // Assert that ProxyAccount no longer has the tokens
        assertEq(mockToken.balanceOf(address(proxyAccount)), 0);
    }
    
    function testOnlyOwnerCanExecuteStrategy() public {
        // Create a different address to test access control
        address notOwner = address(0x123);
        
        // Try to call executeStrategy from non-owner address
        vm.prank(notOwner);
        vm.expectRevert("ProxyAccount: caller is not the owner");
        proxyAccount.executeStrategy(address(mockToken), "");
    }
    
    function testOnlyOwnerCanTransferToken() public {
        // Create a different address to test access control
        address notOwner = address(0x123);
        
        // Try to call transferToken from non-owner address
        vm.prank(notOwner);
        vm.expectRevert("ProxyAccount: caller is not the owner");
        proxyAccount.transferToken(address(mockToken), 100);
    }
    
    function testExecuteStrategySuccess() public {
        uint256 mintAmount = 1000 * 10**18;
        
        // Mint tokens to ProxyAccount
        mockToken.mint(address(proxyAccount), mintAmount);
        
        // Encode transfer call data
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", address(this), mintAmount);
        
        // Execute strategy to transfer tokens
        proxyAccount.executeStrategy(address(mockToken), data);
        
        // Verify the strategy execution worked
        assertEq(mockToken.balanceOf(address(this)), mintAmount);
        assertEq(mockToken.balanceOf(address(proxyAccount)), 0);
    }
    
    function testExecuteStrategyFailure() public {
        // Try to execute a strategy that will fail (calling non-existent function)
        bytes memory invalidData = abi.encodeWithSignature("nonExistentFunction()");
        
        // Expect the call to revert
        vm.expectRevert("ProxyAccount: strategy execution failed");
        proxyAccount.executeStrategy(address(mockToken), invalidData);
    }
} 
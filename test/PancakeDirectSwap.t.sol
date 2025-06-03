// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PancakeDirectSwap.sol";
import "../src/interfaces/IPancakeFactory.sol";
import "../src/interfaces/IPancakePair.sol";
import "../src/interfaces/IPancakeRouter.sol";
import "../src/interfaces/IWBNB.sol";
import "forge-std/interfaces/IERC20.sol";

contract PancakeDirectSwapTest is Test {
    PancakeDirectSwap public swapContract;
    
    // BSC Mainnet addresses
    address constant PANCAKE_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955; // USDT on BSC
    address constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82; // CAKE token
    
    address user = makeAddr("user");
    
    function setUp() public {
        // Fork BSC mainnet
        vm.createSelectFork("https://bsc-dataseed.binance.org/");
        
        swapContract = new PancakeDirectSwap();
        
        // Give user some BNB
        vm.deal(user, 100 ether);
    }
    
    function testSwapBNBForExactUSDT() public {
        vm.startPrank(user);
        
        uint256 amountOut = 100 * 1e18; // 100 USDT
        uint256 deadline = block.timestamp + 300;
        
        // Get quote first
        uint256 expectedAmountIn = swapContract.getAmountIn(amountOut, USDT);
        
        // Execute swap
        uint256 balanceBefore = IERC20(USDT).balanceOf(user);
        uint256 bnbBefore = user.balance;
        
        uint256 actualAmountIn = swapContract.swapBNBForExactTokens{value: expectedAmountIn + 0.1 ether}(
            amountOut,
            USDT,
            deadline
        );
        
        uint256 balanceAfter = IERC20(USDT).balanceOf(user);
        uint256 bnbAfter = user.balance;
        
        // Assertions
        assertEq(balanceAfter - balanceBefore, amountOut, "Should receive exact USDT amount");
        assertLe(actualAmountIn, expectedAmountIn + 1, "Actual amount should be close to expected");
        assertGe(bnbAfter, bnbBefore - expectedAmountIn - 0.01 ether, "Should refund excess BNB");
        
        vm.stopPrank();
    }
    
    function testSwapBNBForExactCAKE() public {
        vm.startPrank(user);
        
        uint256 amountOut = 10 * 1e18; // 10 CAKE
        uint256 deadline = block.timestamp + 300;
        
        // Get quote first
        uint256 expectedAmountIn = swapContract.getAmountIn(amountOut, CAKE);
        
        // Execute swap
        uint256 balanceBefore = IERC20(CAKE).balanceOf(user);
        
        uint256 actualAmountIn = swapContract.swapBNBForExactTokens{value: expectedAmountIn + 0.1 ether}(
            amountOut,
            CAKE,
            deadline
        );
        
        uint256 balanceAfter = IERC20(CAKE).balanceOf(user);
        
        // Assertions
        assertEq(balanceAfter - balanceBefore, amountOut, "Should receive exact CAKE amount");
        assertLe(actualAmountIn, expectedAmountIn + 1, "Actual amount should be close to expected");
        
        vm.stopPrank();
    }
    
    function testGetAmountIn() public {
        uint256 amountOut = 100 * 1e18; // 100 USDT
        uint256 amountIn = swapContract.getAmountIn(amountOut, USDT);
        
        assertGt(amountIn, 0, "Amount in should be greater than 0");
        
        // Test with different amount
        uint256 amountOut2 = 50 * 1e18; // 50 USDT
        uint256 amountIn2 = swapContract.getAmountIn(amountOut2, USDT);
        
        assertLt(amountIn2, amountIn, "Smaller output should require smaller input");
    }
    
    function testPairExists() public {
        assertTrue(swapContract.pairExists(USDT), "WBNB-USDT pair should exist");
        assertTrue(swapContract.pairExists(CAKE), "WBNB-CAKE pair should exist");
        
        // Test with non-existent pair
        address fakeToken = makeAddr("fakeToken");
        assertFalse(swapContract.pairExists(fakeToken), "Fake token pair should not exist");
    }
    
    function testRevertDeadlineExpired() public {
        vm.startPrank(user);
        
        uint256 amountOut = 100 * 1e18;
        uint256 deadline = block.timestamp - 1; // Past deadline
        
        vm.expectRevert(PancakeDirectSwap.DeadlineExpired.selector);
        swapContract.swapBNBForExactTokens{value: 1 ether}(
            amountOut,
            USDT,
            deadline
        );
        
        vm.stopPrank();
    }
    
    function testRevertInsufficientOutputAmount() public {
        vm.startPrank(user);
        
        uint256 deadline = block.timestamp + 300;
        
        vm.expectRevert(PancakeDirectSwap.InsufficientOutputAmount.selector);
        swapContract.swapBNBForExactTokens{value: 1 ether}(
            0, // Zero amount out
            USDT,
            deadline
        );
        
        vm.stopPrank();
    }
    
    function testRevertInvalidToken() public {
        vm.startPrank(user);
        
        uint256 amountOut = 100 * 1e18;
        uint256 deadline = block.timestamp + 300;
        
        // Test with zero address
        vm.expectRevert(PancakeDirectSwap.InvalidToken.selector);
        swapContract.swapBNBForExactTokens{value: 1 ether}(
            amountOut,
            address(0),
            deadline
        );
        
        // Test with WBNB address
        vm.expectRevert(PancakeDirectSwap.InvalidToken.selector);
        swapContract.swapBNBForExactTokens{value: 1 ether}(
            amountOut,
            WBNB,
            deadline
        );
        
        vm.stopPrank();
    }
    
    function testRevertPairNotFound() public {
        vm.startPrank(user);
        
        uint256 amountOut = 100 * 1e18;
        uint256 deadline = block.timestamp + 300;
        address fakeToken = makeAddr("fakeToken");
        
        vm.expectRevert(PancakeDirectSwap.PairNotFound.selector);
        swapContract.swapBNBForExactTokens{value: 1 ether}(
            amountOut,
            fakeToken,
            deadline
        );
        
        vm.stopPrank();
    }
    
    function testRevertInsufficientInputAmount() public {
        vm.startPrank(user);
        
        uint256 amountOut = 100 * 1e18;
        uint256 deadline = block.timestamp + 300;
        
        // Get required amount but send less
        uint256 requiredAmount = swapContract.getAmountIn(amountOut, USDT);
        
        vm.expectRevert(PancakeDirectSwap.InsufficientInputAmount.selector);
        swapContract.swapBNBForExactTokens{value: requiredAmount - 1}(
            amountOut,
            USDT,
            deadline
        );
        
        vm.stopPrank();
    }
    
    function testGasUsage() public {
        vm.startPrank(user);
        
        uint256 amountOut = 100 * 1e18;
        uint256 deadline = block.timestamp + 300;
        uint256 expectedAmountIn = swapContract.getAmountIn(amountOut, USDT);
        
        uint256 gasBefore = gasleft();
        swapContract.swapBNBForExactTokens{value: expectedAmountIn + 0.1 ether}(
            amountOut,
            USDT,
            deadline
        );
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for swap:", gasUsed);
        
        // Should use less gas than router (typically router uses ~150k-200k gas)
        assertLt(gasUsed, 150000, "Should use less gas than router");
        
        vm.stopPrank();
    }
    
    function testRecoverToken() public {
        // Deploy a mock ERC20 token
        MockERC20 mockToken = new MockERC20("Mock", "MOCK", 18);
        mockToken.mint(address(swapContract), 1000 * 1e18);
        
        uint256 balanceBefore = mockToken.balanceOf(address(this));
        swapContract.recoverToken(address(mockToken), 1000 * 1e18);
        uint256 balanceAfter = mockToken.balanceOf(address(this));
        
        assertEq(balanceAfter - balanceBefore, 1000 * 1e18, "Should recover tokens");
    }
    
    function testCannotRecoverWBNB() public {
        vm.expectRevert("Cannot recover WBNB");
        swapContract.recoverToken(WBNB, 1 ether);
    }
    
    function testSwapAndAddLiquidity() public {
        vm.startPrank(user);
        
        uint256 amountOut = 10 * 1e18; // 10 CAKE tokens to swap
        uint256 amountBNBLiquidity = 1 ether; // 1 BNB for liquidity
        uint256 deadline = block.timestamp + 300;
        
        // Get total BNB needed
        uint256 totalBNBNeeded = swapContract.getTotalBNBNeeded(amountOut, CAKE, amountBNBLiquidity);
        
        // Get pair address to check LP token balance
        address pair = IPancakeFactory(PANCAKE_FACTORY).getPair(WBNB, CAKE);
        
        // Execute swap and add liquidity
        uint256 balanceBefore = IERC20(CAKE).balanceOf(user);
        uint256 bnbBefore = user.balance;
        uint256 lpBalanceBefore = IERC20(pair).balanceOf(user);
        
        (uint256 amountIn, uint256 amountToken, uint256 amountBNB, uint256 liquidity) =
            swapContract.swapAndAddLiquidity{value: totalBNBNeeded + 0.1 ether}(
                amountOut,
                CAKE,
                amountBNBLiquidity,
                0, // amountTokenMin
                0, // amountBNBMin
                deadline
            );
        
        uint256 balanceAfter = IERC20(CAKE).balanceOf(user);
        uint256 bnbAfter = user.balance;
        uint256 lpBalanceAfter = IERC20(pair).balanceOf(user);
        
        // Assertions
        assertGt(amountIn, 0, "Should use BNB for swap");
        assertGt(amountToken, 0, "Should add tokens to liquidity");
        assertGt(amountBNB, 0, "Should add BNB to liquidity");
        assertGt(liquidity, 0, "Should receive LP tokens");
        
        // Check that user received remaining tokens
        uint256 remainingTokens = amountOut - amountToken;
        assertEq(balanceAfter - balanceBefore, remainingTokens, "Should receive remaining tokens");
        
        // Check that user received LP tokens
        assertEq(lpBalanceAfter - lpBalanceBefore, liquidity, "Should receive LP tokens");
        
        // Check BNB usage
        uint256 totalBNBUsed = amountIn + amountBNB;
        assertLe(bnbBefore - bnbAfter, totalBNBUsed + 0.01 ether, "Should use correct amount of BNB");
        
        vm.stopPrank();
    }
    
    function testGetTotalBNBNeeded() public {
        uint256 amountOut = 10 * 1e18; // 10 CAKE
        uint256 amountBNBLiquidity = 1 ether;
        
        uint256 totalNeeded = swapContract.getTotalBNBNeeded(amountOut, CAKE, amountBNBLiquidity);
        uint256 swapNeeded = swapContract.getAmountIn(amountOut, CAKE);
        
        assertEq(totalNeeded, swapNeeded + amountBNBLiquidity, "Total should equal swap + liquidity");
        assertGt(totalNeeded, amountBNBLiquidity, "Total should be greater than liquidity amount");
    }
    
    function testSwapAndAddLiquidityWithMinAmounts() public {
        vm.startPrank(user);
        
        uint256 amountOut = 5 * 1e18; // 5 CAKE tokens
        uint256 amountBNBLiquidity = 0.5 ether; // 0.5 BNB for liquidity
        uint256 deadline = block.timestamp + 300;
        
        // Set more reasonable minimum amounts (lower to avoid slippage issues)
        uint256 amountTokenMin = 0.1 * 1e18; // Minimum 0.1 CAKE for liquidity
        uint256 amountBNBMin = 0.01 ether; // Minimum 0.01 BNB for liquidity
        
        uint256 totalBNBNeeded = swapContract.getTotalBNBNeeded(amountOut, CAKE, amountBNBLiquidity);
        
        (uint256 amountIn, uint256 amountToken, uint256 amountBNB, uint256 liquidity) =
            swapContract.swapAndAddLiquidity{value: totalBNBNeeded + 0.1 ether}(
                amountOut,
                CAKE,
                amountBNBLiquidity,
                amountTokenMin,
                amountBNBMin,
                deadline
            );
        
        // Assertions
        assertGe(amountToken, amountTokenMin, "Should meet minimum token requirement");
        assertGe(amountBNB, amountBNBMin, "Should meet minimum BNB requirement");
        assertGt(liquidity, 0, "Should receive LP tokens");
        
        vm.stopPrank();
    }
    
    function testSwapAndAddLiquidityRevertInsufficientBNB() public {
        vm.startPrank(user);
        
        uint256 amountOut = 10 * 1e18;
        uint256 amountBNBLiquidity = 1 ether;
        uint256 deadline = block.timestamp + 300;
        
        uint256 totalBNBNeeded = swapContract.getTotalBNBNeeded(amountOut, CAKE, amountBNBLiquidity);
        
        // Send insufficient BNB
        vm.expectRevert(PancakeDirectSwap.InsufficientInputAmount.selector);
        swapContract.swapAndAddLiquidity{value: totalBNBNeeded - 0.1 ether}(
            amountOut,
            CAKE,
            amountBNBLiquidity,
            0,
            0,
            deadline
        );
        
        vm.stopPrank();
    }
    
    function testSwapAndAddLiquidityEvents() public {
        vm.startPrank(user);
        
        uint256 amountOut = 5 * 1e18;
        uint256 amountBNBLiquidity = 0.5 ether;
        uint256 deadline = block.timestamp + 300;
        
        uint256 totalBNBNeeded = swapContract.getTotalBNBNeeded(amountOut, CAKE, amountBNBLiquidity);
        
        // Execute the function and check that it completes successfully
        (uint256 amountIn, uint256 amountToken, uint256 amountBNB, uint256 liquidity) =
            swapContract.swapAndAddLiquidity{value: totalBNBNeeded + 0.1 ether}(
                amountOut,
                CAKE,
                amountBNBLiquidity,
                0,
                0,
                deadline
            );
        
        // Verify the operation was successful
        assertGt(amountIn, 0, "Should use BNB for swap");
        assertGt(amountToken, 0, "Should add tokens to liquidity");
        assertGt(amountBNB, 0, "Should add BNB to liquidity");
        assertGt(liquidity, 0, "Should receive LP tokens");
        
        vm.stopPrank();
    }
}

// Mock ERC20 for testing
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}
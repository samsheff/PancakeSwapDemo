// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IPancakeFactory.sol";
import "./interfaces/IPancakePair.sol";
import "./interfaces/IPancakeRouter.sol";
import "./interfaces/IWBNB.sol";
import "../lib/forge-std/src/interfaces/IERC20.sol";

/**
 * @title PancakeDirectSwap
 * @dev Direct interaction with PancakeSwap V2 Factory and Pairs for efficient BNB to token swaps
 * @notice This contract bypasses the PancakeSwap router for gas optimization
 */
contract PancakeDirectSwap {
    // BSC Mainnet addresses
    address private constant PANCAKE_FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address private constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    
    // Events
    event SwapExecuted(
        address indexed user,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    event LiquidityAdded(
        address indexed user,
        address indexed token,
        uint256 amountToken,
        uint256 amountBNB,
        uint256 liquidity
    );
    
    // Custom errors
    error DeadlineExpired();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error PairNotFound();
    error TransferFailed();
    error InvalidToken();
    
    // Reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    constructor() {
        _status = _NOT_ENTERED;
    }
    
    /**
     * @dev Swap BNB for exact amount of tokens using direct pair interaction
     * @param amountOut The exact amount of tokens to receive
     * @param tokenOut The address of the token to receive
     * @param deadline The deadline for the transaction
     * @return amountIn The amount of BNB used for the swap
     */
    function swapBNBForExactTokens(
        uint256 amountOut,
        address tokenOut,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountIn) {
        // Validate inputs
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (tokenOut == address(0) || tokenOut == WBNB) revert InvalidToken();
        
        // Get pair address
        address pair = _getPair(WBNB, tokenOut);
        if (pair == address(0)) revert PairNotFound();
        
        // Get reserves and calculate required input
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, WBNB, tokenOut);
        amountIn = _getAmountIn(amountOut, reserveIn, reserveOut);
        
        // Check if enough BNB was sent
        if (msg.value < amountIn) revert InsufficientInputAmount();
        
        // Wrap BNB to WBNB
        IWBNB(WBNB).deposit{value: amountIn}();
        
        // Transfer WBNB to pair
        if (!IWBNB(WBNB).transfer(pair, amountIn)) revert TransferFailed();
        
        // Execute swap
        _swap(pair, WBNB, tokenOut, amountOut, msg.sender);
        
        // Refund excess BNB
        if (msg.value > amountIn) {
            (bool success, ) = msg.sender.call{value: msg.value - amountIn}("");
            if (!success) revert TransferFailed();
        }
        
        emit SwapExecuted(msg.sender, tokenOut, amountIn, amountOut);
    }
    
    /**
     * @dev Swap BNB for tokens and add liquidity back to the pool
     * @param amountOut The exact amount of tokens to receive from swap
     * @param tokenOut The address of the token to receive
     * @param amountBNBLiquidity The amount of BNB to use for adding liquidity
     * @param amountTokenMin Minimum amount of tokens to add to liquidity
     * @param amountBNBMin Minimum amount of BNB to add to liquidity
     * @param deadline The deadline for the transaction
     * @return amountIn The amount of BNB used for the swap
     * @return amountToken Amount of tokens added to liquidity
     * @return amountBNB Amount of BNB added to liquidity
     * @return liquidity Amount of LP tokens received
     */
    function swapAndAddLiquidity(
        uint256 amountOut,
        address tokenOut,
        uint256 amountBNBLiquidity,
        uint256 amountTokenMin,
        uint256 amountBNBMin,
        uint256 deadline
    ) external payable nonReentrant returns (
        uint256 amountIn,
        uint256 amountToken,
        uint256 amountBNB,
        uint256 liquidity
    ) {
        // Validate inputs
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (tokenOut == address(0) || tokenOut == WBNB) revert InvalidToken();
        if (amountBNBLiquidity == 0) revert InsufficientInputAmount();
        
        // Execute swap first
        amountIn = _executeSwapForLiquidity(tokenOut, amountOut, amountBNBLiquidity);
        
        // Add liquidity
        (amountToken, amountBNB, liquidity) = _addLiquidityAfterSwap(
            tokenOut,
            amountOut,
            amountBNBLiquidity,
            amountTokenMin,
            amountBNBMin,
            deadline
        );
        
        // Handle refunds and transfers
        _handleRefundsAndTransfers(tokenOut, amountOut, amountToken, amountIn, amountBNB);
        
        emit SwapExecuted(msg.sender, tokenOut, amountIn, amountOut);
        emit LiquidityAdded(msg.sender, tokenOut, amountToken, amountBNB, liquidity);
    }
    
    /**
     * @dev Internal function to execute swap for liquidity operation
     */
    function _executeSwapForLiquidity(
        address tokenOut,
        uint256 amountOut,
        uint256 amountBNBLiquidity
    ) private returns (uint256 amountIn) {
        address pair = _getPair(WBNB, tokenOut);
        if (pair == address(0)) revert PairNotFound();
        
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, WBNB, tokenOut);
        amountIn = _getAmountIn(amountOut, reserveIn, reserveOut);
        
        if (msg.value < amountIn + amountBNBLiquidity) revert InsufficientInputAmount();
        
        IWBNB(WBNB).deposit{value: amountIn}();
        if (!IWBNB(WBNB).transfer(pair, amountIn)) revert TransferFailed();
        _swap(pair, WBNB, tokenOut, amountOut, address(this));
    }
    
    /**
     * @dev Internal function to add liquidity after swap
     */
    function _addLiquidityAfterSwap(
        address tokenOut,
        uint256 amountOut,
        uint256 amountBNBLiquidity,
        uint256 amountTokenMin,
        uint256 amountBNBMin,
        uint256 deadline
    ) private returns (uint256 amountToken, uint256 amountBNB, uint256 liquidity) {
        IERC20(tokenOut).approve(PANCAKE_ROUTER, amountOut);
        
        (amountToken, amountBNB, liquidity) = IPancakeRouter(PANCAKE_ROUTER).addLiquidityETH{
            value: amountBNBLiquidity
        }(
            tokenOut,
            amountOut,
            amountTokenMin,
            amountBNBMin,
            msg.sender,
            deadline
        );
    }
    
    /**
     * @dev Internal function to handle refunds and transfers
     */
    function _handleRefundsAndTransfers(
        address tokenOut,
        uint256 amountOut,
        uint256 amountToken,
        uint256 amountIn,
        uint256 amountBNB
    ) private {
        // Transfer remaining tokens to user
        if (amountOut > amountToken) {
            if (!IERC20(tokenOut).transfer(msg.sender, amountOut - amountToken)) revert TransferFailed();
        }
        
        // Refund excess BNB
        uint256 totalUsed = amountIn + amountBNB;
        if (msg.value > totalUsed) {
            (bool success, ) = msg.sender.call{value: msg.value - totalUsed}("");
            if (!success) revert TransferFailed();
        }
    }
    
    /**
     * @dev Get pair address from factory
     */
    function _getPair(address tokenA, address tokenB) private view returns (address) {
        return IPancakeFactory(PANCAKE_FACTORY).getPair(tokenA, tokenB);
    }
    
    /**
     * @dev Get reserves for a pair in the correct order
     */
    function _getReserves(
        address pair,
        address tokenA,
        address tokenB
    ) private view returns (uint256 reserveA, uint256 reserveB) {
        (uint256 reserve0, uint256 reserve1, ) = IPancakePair(pair).getReserves();
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }
    
    /**
     * @dev Calculate required input amount using constant product formula
     * @param amountOut Desired output amount
     * @param reserveIn Input token reserve
     * @param reserveOut Output token reserve
     * @return amountIn Required input amount
     */
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) private pure returns (uint256 amountIn) {
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientInputAmount();
        
        // Calculate with 0.3% fee (997/1000)
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }
    
    /**
     * @dev Execute swap on pair contract
     */
    function _swap(
        address pair,
        address tokenIn,
        address /* tokenOut */,
        uint256 amountOut,
        address to
    ) private {
        address token0 = IPancakePair(pair).token0();
        (uint256 amount0Out, uint256 amount1Out) = tokenIn == token0 
            ? (uint256(0), amountOut) 
            : (amountOut, uint256(0));
            
        IPancakePair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
    }
    
    /**
     * @dev Get quote for BNB to token swap
     * @param amountOut Desired output amount
     * @param tokenOut Token to receive
     * @return amountIn Required BNB input
     */
    function getAmountIn(
        uint256 amountOut,
        address tokenOut
    ) external view returns (uint256 amountIn) {
        if (tokenOut == address(0) || tokenOut == WBNB) revert InvalidToken();
        
        address pair = _getPair(WBNB, tokenOut);
        if (pair == address(0)) revert PairNotFound();
        
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, WBNB, tokenOut);
        amountIn = _getAmountIn(amountOut, reserveIn, reserveOut);
    }
    
    /**
     * @dev Get total BNB needed for swap and liquidity operations
     * @param amountOut Desired token output from swap
     * @param tokenOut Token to receive
     * @param amountBNBLiquidity BNB amount for liquidity
     * @return totalBNBNeeded Total BNB required for both operations
     */
    function getTotalBNBNeeded(
        uint256 amountOut,
        address tokenOut,
        uint256 amountBNBLiquidity
    ) external view returns (uint256 totalBNBNeeded) {
        if (tokenOut == address(0) || tokenOut == WBNB) revert InvalidToken();
        
        address pair = _getPair(WBNB, tokenOut);
        if (pair == address(0)) revert PairNotFound();
        
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pair, WBNB, tokenOut);
        uint256 swapBNBNeeded = _getAmountIn(amountOut, reserveIn, reserveOut);
        
        totalBNBNeeded = swapBNBNeeded + amountBNBLiquidity;
    }
    
    /**
     * @dev Check if a pair exists for WBNB and token
     */
    function pairExists(address token) external view returns (bool) {
        return _getPair(WBNB, token) != address(0);
    }
    
    /**
     * @dev Emergency function to recover stuck tokens (only for tokens sent by mistake)
     */
    function recoverToken(address token, uint256 amount) external {
        require(token != WBNB, "Cannot recover WBNB");
        IERC20(token).transfer(msg.sender, amount);
    }
    
    // Receive function to accept BNB
    receive() external payable {}
}
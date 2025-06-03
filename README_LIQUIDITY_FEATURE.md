# PancakeDirectSwap Liquidity Feature

## Overview

The PancakeDirectSwap contract now includes functionality to swap BNB for tokens and automatically add liquidity back to the PancakeSwap pool in a single transaction. This feature combines the efficiency of direct pair interaction for swapping with the convenience of the PancakeSwap Router for liquidity operations.

## New Functionality

### `swapAndAddLiquidity` Function

This function performs two operations in sequence:
1. **Swap**: Exchanges BNB for a specified amount of tokens using direct pair interaction
2. **Add Liquidity**: Adds the purchased tokens and additional BNB to the liquidity pool

#### Parameters

- `amountOut`: The exact amount of tokens to receive from the swap
- `tokenOut`: The address of the token to receive
- `amountBNBLiquidity`: The amount of BNB to use for adding liquidity
- `amountTokenMin`: Minimum amount of tokens to add to liquidity (slippage protection)
- `amountBNBMin`: Minimum amount of BNB to add to liquidity (slippage protection)
- `deadline`: The deadline for the transaction

#### Returns

- `amountIn`: The amount of BNB used for the swap
- `amountToken`: Amount of tokens added to liquidity
- `amountBNB`: Amount of BNB added to liquidity
- `liquidity`: Amount of LP tokens received

### `getTotalBNBNeeded` Function

A helper function to calculate the total BNB required for both swap and liquidity operations.

#### Parameters

- `amountOut`: Desired token output from swap
- `tokenOut`: Token to receive
- `amountBNBLiquidity`: BNB amount for liquidity

#### Returns

- `totalBNBNeeded`: Total BNB required for both operations

## Usage Example

```solidity
// Calculate total BNB needed
uint256 totalBNB = swapContract.getTotalBNBNeeded(
    10 * 1e18,  // 10 tokens
    tokenAddress,
    1 ether     // 1 BNB for liquidity
);

// Execute swap and add liquidity
(uint256 amountIn, uint256 amountToken, uint256 amountBNB, uint256 liquidity) = 
    swapContract.swapAndAddLiquidity{value: totalBNB + 0.1 ether}(
        10 * 1e18,      // amountOut
        tokenAddress,   // tokenOut
        1 ether,        // amountBNBLiquidity
        0,              // amountTokenMin (0 for no slippage protection)
        0,              // amountBNBMin (0 for no slippage protection)
        block.timestamp + 300  // deadline
    );
```

## Key Features

### Gas Efficiency
- Uses direct pair interaction for swapping (more gas efficient than router)
- Uses PancakeSwap Router for liquidity operations (handles complex LP token math)

### Automatic Refunds
- Refunds excess BNB sent to the contract
- Transfers any remaining tokens not used in liquidity to the user

### Slippage Protection
- Supports minimum amount parameters for both tokens and BNB
- Prevents sandwich attacks and excessive slippage

### Event Emission
- Emits `SwapExecuted` event for the swap operation
- Emits `LiquidityAdded` event for the liquidity operation

## Technical Implementation

### Internal Functions

1. **`_executeSwapForLiquidity`**: Handles the swap operation
2. **`_addLiquidityAfterSwap`**: Handles the liquidity addition
3. **`_handleRefundsAndTransfers`**: Manages refunds and remaining token transfers

### Security Features

- Reentrancy protection using OpenZeppelin's pattern
- Input validation for all parameters
- Deadline checks to prevent stale transactions
- Proper error handling with custom errors

## Integration with Existing Features

The new liquidity functionality is fully compatible with existing contract features:
- All existing swap functions remain unchanged
- Same security model and error handling
- Compatible with existing deployment and testing infrastructure

## Testing

Comprehensive test suite includes:
- Basic swap and add liquidity functionality
- Slippage protection testing
- Error condition testing
- Gas usage verification
- Event emission verification

Run tests with:
```bash
forge test --match-test testSwapAndAddLiquidity -vv
```

## Contract Addresses

- **PancakeSwap Factory**: `0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73`
- **PancakeSwap Router**: `0x10ED43C718714eb63d5aA57B78B54704E256024E`
- **WBNB**: `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`

## Benefits

1. **Single Transaction**: Combines swap and liquidity addition in one transaction
2. **Gas Savings**: Uses efficient direct pair interaction for swapping
3. **Convenience**: Automatically handles token approvals and transfers
4. **Flexibility**: Supports slippage protection and deadline management
5. **Safety**: Includes comprehensive error handling and refund mechanisms
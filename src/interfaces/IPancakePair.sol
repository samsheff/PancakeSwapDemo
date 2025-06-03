// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPancakePair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function transfer(address to, uint value) external returns (bool);
    function balanceOf(address owner) external view returns (uint);
}
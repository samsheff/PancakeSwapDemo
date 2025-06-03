// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IWBNB {
    function deposit() external payable;
    function withdraw(uint wad) external;
    function transfer(address to, uint value) external returns (bool);
    function balanceOf(address owner) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
}
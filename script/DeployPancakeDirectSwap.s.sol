// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PancakeDirectSwap.sol";

contract DeployPancakeDirectSwap is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        PancakeDirectSwap swapContract = new PancakeDirectSwap();
        
        console.log("PancakeDirectSwap deployed at:", address(swapContract));
        
        vm.stopBroadcast();
    }
}
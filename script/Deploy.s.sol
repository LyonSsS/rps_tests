// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {RockPaperScissors} from "../src/RockPaperScissors.sol";

contract DeployScript is Script {
    function run() external returns (RockPaperScissors) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying RockPaperScissors...");
        RockPaperScissors rps = new RockPaperScissors();

        console.log("RockPaperScissors deployed at:", address(rps));

        vm.stopBroadcast();
        return rps;
    }
}


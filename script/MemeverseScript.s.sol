// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./BaseScript.s.sol";
import "../src/verse/Memeverse.sol";
import "../src/verse/ReserveFundManager.sol";

contract MemeverseScript is BaseScript {
    function run() public broadcaster {
        address owner = vm.envAddress("OWNER");
        address gasManager = vm.envAddress("GAS_MANAGER");
        address orETH = vm.envAddress("ORETH");
        address osETH = vm.envAddress("OSETH");
        address orUSD = vm.envAddress("ORUSD");
        address osUSD = vm.envAddress("OSUSD");
        address factory = vm.envAddress("OUTSWAP_FACTORY");
        address router = vm.envAddress("OUTSWAP_ROUTER");
        address orETHStakeManager = vm.envAddress("ORETH_STAKE_MANAGER");
        address orUSDStakeManager = vm.envAddress("ORUSD_STAKE_MANAGER");
        
        address memeverse = address(new Memeverse(
            owner,
            gasManager,
            orETH,
            osETH,
            orUSD,
            osUSD,
            orETHStakeManager,
            orUSDStakeManager,
            factory,
            router
        ));
        console.log("Memeverse deployed on %s", memeverse);

        address reserveFundManager = address(new ReserveFundManager(owner, gasManager, osETH, osUSD, memeverse));
        console.log("ReserveFundManager deployed on %s", reserveFundManager);
    }
}

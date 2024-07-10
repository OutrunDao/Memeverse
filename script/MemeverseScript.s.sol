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
        
        Memeverse memeverse = new Memeverse(
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
        );
        address memeverseAddr = address(memeverse);
        console.log("Memeverse deployed on %s", memeverseAddr);

        address reserveFundManager = address(new ReserveFundManager(owner, gasManager, osETH, osUSD, memeverseAddr));
        console.log("ReserveFundManager deployed on %s", reserveFundManager);

        uint256 genesisFee = 0.01 ether;
        uint256 reserveFundRatio = 2000;
        uint256 permanentLockRatio = 5000;
        uint256 maxEarlyUnlockRatio = 70;
        uint256 minEthFund = 8 ether;
        uint256 minUsdbFund = 30000 ether;
        uint128 minDurationDays = 1;
        uint128 maxDurationDays = 7;
        uint128 minLockupDays = 90;
        uint128 maxLockupDays = 3650;
        uint128 minfundBasedAmount = 1;
        uint128 maxfundBasedAmount = 1000000;
        memeverse.initialize(
            reserveFundManager, 
            genesisFee, 
            reserveFundRatio, 
            permanentLockRatio, 
            maxEarlyUnlockRatio, 
            minEthFund, 
            minUsdbFund, 
            minDurationDays, 
            maxDurationDays, 
            minLockupDays, 
            maxLockupDays, 
            minfundBasedAmount, 
            maxfundBasedAmount
        );
    }
}

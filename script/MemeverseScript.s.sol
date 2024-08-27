// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./BaseScript.s.sol";
import "../src/verse/Memeverse.sol";
import "../src/verse/ReserveFundManager.sol";

contract MemeverseScript is BaseScript {
    function run() public broadcaster {
        address owner = vm.envAddress("OWNER");
        address revenuePool = vm.envAddress("REVENUPOOL");
        address factory = vm.envAddress("OUTSWAP_FACTORY");
        address router = vm.envAddress("OUTSWAP_ROUTER");
        
        Memeverse memeverse = new Memeverse(
            "Memeverse",
            "MVS",
            owner,
            revenuePool,
            factory,
            router
        );
        address memeverseAddr = address(memeverse);
        console.log("Memeverse deployed on %s", memeverseAddr);

        address reserveFundManager = address(new ReserveFundManager(owner, memeverseAddr));
        console.log("ReserveFundManager deployed on %s", reserveFundManager);

        uint256 genesisFee = 0.1 ether;
        uint256 reserveFundRatio = 2000;
        uint256 permanentLockRatio = 5000;
        uint256 maxEarlyUnlockRatio = 70;
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
            minDurationDays, 
            maxDurationDays, 
            minLockupDays, 
            maxLockupDays, 
            minfundBasedAmount, 
            maxfundBasedAmount
        );
    }
}

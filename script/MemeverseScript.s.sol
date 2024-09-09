// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./BaseScript.s.sol";
import "../src/verse/Memeverse.sol";
import "../src/verse/ReserveFundManager.sol";

contract MemeverseScript is BaseScript {
    function run() public broadcaster {
        address UBNB = vm.envAddress("UBNB");
        address owner = vm.envAddress("OWNER");
        address revenuePool = vm.envAddress("REVENUPOOL");
        address factory = vm.envAddress("OUTRUN_AMM_FACTORY");
        address router = vm.envAddress("OUTRUN_AMM_ROUTER");
        
        Memeverse UBNBMemeverse = new Memeverse(
            "UBNBMemeverse",
            "MVS-UBNB",
            UBNB,
            owner,
            revenuePool,
            factory,
            router
        );
        address UBNBMemeverseAddr = address(UBNBMemeverse);
        console.log("UBNBMemeverse deployed on %s", UBNBMemeverseAddr);

        address UBNBReserveFundManager = address(new ReserveFundManager(owner, UBNBMemeverseAddr, UBNB));
        console.log("UBNBReserveFundManager deployed on %s", UBNBReserveFundManager);

        uint256 genesisFee = 0.1 ether;
        uint256 reserveFundRatio = 2000;
        uint256 permanentLockRatio = 5000;
        uint256 maxEarlyUnlockRatio = 70;
        uint256 minTotalFund = 20 * 10**18;
        uint128 minDurationDays = 1;
        uint128 maxDurationDays = 7;
        uint128 minLockupDays = 90;
        uint128 maxLockupDays = 1825;
        uint128 minfundBasedAmount = 1;
        uint128 maxfundBasedAmount = 1000000;

        UBNBMemeverse.initialize(
            UBNBReserveFundManager,
            genesisFee, 
            reserveFundRatio, 
            permanentLockRatio, 
            maxEarlyUnlockRatio, 
            minTotalFund,
            minDurationDays, 
            maxDurationDays, 
            minLockupDays, 
            maxLockupDays, 
            minfundBasedAmount, 
            maxfundBasedAmount
        );
    }
}

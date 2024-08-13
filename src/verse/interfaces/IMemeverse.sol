// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title Memeverse interface
 */
interface IMemeverse {
    struct LaunchPool {
        address token;                  // Token address
        address liquidProof;            // Liquidity proof token address
        string name;                    // Token name
        string symbol;                  // Token symbol
        string description;             // Token description;
        uint256 totalFund;              // Funds(osETH|osUSD) actually added to the memeverse
        uint128 endTime;                // EndTime of launchPool
        uint128 maxDeposit;             // The maximum amount of funds that can be deposited each time
        uint256 lockupDays;             // LockupDay of liquidity
        uint256 fundBasedAmount;        // Token amount based fund
        bool ethOrUsdb;                 // Type of deposited funds, true --> usdb, false --> eth
    }


    function launchPools(uint256 poolId) external view returns (LaunchPool memory);

    function tempFunds(uint256 poolId) external view returns (uint256);

    function tempFundPool(uint256 poolId, address account) external view returns (uint256);


    function initialize(
        address _reserveFundManager,
        uint256 _reserveFundRatio,
        uint256 _permanentLockRatio,
        uint256 _maxEarlyUnlockRatio,
        uint256 _minEthFund,
        uint256 _minUsdbFund,
        uint256 _genesisFee,
        uint128 _minDurationDays,
        uint128 _maxDurationDays,
        uint128 _minLockupDays,
        uint128 _maxLockupDays,
        uint128 _minfundBasedAmount,
        uint128 _maxfundBasedAmount
    ) external;

    function depositToTempFundPool(uint256 poolId, uint256 usdbValue) external payable;

    function claimTokenOrFund(uint256 poolId) external;

    function enablePoolTokenTransfer(uint256 poolId) external;

    function claimPoolLiquidity(uint256 poolId, uint256 burnedLiquidity) external returns (uint256 claimedLiquidity);

    function claimTransactionFees(uint256 poolId) external;

    function registerMemeverse(
        string calldata name,
        string calldata symbol,
        string calldata description,
        uint128 maxDeposit,
        uint128 durationDays,
        uint128 lockupDays,
        uint128 fundBasedAmount,
        uint256 maxSupply,
        bool ethOrUsdb
    ) external payable returns (uint256 poolId);

    function setGenesisFee(uint256 _genesisFee) external;

    function setReserveFundRatio(uint256 _reserveFundRatio) external;

    function setPermanentLockRatio(uint256 _permanentLockRatio) external;

    function setMaxEarlyUnlockRatio(uint256 _earlyUnlockRatio) external;
        
    function setMinEthFund(uint256 _minEthFund) external;

    function setMinUsdbFund(uint256 _minUsdbFund) external;

    function setDurationDaysRange(uint128 _minDurationDays, uint128 _maxDurationDays) external;

    function setLockupDaysRange(uint128 _minLockupDays, uint128 _maxLockupDays) external;

    function setFundBasedAmountRange(uint128 _minfundBasedAmount, uint128 _maxfundBasedAmount) external;


    event ClaimToken(uint256 indexed poolId, address indexed msgSender, uint256 fund, uint256 baseAmount, uint256 deployAmount, uint256 proofAmount);

    event ClaimPoolLiquidity(uint256 indexed poolId, address account, uint256 lpAmount);

    event ClaimTransactionFees(uint256 indexed poolId, address indexed owner, address token, uint256 amount0, uint256 amount1);

    event RegisterMemeverse(uint256 indexed poolId, address indexed owner, address token);
}

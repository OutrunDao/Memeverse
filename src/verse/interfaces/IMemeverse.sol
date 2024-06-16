// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMemeverse {
    struct LaunchPool {
        address owner;                  // LaunchPool owner
        address token;                  // Token address
        string name;                    // Token name
        string symbol;                  // Token symbol
        uint128 totalLiquidityFund;     // Funds(osETH|osUSD) actually added to the liquidity pool
        uint128 totalLiquidityLP;       // Total liquidity of LP
        uint64 startTime;               // StartTime of launchPool
        uint64 endTime;                 // EndTime of launchPool
        uint128 maxDeposit;             // The maximum amount of funds that can be deposited each time
        uint128 claimDeadline;          // Token claim deadline
        uint128 lockupDays;             // LockupDay of liquidity
        uint256 tokenBaseAmount;        // Token amount based fund
        bool ethOrUsdb;                 // Type of deposited funds, true --> usdb, false --> eth
    }

    function launchPool(uint256 poolId) external view returns (LaunchPool memory);

    function poolIds(address token) external view returns (uint256);

    function tempFunds(uint256 poolId) external view returns (uint256);

    function tempFundPool(uint256 poolId, address account) external view returns (uint256);

    function poolFunds(uint256 poolId, address account) external view returns (uint256);

    function isPoolLiquidityClaimed(uint256 poolId, address account) external view returns (bool);

    function getPoolByToken(address token) external view returns (LaunchPool memory);


    function initialize(
        uint256 _minEthLiquidity,
        uint256 _minUsdbLiquidity,
        uint256 _minDurationDays,
        uint256 _maxDurationDays,
        uint256 _minLockupDays,
        uint256 _maxLockupDays
    ) external;

    function depositToTempFundPool(uint256 poolId, uint256 usdbValue) external payable;

    function claimTokenOrFund(uint256 poolId) external;

    function enablePoolTokenTransfer(uint256 poolId) external;

    function claimPoolLiquidity(uint256 poolId) external;

    function claimTransactionFees(uint256 poolId) external;

    function registerMemeverse(
        string calldata name,
        string calldata symbol,
        uint64 startTime,
        uint128 durationDays,
        uint128 maxDeposit,
        uint128 lockupDays,
        uint256 tokenBaseAmount,
        uint256 maxSupply,
        bool ethOrUsdb
    ) external returns (uint256 poolId);

    function setAttributes(uint256 poolId, string[] calldata names, bytes[] calldata datas) external;

    function setMinEthLiquidity(uint256 _minEthLiquidity) external;

    function setMinUsdbLiquidity(uint256 _minUsdbLiquidity) external;

    function setMinDurationDays(uint256 _minDurationDays) external;

    function setMaxDurationDays(uint256 _maxDurationDays) external;

    function setMinLockupDays(uint256 _minLockupDays) external;

    function setMaxLockupDays(uint256 _maxLockupDays) external;


    event ClaimPoolLiquidity(uint256 indexed poolId, address account, uint256 lpAmount);

    event ClaimTransactionFees(uint256 indexed poolId, address indexed owner, address token, uint256 amount0, uint256 amount1);

    event RegisterMemeverse(uint256 indexed poolId, address indexed owner, address token);
}
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title Memeverse interface
 */
interface IMemeverse {
    struct LaunchPool {
        address owner;                  // LaunchPool owner
        address token;                  // Token address
        address liquidityERC20;         // LiquidityERC20 address
        string name;                    // Token name
        string symbol;                  // Token symbol
        string description;             // Token description;
        uint256 totalLiquidityFund;     // Funds(osETH|osUSD) actually added to the liquidity pool
        uint128 endTime;                // EndTime of launchPool
        uint128 maxDeposit;             // The maximum amount of funds that can be deposited each time
        uint256 lockupDays;             // LockupDay of liquidity
        uint256 tokenBaseAmount;        // Token amount based fund
        bool ethOrUsdb;                 // Type of deposited funds, true --> usdb, false --> eth
    }

    function launchPools(uint256 poolId) external view returns (LaunchPool memory);

    function poolIds(address token) external view returns (uint256);

    function tempFunds(uint256 poolId) external view returns (uint256);

    function tempFundPool(uint256 poolId, address account) external view returns (uint256);

    function getPoolByToken(address token) external view returns (LaunchPool memory);


    function initialize(
        address _reserveFundManager,
        uint256 _reserveFundRatio,
        uint256 _permanentLockRatio,
        uint256 _earlyUnlockRatio,
        uint256 _minEthLiquidity,
        uint256 _minUsdbLiquidity,
        uint256 _minDurationDays,
        uint256 _maxDurationDays,
        uint256 _minLockupDays,
        uint256 _maxLockupDays,
        uint256 _ethLiquidityThreshold,
        uint256 _usdbLiquidityThreshold,
        uint256 _genesisFee
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
        uint256 durationDays,
        uint128 maxDeposit,
        uint256 lockupDays,
        uint48 tokenBaseAmount,
        uint256 maxSupply,
        bool ethOrUsdb
    ) external payable returns (uint256 poolId);

    function setAttributes(uint256 poolId, string[] calldata names, bytes[] calldata datas) external;

    function setReserveFundRatio(uint256 _reserveFundRatio) external;

    function setPermanentLockRatio(uint256 _permanentLockRatio) external;

    function setMaxEarlyUnlockRatio(uint256 _earlyUnlockRatio) external;

    function setMinEthLiquidity(uint256 _minEthLiquidity) external;

    function setMinUsdbLiquidity(uint256 _minUsdbLiquidity) external;

    function setMinDurationDays(uint256 _minDurationDays) external;

    function setMaxDurationDays(uint256 _maxDurationDays) external;

    function setMinLockupDays(uint256 _minLockupDays) external;

    function setMaxLockupDays(uint256 _maxLockupDays) external;

    function setEthLiquidityThreshold(uint256 _ethLiquidityThreshold) external;

    function setUsdbLiquidityThreshold(uint256 _usdbLiquidityThreshold) external;

    function setGenesisFee(uint256 _genesisFee) external;


    event ClaimPoolLiquidity(uint256 indexed poolId, address account, uint256 lpAmount);

    event ClaimTransactionFees(uint256 indexed poolId, address indexed owner, address token, uint256 amount0, uint256 amount1);

    event RegisterMemeverse(uint256 indexed poolId, address indexed owner, address token);
}
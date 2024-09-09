// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

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
        uint256 totalFund;              // Funds(UPT) actually added to the memeverse
        uint256 endTime;                // EndTime of launchPool
        uint256 lockupDays;             // LockupDays of liquidity
        uint256 fundBasedAmount;        // Token amount based fund
    }

    function initialize(
        address reserveFundManager,
        uint256 genesisFee,
        uint256 reserveFundRatio,
        uint256 permanentLockRatio,
        uint256 maxEarlyUnlockRatio,
        uint256 minTotalFund,
        uint128 minDurationDays,
        uint128 maxDurationDays,
        uint128 minLockupDays,
        uint128 maxLockupDays,
        uint128 minfundBasedAmount,
        uint128 maxfundBasedAmount
    ) external;

    function deposit(uint256 poolId, uint256 amountInUPT) external;

    function enablePoolTokenTransfer(uint256 poolId) external;

    function redeemLiquidity(uint256 poolId, uint256 liquidity) external returns (uint256 claimedLiquidity);

    function claimTradeFees(uint256 poolId) external;

    function registerMemeverse(
        string calldata _name,
        string calldata _symbol,
        string calldata description,
        uint256 durationDays,
        uint256 lockupDays,
        uint256 fundBasedAmount
    ) external payable returns (uint256 poolId);

    function setRevenuePool(address revenuePool) external;

    function setGenesisFee(uint256 genesisFee) external;

    function setReserveFundRatio(uint256 reserveFundRatio) external;

    function setPermanentLockRatio(uint256 permanentLockRatio) external;

    function setMaxEarlyUnlockRatio(uint256 earlyUnlockRatio) external;

    function setMinTotalFund(uint256 _minTotalFund) external;

    function setDurationDaysRange(uint128 minDurationDays, uint128 maxDurationDays) external;

    function setLockupDaysRange(uint128 minLockupDays, uint128 maxLockupDays) external;

    function setFundBasedAmountRange(uint128 minfundBasedAmount, uint128 maxfundBasedAmount) external;

    error RatioOverflow();

    error PermissionDenied();

    error SymbolDuplication();

    error InvalidRegisterInfo();

    error NotDepositStage(uint256 endTime);

    error NotLiquidityLockStage(uint256 endTime);

    error InsufficientGenesisFee(uint256 genesisFee);

    error InsufficientTotalFund(uint256 minTotalFund);


    event Deposit(
        uint256 indexed poolId, 
        address indexed msgSender, 
        uint256 amountInUPT, 
        uint256 baseAmount, 
        uint256 deployAmount, 
        uint256 proofAmount
    );

    event RedeemLiquidity(uint256 indexed poolId, address account, uint256 liquidity);

    event ClaimTradeFees(
        uint256 indexed poolId, 
        address indexed owner, 
        address token0, 
        uint256 amount0, 
        address token1, 
        uint256 amount1
    );

    event RegisterMemeverse(uint256 indexed poolId, address indexed owner, address token);
}

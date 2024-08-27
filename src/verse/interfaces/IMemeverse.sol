// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title Memeverse interface
 */
interface IMemeverse {
    struct FundType {
        uint256 minTotalFund;           // Minimum total fund
        uint256 minFundDeposit;         // Minimum fund deposit
        address fundToken;              // Fund token address
        address outStakeManager;        // Outstake manager address
    }

    struct LaunchPool {
        address token;                  // Token address
        address liquidProof;            // Liquidity proof token address
        string name;                    // Token name
        string symbol;                  // Token symbol
        string description;             // Token description;
        uint256 totalFund;              // Funds(PT) actually added to the memeverse
        uint256 endTime;                // EndTime of launchPool
        uint256 lockupDays;             // LockupDays of liquidity
        uint256 fundBasedAmount;        // Token amount based fund
        uint256 fundTypeId;             // Type of deposited funds
    }

    function launchPools(uint256 poolId) external view returns (LaunchPool memory);

    function fundTypes(uint256 typeId) external view returns (FundType memory);

    function initialize(
        address _reserveFundManager,
        uint256 genesisFee,
        uint256 reserveFundRatio,
        uint256 permanentLockRatio,
        uint256 maxEarlyUnlockRatio,
        uint128 minDurationDays,
        uint128 maxDurationDays,
        uint128 minLockupDays,
        uint128 maxLockupDays,
        uint128 minfundBasedAmount,
        uint128 maxfundBasedAmount
    ) external;

    function deposit(uint256 poolId, uint256 amountInNativeYieldToken) external;

    function enablePoolTokenTransfer(uint256 poolId) external;

    function claimPoolLiquidity(uint256 poolId, uint256 burnedLiquidity) external returns (uint256 claimedLiquidity);

    function claimTransactionFees(uint256 poolId) external;

    function registerMemeverse(
        string calldata _name,
        string calldata _symbol,
        string calldata description,
        uint256 durationDays,
        uint256 lockupDays,
        uint256 fundBasedAmount,
        uint256 mintLimit,
        uint256 fundTypeId
    ) external payable returns (uint256 poolId);

    function setRevenuePool(address revenuePool) external;

    function setGenesisFee(uint256 genesisFee) external;

    function setReserveFundRatio(uint256 reserveFundRatio) external;

    function setPermanentLockRatio(uint256 permanentLockRatio) external;

    function setMaxEarlyUnlockRatio(uint256 earlyUnlockRatio) external;

    function setDurationDaysRange(uint128 minDurationDays, uint128 maxDurationDays) external;

    function setLockupDaysRange(uint128 minLockupDays, uint128 maxLockupDays) external;

    function setFundBasedAmountRange(uint128 minfundBasedAmount, uint128 maxfundBasedAmount) external;

    function setFundType(
        uint256 typeId, 
        uint256 minTotalFund, 
        uint256 minFundDeposit, 
        address fundToken, 
        address outStakeManager
    ) external;


    event Deposit(
        uint256 indexed poolId, 
        address indexed msgSender, 
        uint256 amountInPT, 
        uint256 baseAmount, 
        uint256 deployAmount, 
        uint256 proofAmount
    );

    event ClaimPoolLiquidity(uint256 indexed poolId, address account, uint256 lpAmount);

    event ClaimTransactionFees(
        uint256 indexed poolId, 
        address indexed owner, 
        address token, 
        address token0, 
        uint256 amount0, 
        address token1, 
        uint256 amount1
    );

    event RegisterMemeverse(uint256 indexed poolId, address indexed owner, address token);
}

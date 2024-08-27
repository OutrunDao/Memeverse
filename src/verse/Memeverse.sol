// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

import "./interfaces/IMemeverse.sol";
import "./interfaces/IReserveFundManager.sol";
import "../external/IERC20.sol";
import "../external/IOutrunAMMPair.sol";
import "../external/IOutrunAMMRouter.sol";
import "../external/INativeYieldTokenStakeManager.sol";
import "../utils/FixedPoint128.sol";
import "../utils/Initializable.sol";
import "../utils/SafeTransferLib.sol";
import "../utils/OutrunAMMLibrary.sol";
import "../utils/AutoIncrementId.sol";
import "../token/Meme.sol";
import "../token/MemeLiquidProof.sol";

/**
 * @title Trapping into the memeverse
 */
contract Memeverse is IMemeverse, ERC721Burnable, Ownable, Initializable, AutoIncrementId {
    using SafeTransferLib for IERC20;

    uint256 public constant DAY = 24 * 3600;
    uint256 public constant RATIO = 10000;
    address public immutable OUTRUN_AMM_ROUTER;
    address public immutable OUTRUN_AMM_FACTORY;
    
    address public revenuePool;
    address public reserveFundManager;
    uint256 public genesisFee;
    uint256 public reserveFundRatio;
    uint256 public permanentLockRatio;
    uint256 public maxEarlyUnlockRatio;
    uint128 public minDurationDays;
    uint128 public maxDurationDays;
    uint128 public minLockupDays;
    uint128 public maxLockupDays;
    uint128 public minfundBasedAmount;
    uint128 public maxfundBasedAmount;

    mapping(string symbol => bool) private _symbolMap;
    mapping(uint256 poolId => LaunchPool) private _launchPools;
    mapping(uint256 typeId => FundType fundType) private _fundTypes;

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _revenuePool,
        address _outrunAMMFactory,
        address _outrunAMMRouter
    ) ERC721(_name, _symbol) Ownable(_owner) {
        revenuePool = _revenuePool;
        OUTRUN_AMM_ROUTER = _outrunAMMRouter;
        OUTRUN_AMM_FACTORY = _outrunAMMFactory;
    }

    function launchPools(uint256 poolId) external view override returns (LaunchPool memory) {
        return _launchPools[poolId];
    }

    function fundTypes(uint256 typeId) external view override returns (FundType memory) {
        return _fundTypes[typeId];
    }

    function initialize(
        address _reserveFundManager,
        uint256 _genesisFee,
        uint256 _reserveFundRatio,
        uint256 _permanentLockRatio,
        uint256 _maxEarlyUnlockRatio,
        uint128 _minDurationDays,
        uint128 _maxDurationDays,
        uint128 _minLockupDays,
        uint128 _maxLockupDays,
        uint128 _minfundBasedAmount,
        uint128 _maxfundBasedAmount
    ) external override initializer {
        reserveFundManager = _reserveFundManager;
        genesisFee = _genesisFee;
        reserveFundRatio = _reserveFundRatio;
        permanentLockRatio = _permanentLockRatio;
        maxEarlyUnlockRatio = _maxEarlyUnlockRatio;
        minDurationDays = _minDurationDays;
        maxDurationDays = _maxDurationDays;
        minLockupDays = _minLockupDays;
        maxLockupDays = _maxLockupDays;
        minfundBasedAmount = _minfundBasedAmount;
        maxfundBasedAmount = _maxfundBasedAmount;
    }

    /**
     * @dev Deposit native yield token to mint token
     * @param poolId - LaunchPool id
     * @param amountInNativeYieldToken - Amount of native yield token
     * @notice Approve fund token first
     */
    function deposit(uint256 poolId, uint256 amountInNativeYieldToken) external override {
        address msgSender = msg.sender;

        LaunchPool storage pool = _launchPools[poolId];
        uint256 endTime = pool.endTime;
        uint256 currentTime = block.timestamp;
        require(currentTime < endTime, "Invalid time");

        uint256 fundTypeId = pool.fundTypeId;
        FundType storage fundType = _fundTypes[fundTypeId];
        require(amountInNativeYieldToken >= fundType.minFundDeposit, "Insufficient fund deposited");
        address fundToken = fundType.fundToken;
        IERC20(fundToken).safeTransferFrom(msgSender, address(this), amountInNativeYieldToken);

        // Stake
        (uint256 amountInPT,) = INativeYieldTokenStakeManager(fundType.outStakeManager).stake(amountInNativeYieldToken, pool.lockupDays, msgSender, address(this), msgSender);

        // Deposit to reserveFund
        uint256 reserveFundAmount = amountInPT * reserveFundRatio / RATIO;
        uint256 fundBasedAmount = pool.fundBasedAmount;
        uint256 basePriceX128 = (RATIO - reserveFundRatio) * FixedPoint128.Q128 / RATIO / fundBasedAmount / 2;
        IERC20(fundToken).approve(reserveFundManager, reserveFundAmount);
        address token = pool.token;
        IReserveFundManager(reserveFundManager).deposit(token, reserveFundAmount, basePriceX128, fundToken);
        amountInPT -= reserveFundAmount;

        // Mint token
        uint256 baseAmount = amountInPT * fundBasedAmount;
        uint256 deployAmount = baseAmount << 2;
        IMeme(token).mint(msgSender, baseAmount);
        IMeme(token).mint(address(this), deployAmount);

        // Deploy liquidity
        IERC20(token).approve(OUTRUN_AMM_ROUTER, deployAmount);
        IERC20(fundToken).approve(OUTRUN_AMM_ROUTER, amountInPT);
        (,, uint256 liquidity) = IOutrunAMMRouter(OUTRUN_AMM_ROUTER).addLiquidity(
            fundToken,
            token,
            amountInPT,
            deployAmount,
            amountInPT,
            deployAmount,
            address(this),
            block.timestamp + 600
        );

        // Mint liquidity proof token
        uint256 proofAmount = liquidity * (RATIO - permanentLockRatio) / RATIO; // TODO: Check this
        IMemeLiquidProof(pool.liquidProof).mint(msgSender, proofAmount);

        unchecked {
            pool.totalFund += amountInPT;
        }

        emit Deposit(poolId, msgSender, amountInPT, baseAmount, deployAmount, proofAmount);
    }

    /**
     * @dev Enable transfer about token of pool
     * @param poolId - LaunchPool id
     */
    function enablePoolTokenTransfer(uint256 poolId) external override {
        LaunchPool storage pool = _launchPools[poolId];
        FundType storage fundType = _fundTypes[pool.fundTypeId];
        require(pool.totalFund >= fundType.minTotalFund, "Insufficient staked fund");
        require(block.timestamp >= pool.endTime, "Pool not closed");
        address token = pool.token;
        require(!IMeme(token).isTransferable(), "Already enable transfer");
        IMeme(token).enableTransfer();
    }

    /**
     * @dev Burn liquidProof to claim the locked liquidity
     * @param poolId - LaunchPool id
     * @param burnedLiquidity - Burned liquidity
     * @notice If you unlock early, a portion of your liquidity will be permanently locked in reverse proportion to the time you have already locked
     */
    function claimPoolLiquidity(uint256 poolId, uint256 burnedLiquidity) external override returns (uint256 claimedLiquidity) {
        address msgSender = msg.sender;
        LaunchPool storage pool = _launchPools[poolId];
        IMemeLiquidProof(pool.liquidProof).burn(msgSender, burnedLiquidity);

        uint256 endTime = pool.endTime;
        uint256 lockupDays = pool.lockupDays;
        uint256 lockedDays = (block.timestamp - endTime) / DAY;
        if (lockedDays < lockupDays) {
            uint256 maxRatioDays = lockupDays * maxEarlyUnlockRatio / RATIO;
            lockedDays = lockedDays > maxRatioDays ? maxRatioDays : lockedDays;
            claimedLiquidity = burnedLiquidity * lockedDays / lockupDays;
        } else {
            claimedLiquidity = burnedLiquidity;
        }
        
        FundType storage fundType = _fundTypes[pool.fundTypeId];
        address pairAddress = OutrunAMMLibrary.pairFor(OUTRUN_AMM_FACTORY, fundType.fundToken, pool.token);
        IERC20(pairAddress).safeTransfer(msgSender, claimedLiquidity);

        emit ClaimPoolLiquidity(poolId, msgSender, claimedLiquidity);
    }

    /**
     * @dev Claim pool maker fee
     * @param poolId - LaunchPool id
     */
    function claimTransactionFees(uint256 poolId) external override {
        address msgSender = msg.sender;
        LaunchPool storage pool = _launchPools[poolId];
        require(msgSender == ownerOf(poolId) && block.timestamp > pool.endTime, "Permission denied");

        FundType storage fundType = _fundTypes[pool.fundTypeId];
        address pairAddress = OutrunAMMLibrary.pairFor(OUTRUN_AMM_FACTORY, fundType.fundToken, pool.token);
        IOutrunAMMPair pair = IOutrunAMMPair(pairAddress);
        (uint256 amount0, uint256 amount1) = pair.claimMakerFee();
        address token0 = pair.token0();
        address token1 = pair.token1();
        IERC20(token0).safeTransfer(msgSender, amount0);
        IERC20(token1).safeTransfer(msgSender, amount1);

        emit ClaimTransactionFees(poolId, msgSender, pool.token, token0, amount0, token1, amount1);
    }

    /**
     * @dev register memeverse
     * @param _name - Name of token
     * @param _symbol - Symbol of token
     * @param description - Description of token
     * @param durationDays - Duration days of launchpool
     * @param lockupDays - LockupDay of liquidity
     * @param fundBasedAmount - Token amount based fund
     * @param mintLimit - Maximum mint limit, if 0 => unlimited
     * @param fundTypeId - Fund type id
     */
    function registerMemeverse(
        string calldata _name,
        string calldata _symbol,
        string calldata description,
        uint256 durationDays,
        uint256 lockupDays,
        uint256 fundBasedAmount,
        uint256 mintLimit,
        uint256 fundTypeId
    ) external payable override returns (uint256 poolId) {
        require(msg.value >= genesisFee, "Insufficient genesis fee");
        require(lockupDays >= minLockupDays && lockupDays <= maxLockupDays, "Invalid lockup days");
        require(durationDays >= minDurationDays && durationDays <= maxDurationDays, "Invalid duration days");
        require(fundBasedAmount >= minfundBasedAmount && fundBasedAmount <= maxfundBasedAmount, "Invalid fundBasedAmount");
        require(bytes(_name).length < 32 && bytes(_symbol).length < 32 && bytes(description).length < 257, "String too long");

        FundType storage fundType = _fundTypes[fundTypeId];
        require(fundType.fundToken != address(0), "Invalid fund type");
        require(mintLimit == 0 || mintLimit >= fundBasedAmount * fundType.minTotalFund * 3, "Invalid mint limit");
        
        // Duplicate symbols are not allowed
        require(!_symbolMap[_symbol], "Symbol duplication");
        _symbolMap[_symbol] = true;

        // Deploy token
        address msgSender = msg.sender;
        address token = address(new Meme(_name, _symbol, 18, mintLimit, address(this), reserveFundManager, msgSender));
        address liquidProof = address(new MemeLiquidProof(
            string(abi.encodePacked(_name, " Liquid")),
            string(abi.encodePacked(_symbol, " LIQUID")),
            18,
            address(this)
        ));
        LaunchPool memory pool = LaunchPool(
            token, 
            liquidProof, 
            _name, 
            _symbol, 
            description, 
            0, 
            uint128(block.timestamp + durationDays * DAY),
            lockupDays, 
            fundBasedAmount,
            fundTypeId
        );
        poolId = nextId();
        _safeMint(msgSender, poolId);
        _launchPools[poolId] = pool;

        emit RegisterMemeverse(poolId, msgSender, token);
    }

    /**
     * @dev Set revenuePool
     * @param _revenuePool - Revenue pool address
     */
    function setRevenuePool(address _revenuePool) external override onlyOwner {
        revenuePool = _revenuePool;
    }

    /**
     * @dev Set genesis memeverse fee
     * @param _genesisFee - Genesis memeverse fee
     */
    function setGenesisFee(uint256 _genesisFee) external override onlyOwner {
        genesisFee = _genesisFee;
    }

    /**
     * @dev Set reserve fund ratio
     * @param _reserveFundRatio - Reserve fund ratio
     */
    function setReserveFundRatio(uint256 _reserveFundRatio) external override onlyOwner {
        require(_reserveFundRatio <= RATIO, "Ratio too high");
        reserveFundRatio = _reserveFundRatio;
    }

    /**
     * @dev Set permanent lock ratio
     * @param _permanentLockRatio - Permanent lock ratio
     */
    function setPermanentLockRatio(uint256 _permanentLockRatio) external override onlyOwner {
        require(_permanentLockRatio <= RATIO, "Ratio too high");
        permanentLockRatio = _permanentLockRatio;
    }

    /**
     * @dev Set max early unlock ratio
     * @param _maxEarlyUnlockRatio - Max early unlock ratio
     */
    function setMaxEarlyUnlockRatio(uint256 _maxEarlyUnlockRatio) external override onlyOwner {
        require(_maxEarlyUnlockRatio <= RATIO, "Ratio too high");
        maxEarlyUnlockRatio = _maxEarlyUnlockRatio;
    }

    /**
     * @dev Set launch pool duration days range
     * @param _minDurationDays - Min launch pool duration days
     * @param _maxDurationDays - Max launch pool duration days
     */
    function setDurationDaysRange(uint128 _minDurationDays, uint128 _maxDurationDays) external override onlyOwner {
        minDurationDays = _minDurationDays;
        maxDurationDays = _maxDurationDays;
    }

    /**
     * @dev Set liquidity lockup days range
     * @param _minLockupDays - Min liquidity lockup days
     * @param _maxLockupDays - Max liquidity lockup days
     */
    function setLockupDaysRange(uint128 _minLockupDays, uint128 _maxLockupDays) external override onlyOwner {
        minLockupDays = _minLockupDays;
        maxLockupDays = _maxLockupDays;
    }

    /**
     * @dev Set token amount based fund range
     * @param _minfundBasedAmount - Min token amount based fund
     * @param _maxfundBasedAmount - Max token amount based fund
     */
    function setFundBasedAmountRange(uint128 _minfundBasedAmount, uint128 _maxfundBasedAmount) external override onlyOwner {
        minfundBasedAmount = _minfundBasedAmount;
        maxfundBasedAmount = _maxfundBasedAmount;
    }

    /**
     * @dev Set fund type
     * @param typeId - Type id
     * @param minTotalFund - Min total fund
     * @param minFundDeposit - Min fund deposit
     * @param fundToken - Fund token address
     * @param outStakeManager - Out stake manager address
     */
    function setFundType(
        uint256 typeId, 
        uint256 minTotalFund, 
        uint256 minFundDeposit, 
        address fundToken, 
        address outStakeManager
    ) external override onlyOwner {
        _fundTypes[typeId] = FundType(minTotalFund, minFundDeposit, fundToken, outStakeManager);
    }
}

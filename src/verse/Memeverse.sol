// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

import "./interfaces/IMemeverse.sol";
import "./interfaces/IReserveFundManager.sol";
import "../external/IOutrunAMMPair.sol";
import "../external/IOutrunAMMRouter.sol";
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
    address public immutable UPT;

    address public revenuePool;
    address public reserveFundManager;
    uint256 public genesisFee;
    uint256 public reserveFundRatio;
    uint256 public permanentLockRatio;
    uint256 public maxEarlyUnlockRatio;
    uint256 public minTotalFund;
    uint128 public minDurationDays;
    uint128 public maxDurationDays;
    uint128 public minLockupDays;
    uint128 public maxLockupDays;
    uint128 public minfundBasedAmount;
    uint128 public maxfundBasedAmount;

    mapping(string symbol => bool) public symbolMap;
    mapping(uint256 poolId => LaunchPool) public launchPools;

    constructor(
        string memory _name,
        string memory _symbol,
        address _upt,
        address _owner,
        address _revenuePool,
        address _outrunAMMFactory,
        address _outrunAMMRouter
    ) ERC721(_name, _symbol) Ownable(_owner) {
        UPT = _upt;
        revenuePool = _revenuePool;
        OUTRUN_AMM_ROUTER = _outrunAMMRouter;
        OUTRUN_AMM_FACTORY = _outrunAMMFactory;

        IERC20(_upt).approve(_outrunAMMRouter, type(uint256).max);
    }

    function initialize(
        address _reserveFundManager,
        uint256 _genesisFee,
        uint256 _reserveFundRatio,
        uint256 _permanentLockRatio,
        uint256 _maxEarlyUnlockRatio,
        uint256 _minTotalFund,
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
        minTotalFund = _minTotalFund;
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
     * @param amountInUPT - Amount of UPT
     * @notice Approve fund token first
     */
    function deposit(uint256 poolId, uint256 amountInUPT) external override {
        address msgSender = msg.sender;

        LaunchPool storage pool = launchPools[poolId];
        uint256 endTime = pool.endTime;
        uint256 currentTime = block.timestamp;
        require(currentTime < endTime, NotDepositStage(endTime));

        // Deposit to reserveFund
        uint256 reserveFundAmount = amountInUPT * reserveFundRatio / RATIO;
        uint256 fundBasedAmount = pool.fundBasedAmount;
        uint256 basePriceX128 = (RATIO - reserveFundRatio) * FixedPoint128.Q128 / RATIO / fundBasedAmount / 2;
        IERC20(UPT).approve(reserveFundManager, reserveFundAmount);
        address token = pool.token;
        IReserveFundManager(reserveFundManager).deposit(token, reserveFundAmount, basePriceX128);
        amountInUPT -= reserveFundAmount;

        // Mint token
        uint256 baseAmount = amountInUPT * fundBasedAmount;
        uint256 deployAmount = baseAmount << 2;
        IMeme(token).mint(msgSender, baseAmount);
        IMeme(token).mint(address(this), deployAmount);

        // Deploy liquidity
        IERC20(token).approve(OUTRUN_AMM_ROUTER, deployAmount);
        IERC20(UPT).approve(OUTRUN_AMM_ROUTER, amountInUPT);
        (,, uint256 liquidity) = IOutrunAMMRouter(OUTRUN_AMM_ROUTER).addLiquidity(
            UPT,
            token,
            amountInUPT,
            deployAmount,
            amountInUPT,
            deployAmount,
            address(this),
            block.timestamp + 600
        );

        // Mint liquidity proof token
        uint256 proofAmount = liquidity * (RATIO - permanentLockRatio) / RATIO;
        IMemeLiquidProof(pool.liquidProof).mint(msgSender, proofAmount);

        unchecked {
            pool.totalFund += amountInUPT;
        }

        emit Deposit(poolId, msgSender, amountInUPT, baseAmount, deployAmount, proofAmount);
    }

    /**
     * @dev Enable transfer about token of pool
     * @param poolId - LaunchPool id
     */
    function enablePoolTokenTransfer(uint256 poolId) external override {
        LaunchPool storage pool = launchPools[poolId];
        uint256 _minTotalFund = minTotalFund;
        require(pool.totalFund >= _minTotalFund, InsufficientTotalFund(_minTotalFund));
        uint256 endTime = pool.endTime;
        require(block.timestamp >= endTime, NotLiquidityLockStage(endTime));
        address token = pool.token;
        IMeme(token).enableTransfer();
    }

    /**
     * @dev Burn liquidProof to claim the locked liquidity
     * @param poolId - LaunchPool id
     * @param proofTokenAmount - Burned liquid proof token amount
     * @notice If you unlock early, a portion of your liquidity will be permanently locked in reverse proportion to the time you have already locked
     */
    function redeemLiquidity(uint256 poolId, uint256 proofTokenAmount) external override returns (uint256 claimedLiquidity) {
        address msgSender = msg.sender;
        LaunchPool storage pool = launchPools[poolId];
        IMemeLiquidProof(pool.liquidProof).burn(msgSender, proofTokenAmount);

        uint256 endTime = pool.endTime;
        uint256 lockupDays = pool.lockupDays;
        uint256 lockedDays = (block.timestamp - endTime) / DAY;
        if (lockedDays < lockupDays) {
            uint256 maxRatioDays = lockupDays * maxEarlyUnlockRatio / RATIO;
            lockedDays = lockedDays > maxRatioDays ? maxRatioDays : lockedDays;
            claimedLiquidity = proofTokenAmount * lockedDays / lockupDays;
        } else {
            claimedLiquidity = proofTokenAmount;
        }

        address pairAddress = OutrunAMMLibrary.pairFor(OUTRUN_AMM_FACTORY, UPT, pool.token);
        IERC20(pairAddress).safeTransfer(msgSender, claimedLiquidity);

        emit RedeemLiquidity(poolId, msgSender, claimedLiquidity);
    }

    /**
     * @dev Claim pool trade fee
     * @param poolId - LaunchPool id
     */
    function claimTradeFees(uint256 poolId) external override {
        address msgSender = msg.sender;
        LaunchPool storage pool = launchPools[poolId];
        require(msgSender == ownerOf(poolId) && block.timestamp > pool.endTime, "Permission denied");

        address pairAddress = OutrunAMMLibrary.pairFor(OUTRUN_AMM_FACTORY, UPT, pool.token);
        IOutrunAMMPair pair = IOutrunAMMPair(pairAddress);
        (uint256 amount0, uint256 amount1) = pair.claimMakerFee();
        address token0 = pair.token0();
        address token1 = pair.token1();
        IERC20(token0).safeTransfer(msgSender, amount0);
        IERC20(token1).safeTransfer(msgSender, amount1);

        emit ClaimTradeFees(poolId, msgSender, token0, amount0, token1, amount1);
    }

    /**
     * @dev register memeverse
     * @param _name - Name of token
     * @param _symbol - Symbol of token
     * @param description - Description of token
     * @param durationDays - Duration days of launchpool
     * @param lockupDays - LockupDay of liquidity
     * @param fundBasedAmount - Token amount based fund
     */
    function registerMemeverse(
        string calldata _name,
        string calldata _symbol,
        string calldata description,
        uint256 durationDays,
        uint256 lockupDays,
        uint256 fundBasedAmount
    ) external payable override returns (uint256 poolId) {
        uint256 msgValue = msg.value;
        uint256 _genesisFee = genesisFee;
        require(msgValue >= _genesisFee, InsufficientGenesisFee(_genesisFee));
        Address.sendValue(payable(revenuePool), msgValue);

        require(
            lockupDays >= minLockupDays && 
            lockupDays <= maxLockupDays && 
            durationDays >= minDurationDays && 
            durationDays <= maxDurationDays && 
            fundBasedAmount >= minfundBasedAmount && 
            fundBasedAmount <= maxfundBasedAmount && 
            bytes(_name).length < 32 && 
            bytes(_symbol).length < 32 && 
            bytes(description).length < 257, 
            InvalidRegisterInfo()
        );
        
        // Duplicate symbols are not allowed
        require(!symbolMap[_symbol], "Symbol duplication");
        symbolMap[_symbol] = true;

        // Deploy token
        address msgSender = msg.sender;
        address token = address(new Meme(_name, _symbol, 18, msgSender, address(this), reserveFundManager));
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
            block.timestamp + durationDays * DAY,
            lockupDays, 
            fundBasedAmount
        );
        poolId = nextId();
        _safeMint(msgSender, poolId);
        launchPools[poolId] = pool;

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
     * @dev Set min totalFund in launch pool
     * @param _minTotalFund - Min totalFund
     */
    function setMinTotalFund(uint256 _minTotalFund) external override onlyOwner {
        minTotalFund = _minTotalFund;
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
}

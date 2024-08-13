// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

import "./interfaces/IMemeverse.sol";
import "./interfaces/IReserveFundManager.sol";
import "../blast/GasManagerable.sol";
import "../common/IORETH.sol";
import "../common/IORUSD.sol";
import "../common/IOutrunAMMPair.sol";
import "../common/IOutrunAMMRouter.sol";
import "../common/IORETHStakeManager.sol";
import "../common/IORUSDStakeManager.sol";
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
contract Memeverse is IMemeverse, ERC721Burnable, Ownable, GasManagerable, Initializable, AutoIncrementId {
    using SafeTransferLib for IERC20;

    address public constant USDB = 0x4200000000000000000000000000000000000022;
    uint256 public constant DAY = 24 * 3600;
    uint256 public constant RATIO = 10000;
    address public immutable orETH;
    address public immutable osETH;
    address public immutable orUSD;
    address public immutable osUSD;
    address public immutable orETHStakeManager;
    address public immutable orUSDStakeManager;
    address public immutable outrunAMMRouter;
    address public immutable outrunAMMFactory;
    
    address public reserveFundManager;
    uint256 public genesisFee;
    uint256 public reserveFundRatio;
    uint256 public permanentLockRatio;
    uint256 public maxEarlyUnlockRatio;
    uint256 public minEthFund;
    uint256 public minUsdbFund;
    uint128 public minDurationDays;
    uint128 public maxDurationDays;
    uint128 public minLockupDays;
    uint128 public maxLockupDays;
    uint128 public minfundBasedAmount;
    uint128 public maxfundBasedAmount;

    mapping(uint256 poolId => LaunchPool) private _launchPools;
    mapping(string symbol => bool) private _symbolMap;
    mapping(uint256 poolId => uint256) private _tempFunds;
    mapping(bytes32 beacon => uint256) private _tempFundPool;

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _gasManager,
        address _orETH,
        address _osETH,
        address _orUSD,
        address _osUSD,
        address _orETHStakeManager,
        address _orUSDStakeManager,
        address _outrunAMMFactory,
        address _outrunAMMRouter
    ) ERC721(_name, _symbol) Ownable(_owner) GasManagerable(_gasManager) {
        orETH = _orETH;
        osETH = _osETH;
        orUSD = _orUSD;
        osUSD = _osUSD;
        orETHStakeManager = _orETHStakeManager;
        orUSDStakeManager = _orUSDStakeManager;
        outrunAMMFactory = _outrunAMMFactory;
        outrunAMMRouter = _outrunAMMRouter;

        IERC20(orETH).approve(_orETHStakeManager, type(uint256).max);
        IERC20(osETH).approve(_outrunAMMRouter, type(uint256).max);
        IERC20(orUSD).approve(_orUSDStakeManager, type(uint256).max);
        IERC20(osUSD).approve(_outrunAMMRouter, type(uint256).max);
    }

    function launchPools(uint256 poolId) external view override returns (LaunchPool memory) {
        return _launchPools[poolId];
    }

    function tempFunds(uint256 poolId) external view override returns (uint256) {
        return _tempFunds[poolId];
    }

    function tempFundPool(uint256 poolId, address account) external view override returns (uint256) {
        return _tempFundPool[getBeacon(poolId, account)];
    }

    function getBeacon(uint256 poolId, address account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(poolId, account));
    }

    function initialize(
        address _reserveFundManager,
        uint256 _genesisFee,
        uint256 _reserveFundRatio,
        uint256 _permanentLockRatio,
        uint256 _maxEarlyUnlockRatio,
        uint256 _minEthFund,
        uint256 _minUsdbFund,
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
        minEthFund = _minEthFund;
        minUsdbFund = _minUsdbFund;
        minDurationDays = _minDurationDays;
        maxDurationDays = _maxDurationDays;
        minLockupDays = _minLockupDays;
        maxLockupDays = _maxLockupDays;
        minfundBasedAmount = _minfundBasedAmount;
        maxfundBasedAmount = _maxfundBasedAmount;

        IERC20(osETH).approve(_reserveFundManager, type(uint256).max);
        IERC20(osUSD).approve(_reserveFundManager, type(uint256).max);
    }

    /**
     * @dev Deposit temporary fund
     * @param poolId - LaunchPool id
     * @param usdbValue - USDB value to deposit
     */
    function depositToTempFundPool(uint256 poolId, uint256 usdbValue) external payable override {
        address msgSender = msg.sender;
        require(msgSender == tx.origin, "Only EOA account");

        LaunchPool storage pool = _launchPools[poolId];
        uint128 endTime = pool.endTime;
        uint128 maxDeposit = pool.maxDeposit;
        uint256 currentTime = block.timestamp;
        require(currentTime < endTime, "Invalid time");

        uint256 value;
        if (pool.ethOrUsdb) {
            value = usdbValue;
            require(value <= maxDeposit, "USDB value exceeds max deposit");
            IERC20(USDB).safeTransferFrom(msgSender, address(this), value);
        } else {
            value = msg.value;
            require(value <= maxDeposit, "ETH value exceeds max deposit");
        }
        
        unchecked {
            _tempFunds[poolId] += value;
            _tempFundPool[getBeacon(poolId, msgSender)] += value;
        }
    }

    /**
     * @dev Claim token or refund after endTime
     * @param poolId - LaunchPool id
     */
    function claimTokenOrFund(uint256 poolId) external override {
        address msgSender = msg.sender;
        LaunchPool storage pool = _launchPools[poolId];
        bytes32 beacon = getBeacon(poolId, msgSender);
        uint256 fund = _tempFundPool[beacon];
        require(fund > 0, "No fund");

        _tempFunds[poolId] -= fund;
        _tempFundPool[beacon] = 0;

        uint256 lockupDays = pool.lockupDays;
        uint256 currentTime = block.timestamp;
        bool ethOrUsdb = pool.ethOrUsdb;

        if (currentTime >= pool.endTime && pool.totalFund >= (ethOrUsdb ? minUsdbFund : minEthFund)) {
            if (ethOrUsdb) {
                IERC20(USDB).safeTransfer(msgSender, fund);
            } else {
                SafeTransferLib.safeTransferETH(payable(msgSender), fund);
            }
            return;
        }

        address token = pool.token;
        uint256 fundBasedAmount = pool.fundBasedAmount;
        uint256 amountInOS;
        uint256 reserveFundAmount;

        // Stake
        if (ethOrUsdb) {
            IORUSD(orUSD).deposit(fund);
            (amountInOS,) = IORUSDStakeManager(orUSDStakeManager).stake(fund, lockupDays, msgSender, address(this), msgSender);
        } else {
            IORETH(orETH).deposit{value: fund}();
            (amountInOS,) = IORETHStakeManager(orETHStakeManager).stake(fund, lockupDays, msgSender, address(this), msgSender);
        }
        
        // Deposit to reserveFund
        reserveFundAmount = amountInOS * reserveFundRatio / RATIO;
        uint256 basePriceX128 = (RATIO - reserveFundRatio) * FixedPoint128.Q128 / RATIO / fundBasedAmount / 2;
        IReserveFundManager(reserveFundManager).deposit(token, reserveFundAmount, basePriceX128, ethOrUsdb);
        amountInOS -= reserveFundAmount;

        // Mint token
        uint256 baseAmount = amountInOS * fundBasedAmount;
        uint256 deployAmount = baseAmount << 2;
        IMeme(token).mint(msgSender, baseAmount);
        IMeme(token).mint(address(this), deployAmount);
        
        // Deploy liquidity
        IERC20(token).approve(outrunAMMRouter, deployAmount);
        (,, uint256 liquidity) = IOutrunAMMRouter(outrunAMMRouter).addLiquidity(
            ethOrUsdb ? osUSD : osETH,
            token,
            amountInOS,
            deployAmount,
            amountInOS,
            deployAmount,
            address(this),
            block.timestamp + 600
        );

        // Mint liquidity proof token
        uint256 proofAmount = liquidity * permanentLockRatio / RATIO;
        IMemeLiquidProof(pool.liquidProof).mint(msgSender, proofAmount);

        unchecked {
            pool.totalFund += fund;
        }

        emit ClaimToken(poolId, msgSender, fund, baseAmount, deployAmount, proofAmount);
    }

    /**
     * @dev Enable transfer about token of pool
     * @param poolId - LaunchPool id
     */
    function enablePoolTokenTransfer(uint256 poolId) external override {
        LaunchPool storage pool = _launchPools[poolId];
        require(pool.totalFund >= (pool.ethOrUsdb ? minUsdbFund : minEthFund), "Insufficient staked fund");

        address token = pool.token;
        require(!IMeme(token).isTransferable(), "Already enable transfer");
        require(block.timestamp >= pool.endTime, "Pool not closed");

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
        
        address lpBaseToken = pool.ethOrUsdb ? osUSD : osETH;
        address pairAddress = OutrunAMMLibrary.pairFor(outrunAMMFactory, pool.token, lpBaseToken);
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

        address lpBaseToken = pool.ethOrUsdb ? osUSD : osETH;
        address pairAddress = OutrunAMMLibrary.pairFor(outrunAMMFactory, pool.token, lpBaseToken);
        IOutrunAMMPair pair = IOutrunAMMPair(pairAddress);
        (uint256 amount0, uint256 amount1) = pair.claimMakerFee();
        IERC20(pair.token0()).safeTransfer(msgSender, amount0);
        IERC20(pair.token1()).safeTransfer(msgSender, amount1);

        emit ClaimTransactionFees(poolId, msgSender, pool.token, amount0, amount1);
    }

    /**
     * @dev register memeverse
     * @param _name - Name of token
     * @param _symbol - Symbol of token
     * @param durationDays - Duration days of launchpool
     * @param maxDeposit - Max fee per deposit
     * @param lockupDays - LockupDay of liquidity
     * @param fundBasedAmount - Token amount based fund
     * @param maxSupply - Maximum token supply, if 0 => unlimited
     * @param ethOrUsdb - Type of deposited funds
     */
    function registerMemeverse(
        string calldata _name,
        string calldata _symbol,
        string calldata description,
        uint128 maxDeposit,
        uint128 durationDays,
        uint128 lockupDays,
        uint128 fundBasedAmount,
        uint256 maxSupply,
        bool ethOrUsdb
    ) external payable override returns (uint256 poolId) {
        require(msg.value >= genesisFee, "Insufficient genesis fee");
        require(maxDeposit > 0, "MaxDeposit zero input");
        require(durationDays >= minDurationDays && durationDays <= maxDurationDays, "Invalid duration days");
        require(lockupDays >= minLockupDays && lockupDays <= maxLockupDays, "Invalid lockup days");
        require(fundBasedAmount >= minfundBasedAmount && fundBasedAmount <= maxfundBasedAmount, "Invalid fundBasedAmount");
        require(bytes(_name).length < 32 && bytes(_symbol).length < 32 && bytes(description).length < 257, "String too long");

        // Duplicate symbols are not allowed during the liquidity lock period
        require(!_symbolMap[_symbol], "Symbol duplication");
        _symbolMap[_symbol] = true;

        uint256 endTime = block.timestamp + durationDays * DAY;

        // Deploy token
        address msgSender = msg.sender;
        address token = address(new Meme(_name, _symbol, 18, maxSupply, address(this), reserveFundManager, msgSender));
        address liquidProof = address(new MemeLiquidProof(
            string(abi.encodePacked(_name, " Liquid")),
            string(abi.encodePacked(_symbol, " LIQUID")),
            18,
            address(this),
            msgSender
        ));
        LaunchPool memory pool = LaunchPool(
            token, 
            liquidProof, 
            _name, 
            _symbol, 
            description, 
            0, 
            uint128(endTime),
            maxDeposit,
            lockupDays, 
            fundBasedAmount,
            ethOrUsdb
        );
        poolId = nextId();
        _safeMint(msgSender, poolId);
        _launchPools[poolId] = pool;

        emit RegisterMemeverse(poolId, msgSender, token);
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
     * @dev Set min eth fund staked amount to enable transfer token
     * @param _minEthFund - Min eth fund staked amount
     */
    function setMinEthFund(uint256 _minEthFund) external override onlyOwner {
        minEthFund = _minEthFund;
    }

    /**
     * @dev Set min usdb fund staked amount to enable transfer token
     * @param _minUsdbFund - Min usdb fund staked amount
     */
    function setMinUsdbFund(uint256 _minUsdbFund) external override onlyOwner {
        minUsdbFund = _minUsdbFund;
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

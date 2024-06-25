// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "./interfaces/IMemeverse.sol";
import "./interfaces/IReserveFundManager.sol";
import "../blast/GasManagerable.sol";
import "../utils/FixedPoint128.sol";
import "../utils/Initializable.sol";
import "../utils/AutoIncrementId.sol";
import "../utils/IORETH.sol";
import "../utils/IORUSD.sol";
import "../utils/OutswapV1Library.sol";
import "../utils/IOutswapV1Router.sol";
import "../utils/IOutswapV1Pair.sol";
import "../utils/IORETHStakeManager.sol";
import "../utils/IORUSDStakeManager.sol";
import "../token/Meme.sol";
import "../token/MemeLiquidityERC20.sol";
import "../token/interfaces/IMeme.sol";
import "../token/interfaces/IMemeLiquidityERC20.sol";

/**
 * @title Trapped into the memeverse
 */
contract Memeverse is IMemeverse, Multicall, Ownable, GasManagerable, Initializable, AutoIncrementId {
    using SafeERC20 for IERC20;

    address public constant USDB = 0x4200000000000000000000000000000000000022;
    uint256 public constant DAY = 24 * 3600;
    uint256 public constant RATIO = 10000;
    address public immutable orETH;
    address public immutable osETH;
    address public immutable orUSD;
    address public immutable osUSD;
    address public immutable orETHStakeManager;
    address public immutable orUSDStakeManager;
    address public immutable outswapV1Router;
    address public immutable outswapV1Factory;
    
    address public reserveFundManager;
    uint256 public reserveFundRatio;
    uint256 public permanentLockRatio;
    uint256 public maxEarlyUnlockRatio;
    uint256 public minEthLiquidity;
    uint256 public minUsdbLiquidity;
    uint256 public minDurationDays;
    uint256 public maxDurationDays;
    uint256 public minLockupDays;
    uint256 public maxLockupDays;
    uint256 public ethLiquidityThreshold;
    uint256 public usdbLiquidityThreshold;
    uint256 public genesisFee;

    mapping(address token => uint256) private _poolIds;
    mapping(uint256 poolId => LaunchPool) private _launchPools;
    mapping(string symbol => bool) private _symbolMap;
    mapping(uint256 poolId => uint256) private _tempFunds;
    mapping(bytes32 beacon => uint256) private _tempFundPool;

    constructor(
        address _owner,
        address _gasManager,
        address _orETH,
        address _osETH,
        address _orUSD,
        address _osUSD,
        address _orETHStakeManager,
        address _orUSDStakeManager,
        address _outswapV1Router,
        address _outswapV1Factory
    ) Ownable(_owner) GasManagerable(_gasManager) {
        orETH = _orETH;
        osETH = _osETH;
        orUSD = _orUSD;
        osUSD = _osUSD;
        orETHStakeManager = _orETHStakeManager;
        orUSDStakeManager = _orUSDStakeManager;
        outswapV1Router = _outswapV1Router;
        outswapV1Factory = _outswapV1Factory;

        IERC20(orETH).approve(_orETHStakeManager, type(uint256).max);
        IERC20(osETH).approve(_outswapV1Router, type(uint256).max);
        IERC20(orUSD).approve(_orUSDStakeManager, type(uint256).max);
        IERC20(osUSD).approve(_outswapV1Router, type(uint256).max);

    }

    function poolIds(address token) external view override returns (uint256) {
        return _poolIds[token];
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

    function getPoolByToken(address token) external view override returns (LaunchPool memory) {
        return _launchPools[_poolIds[token]];
    }

    function getBeacon(uint256 poolId, address account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(poolId, account));
    }

    function initialize(
        address _reserveFundManager,
        uint256 _reserveFundRatio,
        uint256 _permanentLockRatio,
        uint256 _maxEarlyUnlockRatio,
        uint256 _minEthLiquidity,
        uint256 _minUsdbLiquidity,
        uint256 _minDurationDays,
        uint256 _maxDurationDays,
        uint256 _minLockupDays,
        uint256 _maxLockupDays,
        uint256 _ethLiquidityThreshold,
        uint256 _usdbLiquidityThreshold,
        uint256 _genesisFee
    ) external override initializer {
        reserveFundManager = _reserveFundManager;
        IERC20(osETH).approve(_reserveFundManager, type(uint256).max);
        IERC20(osUSD).approve(_reserveFundManager, type(uint256).max);
        setReserveFundRatio(_reserveFundRatio);
        setPermanentLockRatio(_permanentLockRatio);
        setMaxEarlyUnlockRatio(_maxEarlyUnlockRatio);
        setMinEthLiquidity(_minEthLiquidity);
        setMinUsdbLiquidity(_minUsdbLiquidity);
        setMinDurationDays(_minDurationDays);
        setMaxDurationDays(_maxDurationDays);
        setMinLockupDays(_minLockupDays);
        setMaxLockupDays(_maxLockupDays);
        setEthLiquidityThreshold(_ethLiquidityThreshold);
        setUsdbLiquidityThreshold(_usdbLiquidityThreshold);
        setGenesisFee(_genesisFee);
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

        uint128 endTime = pool.endTime;
        uint256 lockupDays = pool.lockupDays;
        uint256 currentTime = block.timestamp;
        bool ethOrUsdb = pool.ethOrUsdb;
        if (ethOrUsdb) {
            if (currentTime < endTime || pool.totalLiquidityFund < usdbLiquidityThreshold) {
                // Stake
                IORUSD(orUSD).deposit(fund);
                (uint256 amountInOSUSD,) = IORUSDStakeManager(orUSDStakeManager).stake(fund, lockupDays, msgSender, address(this), msgSender);
                
                // Deposit to reserveFund
                uint256 reserveFundAmount = amountInOSUSD * reserveFundRatio / RATIO;
                address token = pool.token;
                uint256 tokenBaseAmount = pool.tokenBaseAmount;
                uint256 basePriceX128 = (RATIO - reserveFundRatio) * FixedPoint128.Q128 / RATIO / tokenBaseAmount;
                IReserveFundManager(reserveFundManager).deposit(token, reserveFundAmount, basePriceX128, ethOrUsdb);
                amountInOSUSD -= reserveFundAmount;

                // Mint token
                uint256 tokenAmount = amountInOSUSD * tokenBaseAmount;
                IMeme(token).mint(msgSender, tokenAmount);
                IMeme(token).mint(address(this), tokenAmount);

                // Deploy liquidity
                IERC20(token).approve(outswapV1Router, tokenAmount);
                (,, uint256 liquidity) = IOutswapV1Router(outswapV1Router).addLiquidity(
                    osUSD,
                    token,
                    amountInOSUSD,
                    tokenAmount,
                    amountInOSUSD,
                    tokenAmount,
                    address(this),
                    block.timestamp + 600
                );

                IMemeLiquidityERC20(pool.liquidityERC20).mint(msgSender, liquidity * permanentLockRatio / RATIO);
                unchecked {
                    pool.totalLiquidityFund += fund;
                }
            } else {
                 IERC20(USDB).safeTransfer(msgSender, fund);
            }
        } else {
            if (currentTime < endTime || pool.totalLiquidityFund < ethLiquidityThreshold) {
                // Stake
                IORETH(orETH).deposit{value: fund}();
                (uint256 amountInOSETH,) = IORETHStakeManager(orETHStakeManager).stake(fund, lockupDays, msgSender, address(this), msgSender);
               
                // Deposit to reserveFund
                uint256 reserveFundAmount = amountInOSETH * reserveFundRatio / RATIO;
                address token = pool.token;
                uint256 tokenBaseAmount = pool.tokenBaseAmount;
                uint256 basePriceX128 = (RATIO - reserveFundRatio) * FixedPoint128.Q128 / RATIO / tokenBaseAmount;
                IReserveFundManager(reserveFundManager).deposit(token, reserveFundAmount, basePriceX128, ethOrUsdb);
                amountInOSETH -= reserveFundAmount;

                // Mint token
                uint256 tokenAmount = amountInOSETH * tokenBaseAmount;
                IMeme(token).mint(msgSender, tokenAmount);
                IMeme(token).mint(address(this), tokenAmount);

                // Deploy liquidity
                IERC20(token).approve(outswapV1Router, tokenAmount);
                (,, uint256 liquidity) = IOutswapV1Router(outswapV1Router).addLiquidity(
                    osETH,
                    token,
                    amountInOSETH,
                    tokenAmount,
                    amountInOSETH,
                    tokenAmount,
                    address(this),
                    block.timestamp + 600
                );

                IMemeLiquidityERC20(pool.liquidityERC20).mint(msgSender, liquidity * permanentLockRatio / RATIO);
                unchecked {
                    pool.totalLiquidityFund += fund;
                }
            } else {
                Address.sendValue(payable(msgSender), fund);
            }
        }
    }

    /**
     * @dev Enable transfer about token of pool
     * @param poolId - LaunchPool id
     */
    function enablePoolTokenTransfer(uint256 poolId) external override {
        LaunchPool storage pool = _launchPools[poolId];
        uint256 totalLiquidityFund = pool.totalLiquidityFund;

        if (pool.ethOrUsdb) {
            require(totalLiquidityFund >= usdbLiquidityThreshold, "Insufficient liquidity");
        } else {
            require(totalLiquidityFund >= ethLiquidityThreshold, "Insufficient liquidity");
        }

        address token = pool.token;
        require(!IMeme(token).transferable(), "Already enable transfer");
        require(block.timestamp >= pool.endTime, "Pool not closed");

        IMeme(token).enableTransfer();
    }

    /**
     * @dev Claim your liquidity by pooId when liquidity unlocked
     * @param poolId - LaunchPool id
     * @param burnedLiquidity - Burned liquidity
     */
    function claimPoolLiquidity(uint256 poolId, uint256 burnedLiquidity) external override {
        address msgSender = msg.sender;
        LaunchPool storage pool = _launchPools[poolId];
        require(block.timestamp >= pool.endTime + pool.lockupDays * DAY, "Locked liquidity");
        IMemeLiquidityERC20(pool.liquidityERC20).burn(msgSender, burnedLiquidity);

        address lpBaseToken = pool.ethOrUsdb ? osUSD : osETH;
        address pairAddress = OutswapV1Library.pairFor(outswapV1Factory, pool.token, lpBaseToken);
        IERC20(pairAddress).safeTransfer(msgSender, burnedLiquidity);

        emit ClaimPoolLiquidity(poolId, msgSender, burnedLiquidity);
    }

    /**
     * @dev Claim pool maker fee
     * @param poolId - LaunchPool id
     */
    function claimTransactionFees(uint256 poolId) external override {
        address msgSender = msg.sender;
        LaunchPool storage pool = _launchPools[poolId];
        require(msgSender == pool.owner && block.timestamp > pool.endTime, "Permission denied");

        address lpBaseToken = pool.ethOrUsdb ? osUSD : osETH;
        address pairAddress = OutswapV1Library.pairFor(outswapV1Factory, pool.token, lpBaseToken);
        IOutswapV1Pair pair = IOutswapV1Pair(pairAddress);
        (uint256 amount0, uint256 amount1) = pair.claimMakerFee();
        IERC20(pair.token0()).safeTransfer(msgSender, amount0);
        IERC20(pair.token1()).safeTransfer(msgSender, amount1);

        emit ClaimTransactionFees(poolId, msgSender, pool.token, amount0, amount1);
    }

    /**
     * @dev register memeverse
     * @param name - Name of token
     * @param symbol - Symbol of token
     * @param durationDays - Duration days of launchpool
     * @param maxDeposit - Max fee per deposit
     * @param lockupDays - LockupDay of liquidity
     * @param tokenBaseAmount - Token amount based fund
     * @param maxSupply - Maximum token supply, if 0 => unlimited
     * @param ethOrUsdb - Type of deposited funds
     */
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
    ) external payable override returns (uint256 poolId) {
        require(msg.value >= genesisFee, "Insufficient genesis fee");
        require(maxDeposit > 0 && tokenBaseAmount > 0 && maxSupply > 0, "Zero input");
        require(lockupDays >= minLockupDays && lockupDays <= maxLockupDays, "Invalid lockup days");
        require(durationDays >= minDurationDays && durationDays <= maxDurationDays, "Invalid duration days");
        require(bytes(name).length < 32 && bytes(symbol).length < 32 && bytes(description).length < 257, "String too long");

        // Duplicate symbols are not allowed during the liquidity lock period
        require(!_symbolMap[symbol], "Symbol duplication");
        _symbolMap[symbol] = true;

        uint256 endTime = block.timestamp + durationDays * DAY;

        // Deploy token
        address msgSender = msg.sender;
        address token = address(new Meme(name, symbol, maxSupply, address(this), reserveFundManager, msgSender));
        address liquidityERC20 = address(new MemeLiquidityERC20(
            string(abi.encodePacked(name, " Liquid")),
            string(abi.encodePacked(symbol, " LIQUID")),
            address(this),
            msgSender
        ));
        LaunchPool memory pool = LaunchPool(
            msgSender, 
            token, 
            liquidityERC20, 
            name, 
            symbol, 
            description, 
            0, 
            uint128(endTime),
            maxDeposit,
            lockupDays, 
            tokenBaseAmount,
            ethOrUsdb
        );
        poolId = nextId();
        _poolIds[token] = poolId;
        _launchPools[poolId] = pool;

        emit RegisterMemeverse(poolId, msgSender, token);
    }

    /**
     * @param poolId - LaunchPool id
     * @param names - Attributes names
     * @param datas - Attributes datas
     */
    function setAttributes(uint256 poolId, string[] calldata names, bytes[] calldata datas) external override {
        LaunchPool storage pool = _launchPools[poolId];
        require(msg.sender == pool.owner, "Permission denied");
        uint256 length = names.length;
        require(length == datas.length, "Invalid attributes");

        address token = pool.token;
        for(uint256 i = 0; i < length; i++) {
            bytes calldata data = datas[i];
            require(data.length < 257, "Data too long");
            IMeme(token).setAttribute(names[i], data);
        }
    }

    /**
     * @param _reserveFundRatio - Reserve fund ratio
     */
    function setReserveFundRatio(uint256 _reserveFundRatio) public override onlyOwner {
        require(_reserveFundRatio <= RATIO, "Ratio too high");
        reserveFundRatio = _reserveFundRatio;
    }

    /**
     * @param _permanentLockRatio - Permanent lock ratio
     */
    function setPermanentLockRatio(uint256 _permanentLockRatio) public override onlyOwner {
        require(_permanentLockRatio <= RATIO, "Ratio too high");
        permanentLockRatio = _permanentLockRatio;
    }

    /**
     * @param _maxEarlyUnlockRatio - Max early unlock ratio
     */
    function setMaxEarlyUnlockRatio(uint256 _maxEarlyUnlockRatio) public override onlyOwner {
        require(_maxEarlyUnlockRatio <= RATIO, "Ratio too high");
        maxEarlyUnlockRatio = _maxEarlyUnlockRatio;
    }

    /**
     * @param _minEthLiquidity - Min eth liquidity to enable transfer token
     */
    function setMinEthLiquidity(uint256 _minEthLiquidity) public override onlyOwner {
        minEthLiquidity = _minEthLiquidity;
    }

    /**
     * @param _minUsdbLiquidity - Min usdb liquidity to enable transfer token
     */
    function setMinUsdbLiquidity(uint256 _minUsdbLiquidity) public override onlyOwner {
        minUsdbLiquidity = _minUsdbLiquidity;
    }

    /**
     * @param _minDurationDays - Min launch pool duration days
     */
    function setMinDurationDays(uint256 _minDurationDays) public override onlyOwner {
        minDurationDays = _minDurationDays;
    }

    /**
     * @param _maxDurationDays - Max launch pool duration days
     */
    function setMaxDurationDays(uint256 _maxDurationDays) public override onlyOwner {
        maxDurationDays = _maxDurationDays;
    }

    /**
     * @param _minLockupDays - Min liquidity lockup days
     */
    function setMinLockupDays(uint256 _minLockupDays) public override onlyOwner {
        minLockupDays = _minLockupDays;
    }

    /**
     * @param _maxLockupDays - Max liquidity lockup days
     */
    function setMaxLockupDays(uint256 _maxLockupDays) public override onlyOwner {
        maxLockupDays = _maxLockupDays;
    }

    /**
     * @param _ethLiquidityThreshold - ETH liquidity threshold
     */
    function setEthLiquidityThreshold(uint256 _ethLiquidityThreshold) public override onlyOwner {
        ethLiquidityThreshold = _ethLiquidityThreshold;
    }

    /**
     * @param _usdbLiquidityThreshold - USDB liquidity threshold
     */
    function setUsdbLiquidityThreshold(uint256 _usdbLiquidityThreshold) public override onlyOwner {
        usdbLiquidityThreshold = _usdbLiquidityThreshold;
    }

    /**
     *@param _genesisFee - Genesis memeverse fee
     */
    function setGenesisFee(uint256 _genesisFee) public override onlyOwner {
        genesisFee = _genesisFee;
    }
}

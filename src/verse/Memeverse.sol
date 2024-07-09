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
import "../token/MemeLiquidProof.sol";
import "../token/interfaces/IMeme.sol";
import "../token/interfaces/IMemeLiquidProof.sol";

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
    uint256 public minEthFund;
    uint256 public minUsdbFund;
    uint256 public genesisFee;
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
        address _owner,
        address _gasManager,
        address _orETH,
        address _osETH,
        address _orUSD,
        address _osUSD,
        address _orETHStakeManager,
        address _orUSDStakeManager,
        address _outswapV1Factory,
        address _outswapV1Router
    ) Ownable(_owner) GasManagerable(_gasManager) {
        orETH = _orETH;
        osETH = _osETH;
        orUSD = _orUSD;
        osUSD = _osUSD;
        orETHStakeManager = _orETHStakeManager;
        orUSDStakeManager = _orUSDStakeManager;
        outswapV1Factory = _outswapV1Factory;
        outswapV1Router = _outswapV1Router;

        IERC20(orETH).approve(_orETHStakeManager, type(uint256).max);
        IERC20(osETH).approve(_outswapV1Router, type(uint256).max);
        IERC20(orUSD).approve(_orUSDStakeManager, type(uint256).max);
        IERC20(osUSD).approve(_outswapV1Router, type(uint256).max);
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
    ) external override initializer {
        reserveFundManager = _reserveFundManager;
        IERC20(osETH).approve(_reserveFundManager, type(uint256).max);
        IERC20(osUSD).approve(_reserveFundManager, type(uint256).max);
        setReserveFundRatio(_reserveFundRatio);
        setPermanentLockRatio(_permanentLockRatio);
        setMaxEarlyUnlockRatio(_maxEarlyUnlockRatio);
        setMinEthFund(_minEthFund);
        setMinUsdbFund(_minUsdbFund);
        setGenesisFee(_genesisFee);
        setMinDurationDays(_minDurationDays);
        setMaxDurationDays(_maxDurationDays);
        setMinLockupDays(_minLockupDays);
        setMaxLockupDays(_maxLockupDays);
        setMinfundBasedAmount(_minfundBasedAmount);
        setMaxfundBasedAmount(_maxfundBasedAmount);
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
            if (currentTime < endTime || pool.totalFund < minUsdbFund) {
                // Stake
                IORUSD(orUSD).deposit(fund);
                (uint256 amountInOSUSD,) = IORUSDStakeManager(orUSDStakeManager).stake(fund, lockupDays, msgSender, address(this), msgSender);
                
                // Deposit to reserveFund
                uint256 reserveFundAmount = amountInOSUSD * reserveFundRatio / RATIO;
                address token = pool.token;
                uint256 fundBasedAmount = pool.fundBasedAmount;
                uint256 basePriceX128 = (RATIO - reserveFundRatio) * FixedPoint128.Q128 / RATIO / fundBasedAmount / 2;
                IReserveFundManager(reserveFundManager).deposit(token, reserveFundAmount, basePriceX128, ethOrUsdb);
                amountInOSUSD -= reserveFundAmount;

                // Mint token
                uint256 baseAmount = amountInOSUSD * fundBasedAmount;
                uint256 deployAmount = baseAmount << 2;
                IMeme(token).mint(msgSender, baseAmount);
                IMeme(token).mint(address(this), deployAmount);

                // Deploy liquidity
                IERC20(token).approve(outswapV1Router, deployAmount);
                (,, uint256 liquidity) = IOutswapV1Router(outswapV1Router).addLiquidity(
                    osUSD,
                    token,
                    amountInOSUSD,
                    deployAmount,
                    amountInOSUSD,
                    deployAmount,
                    address(this),
                    block.timestamp + 600
                );

                uint256 proofAmount = liquidity * permanentLockRatio / RATIO;
                IMemeLiquidProof(pool.liquidProof).mint(msgSender, proofAmount);
                unchecked {
                    pool.totalFund += fund;
                }

                emit ClaimToken(poolId, msgSender, fund, baseAmount, deployAmount, proofAmount);
            } else {
                 IERC20(USDB).safeTransfer(msgSender, fund);
            }
        } else {
            if (currentTime < endTime || pool.totalFund < minEthFund) {
                // Stake
                IORETH(orETH).deposit{value: fund}();
                (uint256 amountInOSETH,) = IORETHStakeManager(orETHStakeManager).stake(fund, lockupDays, msgSender, address(this), msgSender);
               
                // Deposit to reserveFund
                uint256 reserveFundAmount = amountInOSETH * reserveFundRatio / RATIO;
                address token = pool.token;
                uint256 fundBasedAmount = pool.fundBasedAmount;
                uint256 basePriceX128 = (RATIO - reserveFundRatio) * FixedPoint128.Q128 / RATIO / fundBasedAmount / 2;
                IReserveFundManager(reserveFundManager).deposit(token, reserveFundAmount, basePriceX128, ethOrUsdb);
                amountInOSETH -= reserveFundAmount;

                // Mint token
                uint256 baseAmount = amountInOSETH * fundBasedAmount;
                uint256 deployAmount = baseAmount << 2;
                IMeme(token).mint(msgSender, baseAmount);
                IMeme(token).mint(address(this), deployAmount);

                // Deploy liquidity
                IERC20(token).approve(outswapV1Router, deployAmount);
                (,, uint256 liquidity) = IOutswapV1Router(outswapV1Router).addLiquidity(
                    osETH,
                    token,
                    amountInOSETH,
                    deployAmount,
                    amountInOSETH,
                    deployAmount,
                    address(this),
                    block.timestamp + 600
                );

                uint256 proofAmount = liquidity * permanentLockRatio / RATIO;
                IMemeLiquidProof(pool.liquidProof).mint(msgSender, proofAmount);
                unchecked {
                    pool.totalFund += fund;
                }

                emit ClaimToken(poolId, msgSender, fund, baseAmount, deployAmount, proofAmount);
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
        uint256 totalFund = pool.totalFund;

        if (pool.ethOrUsdb) {
            require(totalFund >= minUsdbFund, "Insufficient staked fund");
        } else {
            require(totalFund >= minEthFund, "Insufficient staked fund");
        }

        address token = pool.token;
        require(!IMeme(token).transferable(), "Already enable transfer");
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
        address pairAddress = OutswapV1Library.pairFor(outswapV1Factory, pool.token, lpBaseToken);
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
     * @param fundBasedAmount - Token amount based fund
     * @param maxSupply - Maximum token supply, if 0 => unlimited
     * @param ethOrUsdb - Type of deposited funds
     */
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
    ) external payable override returns (uint256 poolId) {
        require(msg.value >= genesisFee, "Insufficient genesis fee");
        require(maxDeposit > 0, "MaxDeposit zero input");
        require(durationDays >= minDurationDays && durationDays <= maxDurationDays, "Invalid duration days");
        require(lockupDays >= minLockupDays && lockupDays <= maxLockupDays, "Invalid lockup days");
        require(fundBasedAmount >= minfundBasedAmount && fundBasedAmount <= maxfundBasedAmount, "Invalid fundBasedAmount");
        require(bytes(name).length < 32 && bytes(symbol).length < 32 && bytes(description).length < 257, "String too long");

        // Duplicate symbols are not allowed during the liquidity lock period
        require(!_symbolMap[symbol], "Symbol duplication");
        _symbolMap[symbol] = true;

        uint256 endTime = block.timestamp + durationDays * DAY;

        // Deploy token
        address msgSender = msg.sender;
        address token = address(new Meme(name, symbol, maxSupply, address(this), reserveFundManager, msgSender));
        address liquidProof = address(new MemeLiquidProof(
            string(abi.encodePacked(name, " Liquid")),
            string(abi.encodePacked(symbol, " LIQUID")),
            address(this),
            msgSender
        ));
        LaunchPool memory pool = LaunchPool(
            msgSender, 
            token, 
            liquidProof, 
            name, 
            symbol, 
            description, 
            0, 
            uint128(endTime),
            maxDeposit,
            lockupDays, 
            fundBasedAmount,
            ethOrUsdb
        );
        poolId = nextId();
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
     * @param _minEthFund - Min eth fund staked amount to enable transfer token
     */
    function setMinEthFund(uint256 _minEthFund) public override onlyOwner {
        minEthFund = _minEthFund;
    }

    /**
     * @param _minUsdbFund -Min usdb fund staked amount to enable transfer token
     */
    function setMinUsdbFund(uint256 _minUsdbFund) public override onlyOwner {
        minUsdbFund = _minUsdbFund;
    }

    /**
     *@param _genesisFee - Genesis memeverse fee
     */
    function setGenesisFee(uint256 _genesisFee) public override onlyOwner {
        genesisFee = _genesisFee;
    }

    /**
     * @param _minDurationDays - Min launch pool duration days
     */
    function setMinDurationDays(uint128 _minDurationDays) public override onlyOwner {
        minDurationDays = _minDurationDays;
    }

    /**
     * @param _maxDurationDays - Max launch pool duration days
     */
    function setMaxDurationDays(uint128 _maxDurationDays) public override onlyOwner {
        maxDurationDays = _maxDurationDays;
    }

    /**
     * @param _minLockupDays - Min liquidity lockup days
     */
    function setMinLockupDays(uint128 _minLockupDays) public override onlyOwner {
        minLockupDays = _minLockupDays;
    }

    /**
     * @param _maxLockupDays - Max liquidity lockup days
     */
    function setMaxLockupDays(uint128 _maxLockupDays) public override onlyOwner {
        maxLockupDays = _maxLockupDays;
    }

    /**
     * @param _minfundBasedAmount - Min token amount based fund
     */
    function setMinfundBasedAmount(uint128 _minfundBasedAmount) public override onlyOwner {
        minfundBasedAmount = _minfundBasedAmount;
    }

    /**
     * @param _maxfundBasedAmount - Max token amount based fund
     */
    function setMaxfundBasedAmount(uint128 _maxfundBasedAmount) public override onlyOwner {
        maxfundBasedAmount = _maxfundBasedAmount;
    }
}

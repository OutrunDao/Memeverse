// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IReserveFundManager.sol";
import "../token/interfaces/IMeme.sol";
import "../blast/GasManagerable.sol";
import "../utils/FixedPoint128.sol";

/**
 * @title ReserveFundManager
 */
contract ReserveFundManager is IReserveFundManager, Ownable, GasManagerable {
    using SafeERC20 for IERC20;

    uint256 public constant RATIO = 10000;
    address public immutable osETH;
    address public immutable osUSD;
    address public immutable memeverse;

    uint256 public purchaseFeeRatio;
    mapping(address token => ReserveFund) private _reserveFunds;

    modifier onlyMemeverse() {
        require(msg.sender == memeverse, "Only memeverse");
        _;
    }

    constructor(
        address _owner,
        address _gasManager,
        address _osETH,
        address _osUSD,
        address _memeverse
    ) Ownable(_owner) GasManagerable(_gasManager) {
        osETH = _osETH;
        osUSD = _osUSD;
        memeverse = _memeverse;
    }

    function reserveFunds(address token) external view override returns (ReserveFund memory) {
        return _reserveFunds[token];
    }

    /**
     * @dev Deposit reserve fund
     * @param token - Token address
     * @param fundAmount - Reserve fund amount
     * @param basePriceX128 - Token base priceX128(mul 2** 128)
     * @param ethOrUsdb - Type of deposited funds, true --> usdb, false --> eth
     */
    function deposit(address token, uint256 fundAmount, uint256 basePriceX128, bool ethOrUsdb) external override onlyMemeverse {
        address fundToken = ethOrUsdb ? osUSD : osETH;
        IERC20(fundToken).safeTransferFrom(msg.sender, address(this), fundAmount);

        ReserveFund storage reserveFund = _reserveFunds[token];
        reserveFund.fundAmount += fundAmount;
        if (reserveFund.ethOrUsdb != ethOrUsdb) {
            reserveFund.ethOrUsdb = ethOrUsdb;
        }
        if (reserveFund.basePriceX128 == 0 ) {
            reserveFund.basePriceX128 = basePriceX128;
        }
    }

    /**
     * @dev Allow users to use their funds to purchase tokens from the reserve fund
     * @param token - Token address
     * @param inputFund - Input fund amount
     * @notice Users should approve their fund token allowance first
     */
    function purchase(address token, uint256 inputFund) external override returns (uint256 outputToken) {
        address msgSender = msg.sender;
        ReserveFund storage reserveFund = _reserveFunds[token];
        bool ethOrUsdb = reserveFund.ethOrUsdb;
        address fundToken = ethOrUsdb ? osUSD : osETH;
        IERC20(fundToken).safeTransferFrom(msgSender, address(this), inputFund);
        uint256 purchaseFee = inputFund * purchaseFeeRatio / RATIO;
        inputFund -= purchaseFee;

        outputToken = inputFund * FixedPoint128.Q128 / reserveFund.basePriceX128;
        uint256 tokenAmount = reserveFund.tokenAmount;
        require(tokenAmount >= outputToken, "Insufficient reserve token");
        reserveFund.tokenAmount = tokenAmount - outputToken;
        IERC20(token).safeTransfer(msgSender, outputToken);

        emit Purchase(token, outputToken, ethOrUsdb, purchaseFee);
    }

    /**
     * @dev Allow users to use funds from the reserve fund to repurchase their own tokens
     * @param token - Token address
     * @param inputToken - Input token amount
     * @notice Users should approve their token allowance first
     */
    function repurchase(address token, uint256 inputToken) external override returns (uint256 outputFund) {
        address msgSender = msg.sender;
        IERC20(token).safeTransferFrom(msgSender, address(this), inputToken);
        uint256 burnedToken = inputToken * purchaseFeeRatio / RATIO;
        IMeme(token).burn(address(this), burnedToken);
        inputToken -= burnedToken;

        ReserveFund storage reserveFund = _reserveFunds[token];
        outputFund = inputToken * reserveFund.basePriceX128 / FixedPoint128.Q128;
        uint256 fundAmount = reserveFund.fundAmount;
        require(fundAmount >= outputFund, "Insufficient reserve fund");
        reserveFund.fundAmount = fundAmount - outputFund;

        bool ethOrUsdb = reserveFund.ethOrUsdb;
        address fundToken = ethOrUsdb ? osUSD : osETH;
        IERC20(fundToken).safeTransfer(msgSender, outputFund);

        emit Repurchase(token, outputFund, ethOrUsdb, burnedToken);
    }

    /**
     * @param _purchaseFeeRatio - Purchase fee ratio
     */
    function setPurchaseFeeRatio(uint256 _purchaseFeeRatio) external override onlyOwner {
        require(_purchaseFeeRatio <= RATIO, "Ratio too high");
        purchaseFeeRatio = _purchaseFeeRatio;
    }
}

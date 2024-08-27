// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IReserveFundManager.sol";
import "../token/interfaces/IMeme.sol";
import "../utils/FixedPoint128.sol";
import "../utils/SafeTransferLib.sol";

/**
 * @title ReserveFundManager
 */
contract ReserveFundManager is IReserveFundManager, Ownable {
    using SafeTransferLib for IERC20;

    uint256 public constant RATIO = 10000;
    address public immutable MEMEVERSE;

    uint256 public purchaseFeeRatio;
    mapping(address token => ReserveFund) private _reserveFunds;

    constructor(address _owner, address _memeverse) Ownable(_owner) {
        MEMEVERSE = _memeverse;
    }

    function reserveFunds(address token) external view override returns (ReserveFund memory) {
        return _reserveFunds[token];
    }

    /**
     * @dev Deposit reserve fund
     * @param token - Token address
     * @param fundAmount - Reserve fund amount
     * @param basePriceX128 - Token base priceX128(mul 2**128)
     * @param fundToken - fund token address
     */
    function deposit(address token, uint256 fundAmount, uint256 basePriceX128, address fundToken) external override {
        require(msg.sender == MEMEVERSE, "Only memeverse");
        IERC20(fundToken).safeTransferFrom(msg.sender, address(this), fundAmount);

        ReserveFund storage reserveFund = _reserveFunds[token];
        reserveFund.fundAmount += fundAmount;
        reserveFund.fundToken = fundToken;

        if (reserveFund.basePriceX128 == 0 ) {
            reserveFund.basePriceX128 = basePriceX128;
        }
    }

    /**
     * @dev Allow users to use their funds to purchase tokens from the reserve fund
     * @param token - Token address
     * @param inputFundAmount - Input fund amount
     * @notice Users should approve their fund token allowance first
     */
    function purchase(address token, uint256 inputFundAmount) external override returns (uint256 outputTokenAmount) {
        address msgSender = msg.sender;
        ReserveFund storage reserveFund = _reserveFunds[token];
        address fundToken = reserveFund.fundToken;
        IERC20(fundToken).safeTransferFrom(msgSender, address(this), inputFundAmount);
        uint256 purchaseFee = inputFundAmount * purchaseFeeRatio / RATIO;
        inputFundAmount -= purchaseFee;

        outputTokenAmount = inputFundAmount * FixedPoint128.Q128 / reserveFund.basePriceX128;
        uint256 tokenAmount = reserveFund.tokenAmount;
        require(tokenAmount >= outputTokenAmount, "Insufficient reserve token");
        reserveFund.tokenAmount = tokenAmount - outputTokenAmount;
        IERC20(token).safeTransfer(msgSender, outputTokenAmount);

        emit Purchase(token, fundToken, inputFundAmount, outputTokenAmount, purchaseFee);
    }

    /**
     * @dev Allow users to use funds from the reserve fund to repurchase their own tokens
     * @param token - Token address
     * @param inputTokenAmount - Input token amount
     * @notice Users should approve their token allowance first
     */
    function repurchase(address token, uint256 inputTokenAmount) external override returns (uint256 outputFundAmount) {
        address msgSender = msg.sender;
        IERC20(token).safeTransferFrom(msgSender, address(this), inputTokenAmount);
        uint256 burnedTokenAmount = inputTokenAmount * purchaseFeeRatio / RATIO;
        IMeme(token).burn(address(this), burnedTokenAmount);
        inputTokenAmount -= burnedTokenAmount;

        ReserveFund storage reserveFund = _reserveFunds[token];
        outputFundAmount = inputTokenAmount * reserveFund.basePriceX128 / FixedPoint128.Q128;
        uint256 fundAmount = reserveFund.fundAmount;
        require(fundAmount >= outputFundAmount, "Insufficient reserve fund");
        reserveFund.fundAmount = fundAmount - outputFundAmount;

        address fundToken = reserveFund.fundToken;
        IERC20(fundToken).safeTransfer(msgSender, outputFundAmount);

        emit Repurchase(token, fundToken, inputTokenAmount, outputFundAmount, burnedTokenAmount);
    }

    /**
     * @param _purchaseFeeRatio - Purchase fee ratio
     */
    function setPurchaseFeeRatio(uint256 _purchaseFeeRatio) external override onlyOwner {
        require(_purchaseFeeRatio <= RATIO, "Ratio too high");
        purchaseFeeRatio = _purchaseFeeRatio;
    }
}

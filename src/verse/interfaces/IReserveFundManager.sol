// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/**
 * @title IReserveFundManager interface
 */
interface IReserveFundManager {
    struct ReserveFund {
        uint256 fundAmount;
        uint256 tokenAmount;
        uint256 basePriceX128;
        address fundToken;
    }

    function reserveFunds(address token) external view returns (ReserveFund memory);

    function deposit(address token, uint256 fundAmount, uint256 basePriceX128, address fundToken) external;

    function purchase(address token, uint256 fundAmount) external returns (uint256 tokenAmount);

    function repurchase(address token, uint256 tokenAmount) external returns (uint256 fundAmount);

    function setPurchaseFeeRatio(uint256 _purchaseFeeRatio) external;

    event Purchase(address indexed token, address fundToken, uint256 inputFundAmount, uint256 outputTokenAmount, uint256 purchaseFee);

    event Repurchase(address indexed token, address fundToken, uint256 inputTokenAmount, uint256 outputFundAmount, uint256 burnedTokenAmount);
}
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IERC20Errors.sol";

/**
 * @title Memeverse Liquidity ERC20 Token Interface
 */
interface IMemeLiquidityERC20 is IERC20, IERC20Errors {
    function memeverse() external view returns (address);

    function mint(address _account, uint256 _amount) external;

    function burn(address account, uint256 value) external returns (bool);
}
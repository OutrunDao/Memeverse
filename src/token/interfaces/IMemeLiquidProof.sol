// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "../../external/IERC20.sol";

/**
 * @title Memeverse Liquidity proof Token Interface
 */
interface IMemeLiquidProof is IERC20 {
    function memeverse() external view returns (address);

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external returns (bool);
}
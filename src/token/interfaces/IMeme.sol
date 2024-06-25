// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IERC20Errors.sol";

/**
 * @title Meme token interface
 */
interface IMeme is IERC20, IERC20Errors {
    function maxSupply() external view returns (uint256);

    function memeverse() external view returns (address);

    function reserveFundManager() external view returns (address);

    function transferable() external view returns (bool);

    function getAttributes(string calldata name) external view returns (bytes memory);

    /**
     * @dev Enable token transfer
     */
    function enableTransfer() external;

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 value) external returns (bool);

    /**
     * @dev Set attribute
     * @param name - Attribute name
     * @param data - Attribute data
     */
    function setAttribute(string calldata name, bytes calldata data) external;
}
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "./interfaces/IMemeLiquidProof.sol";

/**
 * @title Memeverse Liquidity proof Token Standard
 */
contract MemeLiquidProof is IMemeLiquidProof {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    address public memeverse;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    modifier onlyMemeverse() {
        require(msg.sender == memeverse, PermissionDenied());
        _;
    }

    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _memeverse) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        memeverse = _memeverse;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        if (to == address(0)) {
            unchecked {
                totalSupply -= amount;
            }
        }

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        if (to == address(0)) {
            unchecked {
                totalSupply -= amount;
            }
        }

        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address account, uint256 amount) external override onlyMemeverse {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external onlyMemeverse returns (bool) {
        require(balanceOf[account] >= amount, InsufficientBalance());
        _burn(account, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
}

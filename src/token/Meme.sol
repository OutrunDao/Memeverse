// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IMeme.sol";

/**
 * @title Meme token
 */
contract Meme is IMeme, Ownable {
    uint256 internal constant DAY = 24 * 3600;

    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    uint256 public mintLimit; // if 0, unlimit
    address public memeverse;
    address public reserveFundManager;
    bool public isTransferable;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    error MemeTokenExceedsMintLimit();
    error TransferNotEnable();

    modifier onlyMemeverse() {
        require(msg.sender == memeverse, "Only memeverse");
        _;
    }

    constructor(
        string memory _name, 
        string memory _symbol,
        uint8 _decimals, 
        uint256 _mintLimit,
        address _memeverse,
        address _reserveFundManager,
        address _owner
    ) Ownable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        mintLimit = _mintLimit;
        memeverse = _memeverse;
        reserveFundManager = _reserveFundManager;
    }

    function enableTransfer() external override onlyMemeverse {
        require(!isTransferable, "Already enable transfer");
        isTransferable = true;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        if (isTransferable) {
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
        } else {
            revert TransferNotEnable();
        }

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        if (isTransferable) {
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
        } else {
            revert TransferNotEnable();
        }

        return true;
    }

    function mint(address account, uint256 amount) external override onlyMemeverse {
        _mint(account, amount);

        uint256 _mintLimit = mintLimit;
        if (_mintLimit != 0 && totalSupply > _mintLimit) {
            revert MemeTokenExceedsMintLimit();
        }
    }

    function burn(address account, uint256 amount) external override returns (bool) {
        require(msg.sender == reserveFundManager, "Only reserveFundManager");
        require(balanceOf[account] >= amount, "Insufficient balance");
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

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IMeme.sol";
import "../blast/GasManagerable.sol";

/**
 * @title Memeverse token.
 */
contract Meme is IMeme, Ownable, GasManagerable {
    uint256 public constant DAY = 24 * 3600;

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;
    uint256 private _maxSupply; // if 0, unlimit
    address private _memeverse;
    address private _reserveFundManager;
    bool private _isTransferable;

    mapping(address account => uint256) private _balances;
    mapping(address account => mapping(address spender => uint256)) private _allowances;
    // Description, Twitter, Telegram, Discord, Website and more. Max length = 256
    mapping(string name => bytes) private _attributes;  // Additional attributes

    error MemeTokenExceedsMaxSupply();

    modifier onlyMemeverse() {
        require(msg.sender == _memeverse, "Only memeverse");
        _;
    }

    constructor(
        string memory name_, 
        string memory symbol_, 
        uint256 maxSupply_,
        address memeverse_,
        address reserveFundManager_,
        address owner_
    ) Ownable(owner_) GasManagerable(owner_) {
        _name = name_;
        _symbol = symbol_;
        _maxSupply = maxSupply_;
        _memeverse = memeverse_;
        _reserveFundManager = reserveFundManager_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return 18;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function maxSupply() public view override returns (uint256) {
        return _maxSupply;
    }

    function memeverse() public view override returns (address) {
        return _memeverse;
    }

    function reserveFundManager() public view override returns (address) {
        return _reserveFundManager;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transferable() external view override returns (bool) {
        return _isTransferable;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function getAttributes(string calldata attributeName) external view override returns (bytes memory) {
        return _attributes[attributeName];
    }

    function enableTransfer() external override onlyMemeverse {
        require(!_isTransferable, "Already enable transfer");
        _isTransferable = true;
    }

    function mint(address account, uint256 amount) external override onlyMemeverse {
        _mint(account, amount);

        if (_maxSupply != 0 && _totalSupply > _maxSupply) {
            revert MemeTokenExceedsMaxSupply();
        }
    }

    function burn(address account, uint256 value) external override returns (bool) {
        require(msg.sender == _reserveFundManager, "Only reserveFundManager");
        require(balanceOf(account) >= value, "Insufficient balance");
        _burn(account, value);
        return true;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function setAttribute(string calldata attributeName, bytes calldata data) external override onlyMemeverse {
        require(data.length < 257, "Data too long");
        _attributes[attributeName] = data;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        if (_isTransferable) {
            _update(from, to, value);
        } else {
            revert TransferNotStart();
        }
    }

    function _update(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

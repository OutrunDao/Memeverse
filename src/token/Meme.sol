// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IMeme.sol";
import "../blast/GasManagerable.sol";

/**
 * @title Meme token
 */
contract Meme is IMeme, Ownable, GasManagerable {
    uint256 internal constant DAY = 24 * 3600;
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    uint256 public maxSupply; // if 0, unlimit
    address public memeverse;
    address public reserveFundManager;
    bool public isTransferable;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;
    // Description, Twitter, Telegram, Discord, Website and more. Max length = 256
    mapping(string name => bytes) public attributes;  // Additional attributes

    error MemeTokenExceedsMaxSupply();
    error TransferNotStart();

    modifier onlyMemeverse() {
        require(msg.sender == memeverse, "Only memeverse");
        _;
    }

    constructor(
        string memory _name, 
        string memory _symbol,
        uint8 _decimals, 
        uint256 _maxSupply,
        address _memeverse,
        address _reserveFundManager,
        address _owner
    ) Ownable(_owner) GasManagerable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        maxSupply = _maxSupply;
        memeverse = _memeverse;
        reserveFundManager = _reserveFundManager;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    function enableTransfer() external override onlyMemeverse {
        require(!isTransferable, "Already enable transfer");
        isTransferable = true;
    }

    function setAttribute(string calldata attributeName, bytes calldata data) external override onlyOwner {
        require(data.length < 257, "Data too long");
        attributes[attributeName] = data;
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
            revert TransferNotStart();
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
            revert TransferNotStart();
        }

        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function mint(address account, uint256 amount) external override onlyMemeverse {
        _mint(account, amount);

        uint256 _maxSupply = maxSupply;
        if (_maxSupply != 0 && totalSupply > _maxSupply) {
            revert MemeTokenExceedsMaxSupply();
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

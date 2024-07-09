//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

library OutswapV1Library02 {
    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "OutswapV1Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "OutswapV1Library: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            /* bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(OutswapV1Pair).creationCode, abi.encode(gasManager))); */
                            hex"d79ed2f68b5aeda6137657827786887c38c6283b2e9865d49f0f77e0f21d17bf" // 1% init code hash
                        )
                    )
                )
            )
        );
    }
}

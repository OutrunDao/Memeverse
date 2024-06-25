pragma solidity ^0.8.24;

library FixedPoint128 {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    struct uq128x128 {
        uint256 value;
    }

    function fromUInt(uint256 x) internal pure returns (uq128x128 memory) {
        return uq128x128(x * Q128);
    }

    function toUInt(uq128x128 memory x) internal pure returns (uint256) {
        return x.value / Q128;
    }

    function add(uq128x128 memory a, uq128x128 memory b) internal pure returns (uq128x128 memory) {
        return uq128x128(a.value + b.value);
    }

    function mul(uq128x128 memory a, uq128x128 memory b) internal pure returns (uq128x128 memory) {
        uint256 result = (a.value * b.value) / Q128;
        require(result <= type(uint256).max, "FixedPoint128: multiplication overflow");
        return uq128x128(result);
    }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Testing Libraries
import {Test} from "forge-std/Test.sol";
// import {console2} from "forge-std/console2.sol";

// ECIES
import {Point, ECIES} from "src/lib/ECIES.sol";

contract ECIESisValidTest is Test {
    // [X] when the public key is not on the curve y^2 = x^3 + 3
    //      [X] it returns false
    // [X] when the public key is the generator point (1, 2)
    //      [X] it returns false
    // [X] when the public key is the point at infinity (0, 0)
    //      [X] it returns false
    // [X] when the public key x coordinate is greater than or equal to the field modulus
    //      [X] it returns false
    // [X] when the public key y coordinate is greater than or equal to the field modulus
    //      [X] it returns false
    // [X] when the public key is valid
    //      [X] it returns true

    uint256 public constant FIELD_MODULUS =
        21_888_242_871_839_275_222_246_405_745_257_275_088_548_364_400_416_034_343_698_204_186_575_808_495_617;

    // =========== MODIFIERS =========== //

    modifier whenNotOnCurve(uint256 x, uint256 y) {
        uint256 lhs;
        uint256 rhs;
        assembly {
            lhs := mulmod(y, y, FIELD_MODULUS)
            rhs := addmod(mulmod(x, mulmod(x, x, FIELD_MODULUS), FIELD_MODULUS), 3, FIELD_MODULUS)
        }
        if (lhs == rhs) return;
        _;
    }

    modifier whenOnCurve(uint256 x, uint256 y) {
        uint256 lhs;
        uint256 rhs;
        assembly {
            lhs := mulmod(y, y, FIELD_MODULUS)
            rhs := addmod(mulmod(x, mulmod(x, x, FIELD_MODULUS), FIELD_MODULUS), 3, FIELD_MODULUS)
        }
        if (lhs != rhs) return;
        _;
    }

    modifier whenNotGeneratorPoint(uint256 x, uint256 y) {
        if (x == 1 && y == 2) return;
        _;
    }

    modifier whenNotPointAtInfinity(uint256 x, uint256 y) {
        if (x == 0 && y == 0) return;
        _;
    }

    modifier whenXLessThanFieldModulus(uint256 x) {
        if (x >= FIELD_MODULUS) return;
        _;
    }

    modifier whenYLessThanFieldModulus(uint256 y) {
        if (y >= FIELD_MODULUS) return;
        _;
    }

    modifier whenXGreaterThanOrEqualToFieldModulus(uint256 x) {
        if (x < FIELD_MODULUS) return;
        _;
    }

    modifier whenYGreaterThanOrEqualToFieldModulus(uint256 y) {
        if (y < FIELD_MODULUS) return;
        _;
    }

    // =========== TESTS =========== //

    function testFuzz_invalid_whenNotOnCurve_whenBothLess(
        uint256 x,
        uint256 y
    ) public whenNotOnCurve(x, y) whenXLessThanFieldModulus(x) whenYLessThanFieldModulus(y) {
        Point memory p = Point(x, y);
        assertFalse(ECIES.isValid(p));
    }

    function testFuzz_invalid_whenNotOnCurve_whenXGreater(
        uint256 x,
        uint256 y
    )
        public
        whenNotOnCurve(x, y)
        whenXGreaterThanOrEqualToFieldModulus(x)
        whenYLessThanFieldModulus(y)
    {
        Point memory p = Point(x, y);
        assertFalse(ECIES.isValid(p));
    }

    function testFuzz_invalid_whenNotOnCurve_whenYGreater(
        uint256 x,
        uint256 y
    )
        public
        whenNotOnCurve(x, y)
        whenXLessThanFieldModulus(x)
        whenYGreaterThanOrEqualToFieldModulus(y)
    {
        Point memory p = Point(x, y);
        assertFalse(ECIES.isValid(p));
    }

    function testFuzz_invalid_whenNotOnCurve_whenBothGreater(
        uint256 x,
        uint256 y
    )
        public
        whenNotOnCurve(x, y)
        whenXGreaterThanOrEqualToFieldModulus(x)
        whenYGreaterThanOrEqualToFieldModulus(y)
    {
        Point memory p = Point(x, y);
        assertFalse(ECIES.isValid(p));
    }

    function test_invalid_whenGeneratorPoint() public {
        Point memory p = Point(1, 2);
        assertFalse(ECIES.isValid(p));
    }

    function test_invalid_whenPointAtInfinity() public {
        Point memory p = Point(0, 0);
        assertFalse(ECIES.isValid(p));
    }

    function testFuzz_invalid_whenOnCurve_whenNotGeneratorPoint_whenNotPointAtInfinity_whenXGreater(
        uint256 x,
        uint256 y
    )
        public
        whenOnCurve(x, y)
        whenNotGeneratorPoint(x, y)
        whenNotPointAtInfinity(x, y)
        whenXGreaterThanOrEqualToFieldModulus(x)
        whenYLessThanFieldModulus(y)
    {
        Point memory p = Point(x, y);
        assertFalse(ECIES.isValid(p));
    }

    function testFuzz_invalid_whenOnCurve_whenNotGeneratorPoint_whenNotPointAtInfinity_whenYGreater(
        uint256 x,
        uint256 y
    )
        public
        whenOnCurve(x, y)
        whenNotGeneratorPoint(x, y)
        whenNotPointAtInfinity(x, y)
        whenXLessThanFieldModulus(x)
        whenYGreaterThanOrEqualToFieldModulus(y)
    {
        Point memory p = Point(x, y);
        assertFalse(ECIES.isValid(p));
    }

    function testFuzz_invalid_whenOnCurve_whenNotGeneratorPoint_whenNotPointAtInfinity_whenBothGreater(
        uint256 x,
        uint256 y
    )
        public
        whenOnCurve(x, y)
        whenNotGeneratorPoint(x, y)
        whenNotPointAtInfinity(x, y)
        whenXGreaterThanOrEqualToFieldModulus(x)
        whenYGreaterThanOrEqualToFieldModulus(y)
    {
        Point memory p = Point(x, y);
        assertFalse(ECIES.isValid(p));
    }

    function testFuzz_valid_whenOnCurve_whenNotGeneratorPoint_whenNotPointAtInfinity_whenBothLess(
        uint256 x,
        uint256 y
    )
        public
        whenOnCurve(x, y)
        whenNotGeneratorPoint(x, y)
        whenNotPointAtInfinity(x, y)
        whenXLessThanFieldModulus(x)
        whenYLessThanFieldModulus(y)
    {
        Point memory p = Point(x, y);
        assertTrue(ECIES.isValid(p));
    }
}

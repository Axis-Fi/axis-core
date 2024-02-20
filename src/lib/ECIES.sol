// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

struct Point {
    uint256 x;
    uint256 y;
}

/// @notice This library implements a simplified version of the Elliptic Curve Integrated Encryption Scheme (ECIES) using the alt_bn128 curve.
/// @dev    The alt_bn128 curve is used since there are precompiled contracts for point addition, calar multiplication, and pairing that make it gas efficient.
///         XOR encryption is used with the derived symmetric key, which is not as secure as modern encryption algorithms, but is simple and cheap to implement.
///         We use keccak256 as the key derivation function, which, as a hash-based key derivation function, is susceptible to dictionary attacks, but is sufficient for our purposes.
///         As a result of the relative weakness of the symmetric encryption and key derivation function, we rely on the security of the elliptic curve to hide the shared secret.
///         Recent advances in attacks on the alt_bn128 curve have reduced the expected security of the curve to ~98 bits.
///         Therefore, this implementation should not be used to secure value directly. It can be used to secure data which, if compromised, would not be catastrophic.
///         Inspired by:
///         - https://cryptobook.nakov.com/asymmetric-key-ciphers/ecies-public-key-encryption
///         - https://billatnapier.medium.com/how-do-i-implement-symmetric-key-encryption-in-ethereum-14afffff6e42
///         - https://github.com/PhilippSchindler/EthDKG/blob/master/contracts/ETHDKG.sol
/// @author Oighty
library ECIES {
    uint256 constant GROUP_ORDER =
        21_888_242_871_839_275_222_246_405_745_257_275_088_548_364_400_416_034_343_698_204_186_575_808_495_617;
    uint256 constant FIELD_MODULUS =
        21_888_242_871_839_275_222_246_405_745_257_275_088_696_311_157_297_823_662_689_037_894_645_226_208_583;

    /// @notice We use a hash function to derive a symmetric key from the shared secret and a provided salt.
    /// @dev This is not as secure as modern key derivation functions, since hash-based keys are susceptible to dictionary attacks.
    ///      However, it is simple and cheap to implement, and is sufficient for our purposes.
    ///      The salt prevents duplication even if a shared secret is reused.
    function deriveSymmetricKey(uint256 sharedSecret_, bytes32 s1_) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(sharedSecret_, s1_)));
    }

    /// @notice Recover the shared secret as the x-coordinate of the EC point computed as the multiplication of the ciphertext public key and the private key.
    function recoverSharedSecret(
        Point memory ciphertextPubKey_,
        bytes32 privateKey_
    ) public view returns (uint256) {
        if (!isOnBn128(ciphertextPubKey_)) revert("Invalid public key.");

        Point memory p = _ecMul(ciphertextPubKey_, uint256(privateKey_));

        return p.x;
    }

    /// @notice Decrypt a message using the provided ciphertext, ciphertext public key, and private key from the recipient.
    /// @dev    We use XOR encryption. The security of the algorithm relies on the security of the elliptic curve to hide the shared secret.
    /// @param ciphertext_ - The encrypted message.
    /// @param ciphertextPubKey_ - The ciphertext public key provided by the sender.
    /// @param privateKey_ - The private key of the recipient.
    /// @param salt_ - A salt used to derive the symmetric key from the shared secret. Ensures that the symmetric key is unique even if the shared secret is reused.
    function decrypt(
        uint256 ciphertext_,
        Point memory ciphertextPubKey_,
        bytes32 privateKey_,
        bytes32 salt_
    ) public view returns (uint256) {
        uint256 sharedSecret = recoverSharedSecret(ciphertextPubKey_, privateKey_);

        uint256 symmetricKey = deriveSymmetricKey(sharedSecret, salt_);

        return ciphertext_ ^ symmetricKey;
    }

    /// @notice Calculate the point on the generator curve that corresponds to the provided private key. This is used as the public key.
    /// @param generator_ - The generator point of the alt_bn128 curve.
    /// @param privateKey_ - The private key to calculate the public key for.
    function calcPubKey(
        Point memory generator_,
        bytes32 privateKey_
    ) public view returns (Point memory) {
        return _ecMul(generator_, uint256(privateKey_));
    }

    function _ecMul(Point memory p, uint256 scalar) private view returns (Point memory p2) {
        (bool success, bytes memory output) =
            address(0x07).staticcall{gas: 6000}(abi.encode(p.x, p.y, scalar));

        if (!success || output.length == 0) revert("ecMul failed.");

        p2 = abi.decode(output, (Point));
    }

    /// @notice Checks whether a point is on the alt_bn128 curve.
    /// @param  p - The point to check (consists of x and y coordinates).
    function isOnBn128(Point memory p) public pure returns (bool) {
        // check if the provided point is on the bn128 curve (y**2 = x**3 + 3)
        return _fieldmul(p.y, p.y) == _fieldadd(_fieldmul(p.x, _fieldmul(p.x, p.x)), 3);
    }

    function _fieldmul(uint256 a, uint256 b) private pure returns (uint256 c) {
        assembly {
            c := mulmod(a, b, FIELD_MODULUS)
        }
    }

    function _fieldadd(uint256 a, uint256 b) private pure returns (uint256 c) {
        assembly {
            c := addmod(a, b, FIELD_MODULUS)
        }
    }
}
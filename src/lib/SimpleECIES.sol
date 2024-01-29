// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

struct Point {
    uint256 x;
    uint256 y;
}

library SimpleECIES {

    uint256 constant GROUP_ORDER   = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 constant FIELD_MODULUS = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /// @notice We use a hash function to derive a symmetric key from the shared secret and a provided salt.
    /// @dev This is not as secure as modern key derivation functions, since hash-based keys are susceptible to dictionary attacks.
    ///      However, it is simple and cheap to implement, and is sufficient for our purposes. 
    ///      The salt prevents duplication even if a shared secret is reused.
    function deriveSymmetricKey(uint256 sharedSecret_, uint256 s1_) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(sharedSecret_, s1_)));
    }

    /// @notice Recover the shared secret as the x-coordinate of the EC point computed as the multiplication of the ciphertext public key and the private key.
    function recoverSharedSecret(Point memory ciphertextPubKey_, bytes32 privateKey_) public view returns (uint256) {
        if (!isOnBn128(ciphertextPubKey_)) revert("Invalid public key.");

        Point memory p = _ecMul(ciphertextPubKey_, uint256(privateKey_));

        return p.x;
    }

    /// @notice Decrypt a message using the provided ciphertext, ciphertext public key, and private key from the recipient.
    /// @dev    We use XOR encryption. The security of the algorithm relies on the security of the elliptic curve to hide the shared secret.
    function decrypt(uint256 ciphertext_, Point memory ciphertextPubKey_, bytes32 privateKey_, uint256 salt_) public view returns (uint256) {
        uint256 sharedSecret = recoverSharedSecret(ciphertextPubKey_, privateKey_);

        uint256 symmetricKey = deriveSymmetricKey(sharedSecret, salt_);

        return ciphertext_ ^ symmetricKey;
    }

    function calcPubKey(Point memory generator_, bytes32 privateKey_) public view returns (Point memory) {
        return _ecMul(generator_, uint256(privateKey_));
    }

    function _ecMul(Point memory p, uint256 scalar) private view returns (Point memory p2) {
        (bool success, bytes memory output) = address(0x07).staticcall{gas: 6000}(
            abi.encode(p.x, p.y, scalar)
        );

        if (!success || output.length == 0) revert("ecMul failed.");

        p2 = abi.decode(output, (Point));
    }

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

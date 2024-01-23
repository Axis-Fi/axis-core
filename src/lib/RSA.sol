// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

/// @title RSA-OAEP Encryption Library
/// @notice Library that implements RSA encryption and decryption using EME-OAEP encoding scheme as defined in PKCS#1: RSA Cryptography Specification Version 2.2
/// @author Oighty
// TODO Need to add tests for this library
library RSAOAEP {
    function modexp(
        bytes memory base,
        bytes memory exponent,
        bytes memory modulus
    ) public view returns (bytes memory) {
        (bool success, bytes memory output) = address(0x05).staticcall(
            abi.encodePacked(base.length, exponent.length, modulus.length, base, exponent, modulus)
        );

        if (!success) revert("modexp failed.");

        return output;
    }

    function decrypt(
        bytes memory cipherText,
        bytes memory d,
        bytes memory n,
        bytes memory label
    ) internal view returns (bytes memory message, bytes32 seed) {
        // Implements 7.1.2 RSAES-OAEP-DECRYPT as defined in RFC8017: https://www.rfc-editor.org/rfc/rfc8017
        // Error messages are intentionally vague to prevent oracle attacks

        // 1. Input length validation
        // 1. a. If the length of L is greater than the input limitation
        //       for the hash function, output "decryption error" and stop.
        // SHA2-256 has a limit of (2^64 - 1) / 8 bytes, which is far more than can be held in memory in the EVM.

        // 1. b. If the length of the ciphertext is not the length of the private key,
        //       output "decryption error" and stop.
        // 1. c. Private key must be greater than twice the length of the hash function output plus 2 bytes
        uint256 cLen = cipherText.length;
        {
            uint256 dLen = d.length;
            if (cLen != dLen || dLen < 66) revert("decryption error"); // 66 = 2*32 + 2 where 32 is the length of the output of the sha256 hash function
        }

        // 2. RSA decryption
        // 2. a. Convert ciphertext to integer (can skip since modexp does this for us)
        // 2. b. Apply modexp decryption using the private key and modulus from the public key
        // 2. c. Convert result from integer to bytes (can skip since modexp does this for us)
        bytes memory encoded = modexp(cipherText, d, n);
        // Require that the encoded length be the same as the ciphertext length
        if (cLen != encoded.length) revert("decryption error");

        // 3. EME-OAEP decoding
        // 3. a. Calculate the hash of the provided label
        bytes32 lhash = sha256(label);

        // 3. b. Separate encoded message into Y (1 byte) | maskedSeed (32 bytes) | maskedDB (cLen - 32 - 1)
        bytes1 y = bytes1(encoded);
        bytes32 maskedSeed;
        uint256 words = (cLen - 33) / 32 + ((cLen - 33) % 32 == 0 ? 0 : 1);
        bytes memory maskedDb = new bytes(cLen - 33);

        assembly {
            // Load a word from the encoded string starting at the 2nd byte (also have to account for length stored in first slot)
            maskedSeed := mload(add(encoded, 0x21))

            // Store the remaining bytes into the maskedDb
            for { let i := 0 } lt(i, words) { i := add(i, 1) } {
                mstore(
                    add(add(maskedDb, 0x20), mul(i, 0x20)),
                    mload(add(add(encoded, 0x41), mul(i, 0x20)))
                )
            }
        }

        // 3. c. Calculate seed mask
        // 3. d. Calculate seed
        {
            bytes32 seedMask = bytes32(_mgf(maskedDb, 32));
            seed = maskedSeed ^ seedMask;
        }

        // 3. e. Calculate DB mask
        bytes memory dbMask = _mgf(abi.encodePacked(seed), cLen - 33);

        // 3. f. Calculate DB
        bytes memory db = _xor(maskedDb, dbMask);
        uint256 dbWords = db.length / 32 + db.length % 32 == 0 ? 0 : 1;

        // 3. g. Separate DB into an octet string lHash' of length hLen, a
        //   (possibly empty) padding string PS consisting of octets
        //   with hexadecimal value 0x00, and a message M as

        //      DB = lHash' || PS || 0x01 || M.

        //   If there is no octet with hexadecimal value 0x01 to
        //   separate PS from M, if lHash does not equal lHash', or if
        //   Y is nonzero, output "decryption error" and stop.
        bytes32 recoveredHash = bytes32(db);
        bytes1 one;
        assembly {
            // Iterate over bytes after the label hash until hitting a non-zero byte
            // Skip the first word since it is the recovered hash
            // Identify the start index of the message within the db byte string
            let m := 0
            for { let w := 1 } lt(w, dbWords) { w := add(w, 1) } {
                let word := mload(add(db, add(0x20, mul(w, 0x20))))
                // Iterate over bytes in the word
                for { let i := 0 } lt(i, 0x20) { i := 0x20 } {
                    switch byte(i, word)
                    case 0x00 { continue }
                    case 0x01 {
                        one := 0x01
                        m := add(add(i, 1), mul(sub(w, 1), 0x20))
                        break
                    }
                    default {
                        // Non-zero entry found before 0x01, revert
                        let p := mload(0x40)
                        mstore(p, "decryption error")
                        revert(p, 0x10)
                    }
                }

                // If the 0x01 byte has been found, exit the outer loop
                switch one
                case 0x01 { break }
            }

            // Check that m is not zero, otherwise revert
            switch m
            case 0x00 {
                let p := mload(0x40)
                mstore(p, "decryption error")
                revert(p, 0x10)
            }

            // Copy the message from the db bytes string
            let len := sub(mload(db), m)
            let wrds := div(len, 0x20)
            switch mod(len, 0x20)
            case 0x00 {}
            default { wrds := add(wrds, 1) }
            for { let w := 0 } lt(w, wrds) { w := add(w, 1) } {
                let c := mload(add(db, add(m, mul(w, 0x20))))
                let i := add(message, mul(w, 0x20))
                mstore(i, c)
            }
        }

        if (one != 0x01 || lhash != recoveredHash || y != 0x00) revert("decryption error");

        // 4. Return the message and seed used for encryption
    }

    function encrypt(
        bytes memory message,
        bytes memory label,
        bytes memory e,
        bytes memory n,
        uint256 seed
    ) internal view returns (bytes memory) {
        // Implements 7.1.1. RSAES-OAEP-ENCRYPT as defined in RFC8017: https://www.rfc-editor.org/rfc/rfc8017

        // 1. a. Check that the label length is less than the max for sha256
        // This check is probably not necessary given that the EVM cannot store this much data in memory.
        if (label.length > type(uint64).max / 8) revert("label too long");

        // 1. b. Check length of message against OAEP equation
        uint256 mLen = message.length;
        uint256 nLen = n.length;
        if (mLen > nLen - 66) revert("message too long"); // 66 = 2 * 32 - 2 where 32 is the output size of the hash function in bytes

        // 2. a. Hash the label
        bytes32 labelHash = sha256(label);

        // 2. b. Generate padding string
        bytes memory padding = new bytes(nLen - 66 - mLen);

        // 2. c. Concatenate inputs into data block for encoding
        // DB = labelHash | padding | 0x01 | message
        bytes memory db = abi.encodePacked(labelHash, padding, bytes1(0x01), message);

        // 2. d. Generate random byte string the same length as the hash function
        bytes32 rand = sha256(abi.encodePacked(seed));

        // 2. e.  Let dbMask = MGF(seed, k - hLen - 1).
        bytes memory dbMask = _mgf(abi.encodePacked(rand), nLen - 33);

        // 2. f.  Let maskedDB = DB \xor dbMask.
        bytes memory maskedDb = _xor(db, dbMask);

        // 2. g.  Let seedMask = MGF(maskedDB, hLen).
        bytes32 seedMask = bytes32(_mgf(maskedDb, 32));

        // 2. h.  Let maskedSeed = seed \xor seedMask.
        bytes32 maskedSeed = rand ^ seedMask;

        // 2. i.  Concatenate a single octet with hexadecimal value 0x00,
        //       maskedSeed, and maskedDB to form an encoded message EM of
        //       length k octets as
        //       EM = 0x00 || maskedSeed || maskedDB.
        bytes memory encoded = abi.encodePacked(bytes1(0x00), maskedSeed, maskedDb);

        // 3.  RSA encryption:
        //    a.  Convert the encoded message EM to an integer message
        //        representative m (see Section 4.2):
        //            m = OS2IP (EM).
        //    b.  Apply the RSAEP encryption primitive (Section 5.1.1) to
        //        the RSA public key (n, e) and the message representative m
        //        to produce an integer ciphertext representative c:
        //            c = RSAEP ((n, e), m).
        //    c.  Convert the ciphertext representative c to a ciphertext C
        //        of length k octets (see Section 4.1):
        //            C = I2OSP (c, k).
        //   4.  Output the ciphertext C.
        return modexp(encoded, e, n);
    }

    function _mgf(bytes memory seed, uint256 maskLen) internal pure returns (bytes memory) {
        // Implements 8.2.1 MGF1 as defined in RFC8017: https://www.rfc-editor.org/rfc/rfc8017

        // 1. Check that the mask length is not greater than 2^32 * hash length (32 bytes in this case)
        if (maskLen > 2 ** 32 * 32) revert("mask too long");

        // 2. Let T be the empty octet string
        // Need to initialize to the maskLen here since we cannot resize
        bytes memory t = new bytes(maskLen);

        // 3.  For counter from 0 to \ceil (maskLen / hLen) - 1, do the
        // following:
        //    A.  Convert counter to an octet string C of length 4 octets (see
        //        Section 4.1):
        //           C = I2OSP (counter, 4) .
        //    B.  Concatenate the hash of the seed mgfSeed and C to the octet
        //        string T:
        //           T = T || Hash(mgfSeed || C) .

        uint256 count = maskLen / 32 + (maskLen % 32 == 0 ? 0 : 1);
        for (uint256 c; c < count; c++) {
            bytes32 h = sha256(abi.encodePacked(seed, c));
            assembly {
                let p := add(add(t, 0x20), mul(c, 0x20))
                mstore(p, h)
            }
        }

        // 4.  Output the leading maskLen octets of T as the octet string mask.
        return t;
    }

    function _xor(bytes memory first, bytes memory second) internal pure returns (bytes memory) {
        uint256 fLen = first.length;
        uint256 sLen = second.length;
        if (fLen != sLen) revert("xor: different lengths");

        uint256 words = (fLen / 32) + (fLen % 32 == 0 ? 0 : 1);
        bytes memory result = new bytes(fLen);

        // Iterate through words in the byte strings and xor them one at a time, storing the result
        assembly {
            for { let i := 0 } lt(i, words) { i := add(i, 1) } {
                let f := mload(add(first, mul(i, 0x20)))
                let s := mload(add(second, mul(i, 0x20)))
                mstore(add(add(result, 0x20), mul(i, 0x20)), xor(f, s))
            }
        }

        return result;
    }
}

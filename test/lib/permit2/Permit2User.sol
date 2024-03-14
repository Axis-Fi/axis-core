/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";

import {IPermit2} from "src/lib/permit2/interfaces/IPermit2.sol";
import {Permit2Clone} from "test/lib/permit2/Permit2Clone.sol";

/// @title  Permit2User
/// @notice Helper functions for Permit2
///         Largely lifted from https://github.com/dragonfly-xyz/useful-solidity-patterns/blob/main/test/Permit2Vault.t.sol
contract Permit2User is Test {
    bytes32 internal constant _TOKEN_PERMISSIONS_TYPEHASH =
        keccak256("TokenPermissions(address token,uint256 amount)");
    bytes32 internal constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    Permit2Clone internal _permit2 = new Permit2Clone();
    address internal _permit2Address = address(_permit2);

    // Generate a random uint256
    function _getRandomUint256() internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encode(
                    // solhint-disable-next-line avoid-tx-origin
                    tx.origin,
                    block.number,
                    block.timestamp,
                    block.coinbase,
                    address(this).codehash,
                    gasleft()
                )
            )
        );
    }

    // Generate a signature for a permit message.
    function _signPermit(
        address token_,
        uint256 amount_,
        uint256 nonce_,
        uint256 deadline_,
        address spender,
        uint256 signerKey
    ) internal view returns (bytes memory sig) {
        IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({token: token_, amount: amount_}),
            nonce: nonce_,
            deadline: deadline_
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _getEIP712Hash(permit, spender));
        return abi.encodePacked(r, s, v);
    }

    // Compute the EIP712 hash of the permit object.
    // Normally this would be implemented off-chain.
    function _getEIP712Hash(
        IPermit2.PermitTransferFrom memory permit,
        address spender
    ) internal view returns (bytes32 h) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _permit2.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        _PERMIT_TRANSFER_FROM_TYPEHASH,
                        keccak256(
                            abi.encode(
                                _TOKEN_PERMISSIONS_TYPEHASH,
                                permit.permitted.token,
                                permit.permitted.amount
                            )
                        ),
                        spender,
                        permit.nonce,
                        permit.deadline
                    )
                )
            )
        );
    }
}

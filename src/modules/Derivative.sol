// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

import {ERC6909} from "@solmate-6.7.0/tokens/ERC6909.sol";
import {ERC6909Metadata} from "../lib/ERC6909Metadata.sol";
import {Module} from "./Modules.sol";
import {IDerivative} from "../interfaces/modules/IDerivative.sol";

/// @title  DerivativeModule
/// @notice The DerivativeModule contract is an abstract contract that provides derivative functionality for the AuctionHouse.
/// @dev    This contract is intended to be inherited by derivative modules that are used in the AuctionHouse.
abstract contract DerivativeModule is IDerivative, ERC6909, ERC6909Metadata, Module {
    // ========== STATE VARIABLES ========== //

    /// @inheritdoc IDerivative
    mapping(uint256 tokenId => Token metadata) public tokenMetadata;

    // ========== DERIVATIVE INFORMATION ========== //

    /// @inheritdoc IDerivative
    function getTokenMetadata(
        uint256 tokenId
    ) external view virtual returns (Token memory) {
        return tokenMetadata[tokenId];
    }

    // ========== ERC6909 TOKEN SUPPLY EXTENSION ========== //

    /// @inheritdoc ERC6909Metadata
    function totalSupply(
        uint256 tokenId
    ) public view virtual override returns (uint256) {
        return tokenMetadata[tokenId].supply;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {ERC6909} from "lib/solmate/src/tokens/ERC6909.sol";
import {ERC6909Metadata} from "src/lib/ERC6909Metadata.sol";
import {Module} from "src/modules/Modules.sol";

abstract contract Derivative {
    // ========== ERRORS ========== //

    error Derivative_NotImplemented();

    // ========== EVENTS ========== //

    // ========== DATA STRUCTURES ========== //

    /// @notice     Metadata for a derivative token
    ///
    /// @param      exists          True if the token has been deployed
    /// @param      wrapped         True if an ERC20-wrapped derivative has been deployed
    /// @param      underlyingToken The address of the underlying token
    /// @param      data            Implementation-specific data
    struct Token {
        bool exists;
        address wrapped;
        address underlyingToken;
        bytes data;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The metadata for each derivative token
    mapping(uint256 tokenId => Token metadata) public tokenMetadata;

    // ========== DERIVATIVE MANAGEMENT ========== //

    /// @notice     Deploy a new derivative token. Optionally, deploys an ERC20 wrapper for composability.
    ///
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             ABI-encoded parameters for the derivative to be created
    /// @param      wrapped_            Whether (true) or not (false) the derivative should be wrapped in an ERC20 token for composability
    /// @return     tokenId_            The ID of the newly created derivative token
    /// @return     wrappedAddress_     The address of the ERC20 wrapped derivative token, if wrapped_ is true, otherwise, it's the zero address.
    function deploy(
        address underlyingToken_,
        bytes memory params_,
        bool wrapped_
    ) external virtual returns (uint256 tokenId_, address wrappedAddress_);

    /// @notice     Mint new derivative tokens.
    /// @notice     Deploys the derivative token if it does not already exist.
    /// @notice     The module is expected to transfer the collateral token to itself.
    ///
    /// @param      to_                 The address to mint the derivative tokens to
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             ABI-encoded parameters for the derivative to be created
    /// @param      amount_             The amount of derivative tokens to create
    /// @param      wrapped_            Whether (true) or not (false) the derivative should be wrapped in an ERC20 token for composability
    /// @return     tokenId_            The ID of the newly created derivative token
    /// @return     wrappedAddress_     The address of the ERC20 wrapped derivative token, if wrapped_ is true, otherwise, it's the zero address.
    /// @return     amountCreated_      The amount of derivative tokens created
    function mint(
        address to_,
        address underlyingToken_,
        bytes memory params_,
        uint256 amount_,
        bool wrapped_
    )
        external
        virtual
        returns (uint256 tokenId_, address wrappedAddress_, uint256 amountCreated_);

    /// @notice     Mint new derivative tokens for a specific token ID
    ///
    /// @param      to_                 The address to mint the derivative tokens to
    /// @param      tokenId_            The ID of the derivative token
    /// @param      amount_             The amount of derivative tokens to create
    /// @param      wrapped_            Whether (true) or not (false) the derivative should be wrapped in an ERC20 token for composability
    /// @return     tokenId_            The ID of the derivative token
    /// @return     wrappedAddress_     The address of the ERC20 wrapped derivative token, if wrapped_ is true, otherwise, it's the zero address.
    /// @return     amountCreated_      The amount of derivative tokens created
    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) external virtual returns (uint256, address, uint256);

    /// @notice     Redeem all available derivative tokens for underlying collateral
    ///
    /// @param      tokenId_    The ID of the derivative token to redeem
    function redeemMax(uint256 tokenId_) external virtual;

    /// @notice     Redeem derivative tokens for underlying collateral
    ///
    /// @param      tokenId_    The ID of the derivative token to redeem
    /// @param      amount_     The amount of derivative tokens to redeem
    function redeem(uint256 tokenId_, uint256 amount_) external virtual;

    /// @notice     Determines the amount of redeemable tokens for a given derivative token
    ///
    /// @param      owner_      The owner of the derivative token
    /// @param      tokenId_    The ID of the derivative token
    /// @return     amount_     The amount of redeemable tokens
    function redeemable(address owner_, uint256 tokenId_) external view virtual returns (uint256);

    /// @notice     Exercise a conversion of the derivative token per the specific implementation logic
    /// @dev        Used for options or other derivatives with convertible options, e.g. Rage vesting.
    ///
    /// @param      tokenId_    The ID of the derivative token to exercise
    /// @param      amount      The amount of derivative tokens to exercise
    function exercise(uint256 tokenId_, uint256 amount) external virtual;

    /// @notice     Reclaim posted collateral for a derivative token which can no longer be exercised
    /// @notice     Access controlled: only callable by the derivative issuer via the auction house.
    ///
    /// @param      tokenId_    The ID of the derivative token to reclaim
    function reclaim(uint256 tokenId_) external virtual;

    /// @notice     Transforms an existing derivative issued by this contract into something else. Derivative is burned and collateral sent to the auction house.
    /// @notice     Access controlled: only callable by the auction house.
    ///
    /// @param      tokenId_    The ID of the derivative token to transform
    /// @param      from_       The address of the owner of the derivative token
    /// @param      amount_     The amount of derivative tokens to transform
    function transform(uint256 tokenId_, address from_, uint256 amount_) external virtual;

    /// @notice     Wrap an existing derivative into an ERC20 token for composability
    ///             Deploys the ERC20 wrapper if it does not already exist
    ///
    /// @param      tokenId_    The ID of the derivative token to wrap
    /// @param      amount_     The amount of derivative tokens to wrap
    function wrap(uint256 tokenId_, uint256 amount_) external virtual;

    /// @notice     Unwrap an ERC20 derivative token into the underlying ERC6909 derivative
    ///
    /// @param      tokenId_    The ID of the derivative token to unwrap
    /// @param      amount_     The amount of derivative tokens to unwrap
    function unwrap(uint256 tokenId_, uint256 amount_) external virtual;

    /// @notice     Validate derivative params for the specific implementation
    ///             The parameters should be the same as what is passed into `deploy()` or `mint()`
    ///
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             The params to validate
    /// @return     bool                Whether or not the params are valid
    function validate(
        address underlyingToken_,
        bytes memory params_
    ) external view virtual returns (bool);

    // ========== DERIVATIVE INFORMATION ========== //

    // TODO view function to format implementation specific token data correctly and return to user

    function exerciseCost(
        bytes memory data,
        uint256 amount
    ) external view virtual returns (uint256);

    function convertsTo(
        bytes memory data,
        uint256 amount
    ) external view virtual returns (uint256);

    /// @notice     Compute a unique token ID, given the parameters for the derivative
    ///
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             The parameters for the derivative
    /// @return     tokenId_            The unique token ID
    function computeId(
        address underlyingToken_,
        bytes memory params_
    ) external pure virtual returns (uint256);

    /// @notice     Get the metadata for a derivative token
    ///
    /// @param      tokenId     The ID of the derivative token
    /// @return     Token       The metadata for the derivative token
    function getTokenMetadata(uint256 tokenId) external view virtual returns (Token memory) {
        return tokenMetadata[tokenId];
    }
}

abstract contract DerivativeModule is Derivative, ERC6909, ERC6909Metadata, Module {}

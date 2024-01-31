/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Derivative, DerivativeModule} from "src/modules/Derivative.sol";
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

contract LinearVesting is DerivativeModule {
    using SafeTransferLib for ERC20;

    // ========== EVENTS ========== //

    // ========== ERRORS ========== //

    error BrokenInvariant();
    error InsufficientBalance();

    // ========== DATA STRUCTURES ========== //

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting begins
    /// @param      expiry      The timestamp at which the vesting ends
    /// @param      baseToken   The address of the token to vest
    struct VestingData {
        uint48 start;
        uint48 expiry;
        ERC20 baseToken;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     Stores the vesting data for a particular token id
    mapping(uint256 tokenId => VestingData) public vestingData;

    /// @notice     Stores the amount of tokens that have been claimed for a particular token id and owner
    mapping(address owner => mapping(uint256 tokenId => uint256 claimed)) internal claimed;

    // ========== MODULE SETUP ========== //

    constructor(address parent_) Module(parent_) {}

    /// @inheritdoc Module
    function TYPE() public pure override returns (Type) {
        return Type.Derivative;
    }

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("LIV"), 1);
    }

    // TODO
    // [ ] prevent transfer
    // [ ] prevent transferFrom
    // [ ] prevent approve
    // [ ] claim
    // [ ] claimable
    // [ ] wrap
    // [ ] unwrap

    function deploy(
        address underlyingToken_,
        bytes memory params_,
        bool wrapped_
    ) external virtual override returns (uint256 tokenId_, address wrappedAddress_) {}

    function mint(
        address to_,
        address underlyingToken_,
        bytes memory params_,
        uint256 amount_,
        bool wrapped_
    )
        external
        virtual
        override
        returns (uint256 tokenId_, address wrappedAddress_, uint256 amountCreated_)
    {}

    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override returns (uint256, address, uint256) {}

    /// @inheritdoc Derivative
    function redeem(uint256 tokenId_, uint256 amount_, bool wrapped_) external virtual override {
        // Get the redeemable amount
        uint256 redeemableAmount = redeemable(msg.sender, tokenId_);

        // If the redeemable amount is 0, revert
        if (redeemableAmount == 0) revert InsufficientBalance();

        // If the redeemable amount is less than the requested amount, revert
        if (redeemableAmount < amount_) revert InsufficientBalance();

        // Update claimed amount
        claimed[msg.sender][tokenId_] += amount_;

        // Burn the derivative token
        if (wrapped_) {
            // TODO burn wrapped token
            // What does wrapped_ signify here?
        } else {
            _burn(msg.sender, tokenId_, amount_);
        }

        // Transfer the underlying token to the owner
        vestingData[tokenId_].baseToken.safeTransfer(msg.sender, amount_);
    }

    /// @notice     Returns the amount of vested tokens that can be redeemed for the underlying base token
    /// @dev        The redeemable amount is computed as:
    ///             - The amount of tokens that have vested
    ///               - x: number of vestable tokens
    ///               - t: current timestamp
    ///               - s: start timestamp
    ///               - T: end timestamp
    ///               - Vested = x * (t - s) / (T - s)
    ///             - Minus the amount of tokens that have already been redeemed
    ///
    /// @param      owner_      The address of the owner of the derivative token
    /// @param      tokenId_    The ID of the derivative token
    /// @return     uint256     The amount of tokens that can be redeemed
    function redeemable(address owner_, uint256 tokenId_) public view returns (uint256) {
        // Get the vesting data
        VestingData storage data = vestingData[tokenId_];

        // If before the start time, 0
        if (block.timestamp < data.start) return 0;

        // TODO what if there is a wrapped balance?
        uint256 ownerBalance = balanceOf[owner_][tokenId_];
        uint256 claimedBalance = claimed[owner_][tokenId_];
        uint256 totalAmount = ownerBalance + claimedBalance;
        uint256 vested;

        // If after the end time, all tokens are redeemable
        if (block.timestamp >= data.expiry) {
            vested = totalAmount;
        }
        // If before the end time, calculate what has vested already
        else {
            vested = (totalAmount * (block.timestamp - data.start)) / (data.expiry - data.start);
        }

        // Check invariant: cannot have claimed more than vested
        if (vested < claimedBalance) {
            revert BrokenInvariant();
        }

        // Deduct already claimed tokens
        vested -= claimedBalance;

        return vested;
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function exercise(uint256, uint256, bool) external virtual override {
        revert Derivative.Derivative_NotImplemented();
    }

    function reclaim(uint256 tokenId_) external virtual override {}

    function transform(
        uint256 tokenId_,
        address from_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override {}

    function wrap(uint256 tokenId_, uint256 amount_) external virtual override {}

    function unwrap(uint256 tokenId_, uint256 amount_) external virtual override {}

    function validate(bytes memory params_) external view virtual override returns (bool) {}

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function exerciseCost(bytes memory, uint256) external view virtual override returns (uint256) {
        revert Derivative.Derivative_NotImplemented();
    }

    /// @inheritdoc Derivative
    function convertsTo(
        bytes memory data,
        uint256 amount
    ) external view virtual override returns (uint256) {}

    /// @notice     Computes the ID of a derivative token
    /// @dev        The ID is computed as the hash of the parameters and hashed again with the module identifier.
    ///
    /// @param      base_       The address of the underlying token
    /// @param      start_      The timestamp at which the vesting begins
    /// @param      expiry_     The timestamp at which the vesting ends
    /// @return     uint256     The ID of the derivative token
    function _computeId(
        ERC20 base_,
        uint48 start_,
        uint48 expiry_
    ) internal pure returns (uint256) {
        return uint256(
            keccak256(abi.encodePacked(VEECODE(), keccak256(abi.encode(base_, start_, expiry_))))
        );
    }

    /// @inheritdoc Derivative
    function computeId(bytes memory params_) external pure virtual override returns (uint256) {
        // Decode the parameters
        VestingData memory data = abi.decode(params_, (VestingData));

        // Compute the ID
        return _computeId(data.baseToken, data.start, data.expiry);
    }
}

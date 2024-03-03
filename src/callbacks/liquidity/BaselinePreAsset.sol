// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

interface IPreAsset {
    function seed() external returns (uint256);

    function setBAsset(address bAsset_) external;
}

interface IBAsset {
    function baseline() external view returns (address);
}

/// @notice This contract is a replacement PreAsset for a Baseline Market that allows depositing proceeds from a Batch auction directly into Baseline.
/// @dev The contract is the base token that should be auctioned. It provides a pre-asset token that buyers can then use to claim bAssets from after the Baseline Market is deployed.
contract BaselinePreAsset is ERC20, BaseCallback, IPreAsset {

    // ========== ERRORS ========== //

    error Callback_AlreadyComplete();
    error Callback_MissingFunds();
    error PreAsset_AuctionNotComplete();
    error PreAsset_AlreadySeeded();
    error PreAsset_BAssetAlreadySet();
    error PreAsset_BAssetNotSet();
    error PreAsset_NotAuthorized();
    

    // ========== EVENTS ========== //

    event Seeded(uint256 totalReserves);

    // ========== STATE VARIABLES ========== //

    // Baseline Variables
    ERC20 public immutable reserve;
    address public immutable baselineFactory;
    IBAsset public bAsset;

    /// @notice Lot ID of the auction for the baseline market. This callback only supports one lot.
    uint96 public lotId;
    bool public auctionComplete;
    bool public seeded;
    uint256 public capacity;
    uint256 public clearingPrice; // can be used to determine the init parameters of the baseline market

    // ========== CONSTRUCTOR ========== //

    constructor(
        string memory name_,
        string memory symbol_,
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address seller_,
        address reserve_,
        address baselineFactory_
    ) ERC20(name_, symbol_, 18) BaseCallback(auctionHouse_, permissions_, seller_) {
        // Check that the reserve token has 18 decimals
        if (ERC20(reserve_).decimals() != 18) revert Callback_InvalidParams();

        // set immutable variables
        reserve = ERC20(reserve_);
        baselineFactory = baselineFactory_;

        // set lot ID to max uint(96) initially
        lotId = type(uint96).max;
    }

    // ========== CALLBACK FUNCTIONS ========== //

    // CALLBACK PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: false
    // onBid: false
    // onClaimProceeds: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11100111 = 0xE7

    function _onCreate(
        uint96 lotId_,
        address,
        address baseToken_,
        address quoteToken_,
        uint96 capacity_,
        bool prefund_,
        bytes calldata
    ) internal override {
        // Validate the base token is the pre asset (this contract)
        // and the quote token is the reserve
        if (baseToken_ != address(this) || quoteToken_ != address(reserve)) revert Callback_InvalidParams();

        // Validate that prefund is true
        if (!prefund_) revert Callback_InvalidParams();

        // Validate that the lot ID is not already set
        if (lotId != type(uint96).max) revert Callback_InvalidParams();

        // Set the lot ID
        lotId = lotId_;

        // Store the capacity
        capacity = uint256(capacity_);

        // Mint the capacity of preAsset tokens to the auction house
        _mint(msg.sender, capacity_);
    }

    function _onCancel(
        uint96 lotId_,
        uint96 refund_,
        bool prefunded_,
        bytes calldata
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that prefunded is true
        if (!prefunded_) revert Callback_InvalidParams();

        // Burn the refund amount of preAsset tokens that was sent from the auction house
        // Will revert if the auction house did not send the correct amount of preAsset tokens
        _burn(address(this), refund_);
    }

    function _onCurate(
        uint96 lotId_,
        uint96 curatorFee_,
        bool prefund_,
        bytes calldata
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that prefund is true
        if (!prefund_) revert Callback_InvalidParams();

        // Update the capacity with the curator fee
        capacity += curatorFee_;

        // Mint the curator fee amount of preAsset tokens to the auction house
        _mint(msg.sender, curatorFee_);
    }

    function _onPurchase(
        uint96,
        address,
        uint96,
        uint96,
        bool,
        bytes calldata
    ) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onBid(
        uint96,
        uint64,
        address,
        uint96,
        bytes calldata
    ) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    function _onClaimProceeds(
        uint96 lotId_,
        uint96 proceeds_,
        uint96 refund_,
        bytes calldata,
        bytes memory
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that the auction is not already complete
        if (auctionComplete) revert Callback_AlreadyComplete();

        // Validate that the callback received the correct amount of proceeds
        if (proceeds_ < reserve.balanceOf(address(this))) revert Callback_MissingFunds();

        // Set the auction as complete
        auctionComplete = true;

        // Calculate the clearing price in quote tokens per base token
        clearingPrice = (proceeds_ * 1e18) / (capacity - refund_);

        // Burn any refunded preAsset tokens that were sent from the auction house
        _burn(address(this), refund_);
    }

    // ========== BASELINE PREASSET FUNCTIONS ========== //

    // Transfer reserves to baseline to seed the pool
    function seed() external override returns (uint256) {
        // Ensure the auction is complete
        if (!auctionComplete) revert PreAsset_AuctionNotComplete();

        // Ensure that the baseline market hasn't already been seeded
        if (seeded) revert PreAsset_AlreadySeeded();

        // Ensure that the bAsset has been set
        if (address(bAsset) == address(0)) revert PreAsset_BAssetNotSet();

        // Ensure caller is the baseline contract
        address baseline = bAsset.baseline();
        if (msg.sender != baseline) revert PreAsset_NotAuthorized();

        // Set the preAsset as seeded
        seeded = true;

        // Transfer reserves to the baseline market
        uint256 totalReserves = reserve.balanceOf(address(this));
        reserve.transfer(baseline, totalReserves);

        emit Seeded(totalReserves);
        return totalReserves;
    }

    // Set the precalculated BAsset address, must be called before baseline deployment
    function setBAsset(address bAsset_) external override {
        // Ensure caller is the baseline factory
        if (msg.sender != baselineFactory) revert PreAsset_NotAuthorized();

        // Ensure the bAsset has not already been set
        if (address(bAsset) != address(0)) revert PreAsset_BAssetAlreadySet();

        // Set the bAsset
        bAsset = IBAsset(bAsset_);
    }

}
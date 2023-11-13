/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "src/modules/HOUSE/HOUSE.v1.sol";

contract AuctionHouse is HOUSEv1 {

    // ========== CONSTRUCTOR ========== //
    
    constructor(Kernel kernel_) Module(kernel_) {}

    // ========== KERNEL FUNCTIONS ========== //

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("HOUSE");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    // ========== AUCTION EXECUTION ========== //

    function _getSubmoduleForId(uint256 id_) internal view returns (AuctionSubmodule) {
        // Confirm lot ID is valid
        if (id_ >= auctionCount) revert HOUSE_InvalidLotId(id_);      
        
        // Get lot type
        SubKeycode auctionType = lotType[id_];

        // Load submodule, will revert if not installed
        return AuctionSubmodule(_getSubmoduleIfInstalled(auctionType));
    }

    function purchase(uint256 id_, uint256 amount_, uint256 minAmountOut_) external override permissioned returns (uint256 payout) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Send purchase to submodule and return payout
        payout = submodule.purchase(id_, amount_, minAmountOut_);
    }

    function settle(uint256 id_, AUCTIONv1.Bid[] memory bids_) external override returns (uint256[] memory amountsOut) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Send purchase to submodule and return amountsOut payout
        amountsOut = submodule.settle(id_, bids_);
    }

    // ========== AUCTION MANAGEMENT ========== //

    function createAuction(SubKeycode auctionType_, AUCTIONv1.AuctionParams memory params_) external override returns (uint256 id) {
        // Load auction type submodule, this checks that it is installed.
        // We load it here vs. later to avoid two checks.
        AuctionSubmodule submodule = AuctionSubmodule(_getSubmoduleIfInstalled(auctionType_));

        // Check that the auction type is allowing new auctions to be created
        if (typeSunset[auctionType_]) revert HOUSE_AuctionTypeSunset(auctionType_);

        // Increment auction count and get ID
        id = auctionCount++;

        // Call submodule createAuction function to store implementation-specific data
        submodule.createAuction(id, params_);

        // Store auction type
        lotType[id] = auctionType_;
    }

    // TODO how to verify auction owner?
    function closeAuction(uint256 id_) external override {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Close the auction on the submodule
        submodule.closeAuction(id_);
    }

    // ========== AUCTION INFORMATION ========== //

    function getRouting(uint256 id_) external view override returns (AUCTIONv1.Routing memory) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Get routing from submodule
        return submodule.getRouting(id_);
    }

    function payoutFor(uint256 id_, uint256 amount_) external view override permissioned returns (uint256) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Get payout from submodule
        return submodule.payoutFor(id_, amount_);
    }

    function priceFor(uint256 id_, uint256 payout_) external view override permissioned returns (uint256) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Get price from submodule
        return submodule.priceFor(id_, payout_);
    }

    function maxPayout(uint256 id_) external view override permissioned returns (uint256) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Get max payout from submodule
        return submodule.maxPayout(id_);
    }

    function maxAmountAccepted(uint256 id_) external view override permissioned returns (uint256) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Get max amount accepted from submodule
        return submodule.maxAmountAccepted(id_);
    }

    function isLive(uint256 id_) external view override returns (bool) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Get isLive from submodule
        return submodule.isLive(id_);
    }

    function ownerOf(uint256 id_) external view override returns (address) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Get owner from submodule
        return submodule.ownerOf(id_);
    }

    function remainingCapacity(id_) external view override returns (uint256) {
        AuctionSubmodule submodule = _getSubmoduleForId(id_);

        // Get remaining capacity from submodule
        return submodule.remainingCapacity(id_);
    }

}
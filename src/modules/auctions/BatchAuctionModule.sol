// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {Auction, AuctionModule} from "src/modules/Auction.sol";

/// @title  Batch Auction Module
/// @notice A base contract for batch auctions
abstract contract BatchAuctionModule is AuctionModule {
    // ========== ERRORS ========== //

    error Auction_InvalidBidId(uint96 lotId, uint96 bidId);
    error Auction_NotBidder();

    // ========== SETUP ========== //

    /// @inheritdoc Auction
    function auctionType() external pure override returns (AuctionType) {
        return AuctionType.Batch;
    }

    // ========== BATCH AUCTIONS ========== //

    /// @inheritdoc Auction
    /// @dev        Implements a basic bid function that:
    ///             - Calls implementation-specific validation logic
    ///             - Calls the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot has not started
    ///             - the lot has concluded
    ///             - the lot is already settled
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should override _bid to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Storing the bid data
    function bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint96 amount_,
        bytes calldata auctionData_
    ) external override onlyInternal returns (uint64 bidId) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotConcluded(lotId_);
        _revertIfLotSettled(lotId_);

        // Call implementation-specific logic
        return _bid(lotId_, bidder_, referrer_, amount_, auctionData_);
    }

    /// @notice     Implementation-specific bid logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///             The returned `bidId` should be a unique and persistent identifier for the bid,
    ///             which can be used in subsequent calls (e.g. `cancelBid()` or `settle()`).
    ///
    /// @param      lotId_          The lot ID
    /// @param      bidder_         The bidder of the purchased tokens
    /// @param      referrer_       The referrer of the bid
    /// @param      amount_         The amount of quote tokens to bid
    /// @param      auctionData_    The auction-specific data
    /// @return     bidId           The bid ID
    function _bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint96 amount_,
        bytes calldata auctionData_
    ) internal virtual returns (uint64 bidId);

    /// @inheritdoc Auction
    /// @dev        Implements a basic refundBid function that:
    ///             - Calls implementation-specific validation logic
    ///             - Calls the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot is not settled
    ///             - the bid id is invalid
    ///             - `caller_` is not the bid owner
    ///             - the bid is cancelled
    ///             - the bid is already refunded
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should check for lot cancellation, if needed.
    ///
    ///             Inheriting contracts should override _refundBid to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Updating the bid data
    function refundBid(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) external override onlyInternal returns (uint96 refund) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);
        _revertIfNotBidOwner(lotId_, bidId_, caller_);
        _revertIfBidClaimed(lotId_, bidId_);
        _revertIfLotConcluded(lotId_);

        // Call implementation-specific logic
        return _refundBid(lotId_, bidId_, caller_);
    }

    /// @notice     Implementation-specific bid refund logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    /// @param      caller_     The caller
    /// @return     refund   The amount of quote tokens to refund
    function _refundBid(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) internal virtual returns (uint96 refund);

    /// @inheritdoc Auction
    /// @dev        Implements a basic claimBids function that:
    ///             - Calls implementation-specific validation logic
    ///             - Calls the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot is not settled
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should override _claimBids to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Validating the validity and status of each bid
    ///             - Updating the bid data
    function claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    )
        external
        override
        onlyInternal
        returns (BidClaim[] memory bidClaims, bytes memory auctionOutput)
    {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotNotSettled(lotId_);

        // Call implementation-specific logic
        return _claimBids(lotId_, bidIds_);
    }

    /// @notice     Implementation-specific bid claim logic
    /// @dev        Auction modules should override this to perform any additional logic
    ///
    /// @param      lotId_          The lot ID
    /// @param      bidIds_         The bid IDs
    /// @return     bidClaims       The bid claim data
    /// @return     auctionOutput   The auction-specific output
    function _claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    ) internal virtual returns (BidClaim[] memory bidClaims, bytes memory auctionOutput);

    /// @inheritdoc Auction
    /// @dev        Implements a basic settle function that:
    ///             - Calls common validation logic
    ///             - Calls the implementation-specific function for the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot is still active
    ///             - the lot has already been settled
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should override _settle to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Determining the winning bids
    ///             - Updating the lot data
    function settle(uint96 lotId_)
        external
        virtual
        override
        onlyInternal
        returns (Settlement memory settlement, bytes memory auctionOutput)
    {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotActive(lotId_);
        _revertIfLotSettled(lotId_);

        // Call implementation-specific logic
        (settlement, auctionOutput) = _settle(lotId_);

        // Set lot capacity to zero
        lotData[lotId_].capacity = 0;

        // Store sold and purchased amounts
        lotData[lotId_].purchased = settlement.totalIn;
        lotData[lotId_].sold = settlement.totalOut;
        lotData[lotId_].partialPayout = settlement.pfPayout;
    }

    /// @notice     Implementation-specific lot settlement logic
    /// @dev        Auction modules should override this to perform any additional logic,
    ///             such as determining the winning bids and updating the lot data
    ///
    /// @param      lotId_          The lot ID
    /// @return     settlement      The settlement data
    function _settle(uint96 lotId_)
        internal
        virtual
        returns (Settlement memory settlement, bytes memory auctionOutput);

    /// @inheritdoc Auction
    /// @dev        Implements a basic claimProceeds function that:
    ///             - Calls common validation logic
    ///             - Calls the implementation-specific function for the auction module
    ///
    ///             This function reverts if:
    ///             - the lot id is invalid
    ///             - the lot is not settled
    ///             - the lot proceeds have already been claimed
    ///             - the lot is cancelled
    ///             - the caller is not an internal module
    ///
    ///             Inheriting contracts should override _claimProceeds to implement auction-specific logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Updating the lot data
    function claimProceeds(uint96 lotId_)
        external
        virtual
        override
        onlyInternal
        returns (uint96 purchased, uint96 sold, uint96 payoutSent)
    {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfLotProceedsClaimed(lotId_);
        _revertIfLotNotSettled(lotId_);

        // Call implementation-specific logic
        return _claimProceeds(lotId_);
    }

    /// @notice     Implementation-specific claim proceeds logic
    /// @dev        Auction modules should override this to perform any additional logic,
    ///             such as updating the lot data
    ///
    /// @param      lotId_          The lot ID
    /// @return     purchased       The amount of quote tokens purchased
    /// @return     sold            The amount of base tokens sold
    /// @return     payoutSent      The amount of base tokens that have already been paid out
    function _claimProceeds(uint96 lotId_)
        internal
        virtual
        returns (uint96 purchased, uint96 sold, uint96 payoutSent);

    // ========== MODIFIERS ========== //

    /// @notice     Checks that the lot represented by `lotId_` is not settled
    /// @dev        Should revert if the lot is settled
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotSettled(uint96 lotId_) internal view virtual;

    /// @notice     Checks that the lot represented by `lotId_` is settled
    /// @dev        Should revert if the lot is not settled
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotNotSettled(uint96 lotId_) internal view virtual;

    /// @notice     Checks if the lot represented by `lotId_` has had its proceeds claimed
    /// @dev        Should revert if the lot proceeds have been claimed
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    function _revertIfLotProceedsClaimed(uint96 lotId_) internal view virtual;

    /// @notice     Checks that the lot and bid combination is valid
    /// @dev        Should revert if the bid is invalid
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_  The lot ID
    /// @param      bidId_  The bid ID
    function _revertIfBidInvalid(uint96 lotId_, uint64 bidId_) internal view virtual;

    /// @notice     Checks that `caller_` is the bid owner
    /// @dev        Should revert if `caller_` is not the bid owner
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    /// @param      caller_     The caller
    function _revertIfNotBidOwner(
        uint96 lotId_,
        uint64 bidId_,
        address caller_
    ) internal view virtual;

    /// @notice     Checks that the bid is not claimed
    /// @dev        Should revert if the bid is claimed
    ///             Inheriting contracts must override this to implement custom logic
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    function _revertIfBidClaimed(uint96 lotId_, uint64 bidId_) internal view virtual;

    // ========== NOT IMPLEMENTED ========== //

    function purchase(
        uint96,
        uint96,
        bytes calldata
    ) external virtual override returns (uint96, bytes memory) {
        revert Auction_NotImplemented();
    }
}

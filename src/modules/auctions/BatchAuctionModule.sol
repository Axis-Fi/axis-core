// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.19;

// Interfaces
import {IAuction} from "src/interfaces/IAuction.sol";
import {IBatchAuction} from "src/interfaces/IBatchAuction.sol";

// Auctions
import {AuctionModule} from "src/modules/Auction.sol";

/// @title  Batch Auction Module
/// @notice A base contract for batch auctions
abstract contract BatchAuctionModule is IBatchAuction, AuctionModule {
    // ========== STATE VARIABLES ========== //

    /// @notice     Custom auction output for each lot
    /// @dev        Stored during settlement
    mapping(uint96 => bytes) public lotAuctionOutput;

    /// @inheritdoc IAuction
    function auctionType() external pure override returns (AuctionType) {
        return AuctionType.Batch;
    }

    // ========== BATCH AUCTIONS ========== //

    /// @inheritdoc IBatchAuction
    /// @dev        Implements a basic bid function that:
    ///             - Validates the lot and bid parameters
    ///             - Calls the implementation-specific function
    ///
    ///             This function reverts if:
    ///             - The lot id is invalid
    ///             - The lot has not started
    ///             - The lot has concluded
    ///             - The lot is already settled
    ///             - The caller is not an internal module
    function bid(
        uint96 lotId_,
        address bidder_,
        address referrer_,
        uint256 amount_,
        bytes calldata auctionData_
    ) external virtual override onlyInternal returns (uint64 bidId) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotConcluded(lotId_);
        _revertIfLotSettled(lotId_);

        // Call implementation-specific logic
        return _bid(lotId_, bidder_, referrer_, amount_, auctionData_);
    }

    /// @notice     Implementation-specific bid logic
    /// @dev        Auction modules should override this to perform any additional logic, such as validation and storage.
    ///
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
        uint256 amount_,
        bytes calldata auctionData_
    ) internal virtual returns (uint64 bidId);

    /// @inheritdoc IBatchAuction
    /// @dev        Implements a basic refundBid function that:
    ///             - Validates the lot and bid parameters
    ///             - Calls the implementation-specific function
    ///
    ///             This function reverts if:
    ///             - The lot id is invalid
    ///             - The lot has not started
    ///             - The lot is concluded, decrypted or settled
    ///             - The bid id is invalid
    ///             - `caller_` is not the bid owner
    ///             - The bid is claimed or refunded
    ///             - The caller is not an internal module
    function refundBid(
        uint96 lotId_,
        uint64 bidId_,
        uint256 index_,
        address caller_
    ) external virtual override onlyInternal returns (uint256 refund) {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfBidInvalid(lotId_, bidId_);
        _revertIfNotBidOwner(lotId_, bidId_, caller_);
        _revertIfBidClaimed(lotId_, bidId_);
        _revertIfLotConcluded(lotId_);

        // Call implementation-specific logic
        return _refundBid(lotId_, bidId_, index_, caller_);
    }

    /// @notice     Implementation-specific bid refund logic
    /// @dev        Auction modules should override this to perform any additional logic, such as validation and storage.
    ///
    ///             Implementation functions should check for lot cancellation, if needed.
    ///
    /// @param      lotId_      The lot ID
    /// @param      bidId_      The bid ID
    /// @param      index_      The index of the bid ID in the auction's bid list
    /// @param      caller_     The caller
    /// @return     refund      The amount of quote tokens to refund
    function _refundBid(
        uint96 lotId_,
        uint64 bidId_,
        uint256 index_,
        address caller_
    ) internal virtual returns (uint256 refund);

    /// @inheritdoc IBatchAuction
    /// @dev        Implements a basic claimBids function that:
    ///             - Validates the lot and bid parameters
    ///             - Calls the implementation-specific function
    ///
    ///             This function reverts if:
    ///             - The lot id is invalid
    ///             - The lot is not settled
    ///             - The caller is not an internal module
    function claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    )
        external
        virtual
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
    /// @dev        Auction modules should override this to perform any additional logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Validating the validity and status of each bid
    ///             - Updating the bid data
    ///
    /// @param      lotId_          The lot ID
    /// @param      bidIds_         The bid IDs
    /// @return     bidClaims       The bid claim data
    /// @return     auctionOutput   The auction-specific output
    function _claimBids(
        uint96 lotId_,
        uint64[] calldata bidIds_
    ) internal virtual returns (BidClaim[] memory bidClaims, bytes memory auctionOutput);

    /// @inheritdoc IBatchAuction
    /// @dev        Implements a basic settle function that:
    ///             - Validates the lot and bid parameters
    ///             - Calls the implementation-specific function
    ///             - Updates the lot data
    ///
    ///             This function reverts if:
    ///             - The lot id is invalid
    ///             - The lot has not started
    ///             - The lot is active
    ///             - The lot has already been settled
    ///             - The caller is not an internal module
    function settle(
        uint96 lotId_,
        uint256 num_
    )
        external
        virtual
        override
        onlyInternal
        returns (uint256 totalIn, uint256 totalOut, uint256 capacity, bool finished, bytes memory auctionOutput)
    {
        // Standard validation
        _revertIfLotInvalid(lotId_);
        _revertIfBeforeLotStart(lotId_);
        _revertIfLotActive(lotId_);
        _revertIfLotSettled(lotId_);

        Lot storage lot = lotData[lotId_];

        // Call implementation-specific logic
        (totalIn, totalOut, finished, auctionOutput) = _settle(lotId_, num_);

        // Store sold and purchased amounts
        lotData[lotId_].purchased = totalIn;
        lotData[lotId_].sold = totalOut;
        lotAuctionOutput[lotId_] = auctionOutput;

        return (totalIn, totalOut, lot.capacity, finished, auctionOutput);
    }

    /// @notice     Implementation-specific lot settlement logic
    /// @dev        Auction modules should override this to perform any additional logic, such as:
    ///             - Validating the auction-specific parameters
    ///             - Determining the winning bids
    ///             - Updating the lot data
    ///
    /// @param      lotId_          The lot ID
    /// @param      num_            The number of bids to settle in this pass (capped at the remaining number if more is provided)
    /// @return     totalIn         The total amount of quote tokens that filled the auction
    /// @return     totalOut        The total amount of base tokens sold
    /// @return     finished        Whether the settlement is finished
    /// @return     auctionOutput   The auction-type specific output to be used with a condenser
    function _settle(
        uint96 lotId_,
        uint256 num_
    ) internal virtual returns (uint256 totalIn, uint256 totalOut, bool finished, bytes memory auctionOutput);

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

    // ========== VIEW FUNCTIONS ========== //

    function getNumBids(uint96 lotId_) external view virtual returns (uint256);

    function getBidIds(
        uint96 lotId_,
        uint256 start_,
        uint256 count_
    ) external view virtual returns (uint64[] memory);
}

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

// Interfaces
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {IDerivative} from "src/interfaces/modules/IDerivative.sol";

// Internal dependencies
import {Keycode, Veecode} from "src/modules/Keycode.sol";

/// @title  IAuctionHouse
/// @notice Interface for the Axis AuctionHouse contracts
interface IAuctionHouse {
    // ========= ERRORS ========= //

    error InvalidParams();
    error InvalidLotId(uint96 id_);
    error InvalidState();
    error InvalidCallback();

    /// @notice     Used when the caller is not permitted to perform that action
    error NotPermitted(address caller_);

    // ========= EVENTS ========= //

    /// @notice         Emitted when a new auction lot is created
    ///
    /// @param          lotId       ID of the auction lot
    /// @param          auctionRef  Auction module, represented by its Veecode
    /// @param          infoHash    IPFS hash of the auction information
    event AuctionCreated(uint96 indexed lotId, Veecode indexed auctionRef, string infoHash);

    /// @notice         Emitted when an auction lot is cancelled
    ///
    /// @param          lotId       ID of the auction lot
    /// @param          auctionRef  Auction module, represented by its Veecode
    event AuctionCancelled(uint96 indexed lotId, Veecode indexed auctionRef);

    /// @notice         Emitted when a curator accepts curation of an auction lot
    ///
    /// @param          lotId       ID of the auction lot
    /// @param          curator     Address of the curator
    event Curated(uint96 indexed lotId, address indexed curator);

    // ========= DATA STRUCTURES ========== //

    /// @notice     Auction routing information provided as input parameters
    ///
    /// @param      auctionType         Auction type, represented by the Keycode for the auction submodule
    /// @param      baseToken           Token provided by seller. Declared as an address to avoid dependency hell.
    /// @param      quoteToken          Token to accept as payment. Declared as an address to avoid dependency hell.
    /// @param      curator             (optional) Address of the proposed curator
    /// @param      referrerFee         (optional) Percent of bid/purchase amount received paid to a referrer in basis points, i.e. 1% = 100.
    /// @param      callbacks           (optional) Callbacks implementation for extended functionality
    /// @param      callbackData        (optional) abi-encoded data to be sent to the onCreate callback function
    /// @param      derivativeType      (optional) Derivative type, represented by the Keycode for the derivative submodule
    /// @param      derivativeParams    (optional) abi-encoded data to be used to create payout derivatives on a purchase. The format of this is dependent on the derivative module.
    /// @param      wrapDerivative      (optional) Whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format
    struct RoutingParams {
        Keycode auctionType;
        address baseToken;
        address quoteToken;
        address curator;
        uint48 referrerFee;
        ICallback callbacks;
        bytes callbackData;
        Keycode derivativeType;
        bytes derivativeParams;
        bool wrapDerivative;
    }

    /// @notice     Auction routing information for a lot
    ///
    /// @param      seller              Lot seller
    /// @param      baseToken           ERC20 token provided by seller
    /// @param      quoteToken          ERC20 token to accept as payment
    /// @param      auctionReference    Auction module, represented by its Veecode
    /// @param      funding             The amount of base tokens in funding remaining
    /// @param      callbacks           (optional) Callbacks implementation for extended functionality
    /// @param      derivativeReference (optional) Derivative module, represented by its Veecode
    /// @param      wrapDerivative      (optional) Whether to wrap the derivative in a ERC20 token instead of the native ERC6909 format
    /// @param      derivativeParams    (optional) abi-encoded data to be used to create payout derivatives on a purchase
    struct Routing {
        address seller; // 20 bytes
        address baseToken; // 20 bytes
        address quoteToken; // 20 bytes
        Veecode auctionReference; // 7 bytes
        uint256 funding; // 32 bytes
        ICallback callbacks; // 20 bytes
        Veecode derivativeReference; // 7 bytes
        bool wrapDerivative; // 1 byte
        bytes derivativeParams;
    }

    /// @notice     Fee information for a lot
    /// @dev        This is split into a separate struct, otherwise the Routing struct would be too large
    ///             and would throw a "stack too deep" error.
    ///
    ///             Fee information is set at the time of auction creation, in order to prevent subsequent inflation.
    ///             The fees are cached in order to prevent:
    ///             - Reducing the amount of base tokens available for payout to the winning bidders
    ///             - Reducing the amount of quote tokens available for payment to the seller
    ///
    /// @param      curator     Address of the proposed curator
    /// @param      curated     Whether the curator has approved the auction
    /// @param      curatorFee  The fee charged by the curator
    /// @param      protocolFee The fee charged by the protocol
    /// @param      referrerFee The fee charged by the referrer
    struct FeeData {
        address curator; // 20 bytes
        bool curated; // 1 byte
        uint48 curatorFee; // 6 bytes
        uint48 protocolFee; // 6 bytes
        uint48 referrerFee; // 6 bytes
    }

    // ========== AUCTION MANAGEMENT ========== //

    /// @notice     Creates a new auction lot
    ///
    /// @param      routing_    Routing information for the auction lot
    /// @param      params_     Auction parameters for the auction lot
    /// @param      infoHash_   IPFS hash of the auction information
    /// @return     lotId       ID of the auction lot
    function auction(
        RoutingParams calldata routing_,
        IAuction.AuctionParams calldata params_,
        string calldata infoHash_
    ) external returns (uint96 lotId);

    /// @notice     Cancels an auction lot
    ///
    /// @param      lotId_          ID of the auction lot
    /// @param      callbackData_   (optional) abi-encoded data to be sent to the onCancel callback function
    function cancel(uint96 lotId_, bytes calldata callbackData_) external;

    /// @notice     Accept curation request for a lot.
    /// @notice     If the curator wishes to charge a fee, it must be set before this function is called.
    /// @notice     Access controlled. Must be proposed curator for lot.
    ///
    /// @param      lotId_           Lot ID
    /// @param      callbackData_    (optional) abi-encoded data to be sent to the onCurate callback function
    function curate(uint96 lotId_, bytes calldata callbackData_) external;

    // ========== AUCTION INFORMATION ========== //

    /// @notice     The counter tracks the total number of auction lots
    function lotCounter() external view returns (uint96 lotCount);

    /// @notice     Mapping of lot IDs to their routing information
    /// @dev        See the `Routing` struct for more information
    ///
    /// @param      lotId   ID of the auction lot
    function lotRouting(uint96 lotId)
        external
        view
        returns (
            address seller,
            address baseToken,
            address quoteToken,
            Veecode auctionReference,
            uint256 funding,
            ICallback callbacks,
            Veecode derivativeReference,
            bool wrapDerivative,
            bytes memory derivativeParams
        );

    /// @notice     Mapping of lot IDs to their fee information
    /// @dev        See the `FeeData` struct for more information
    ///
    /// @param      lotId   ID of the auction lot
    function lotFees(uint96 lotId)
        external
        view
        returns (
            address curator,
            bool curated,
            uint48 curatorFee,
            uint48 protocolFee,
            uint48 referrerFee
        );

    /// @notice     Mapping auction and derivative references to the condenser that is used to pass data between them
    ///
    /// @param      auctionRef      Versioned keycode for the auction module
    /// @param      derivativeRef   Versioned keycode for the derivative module
    /// @return     condenserRef    Versioned keycode for the condenser module
    function condensers(
        Veecode auctionRef,
        Veecode derivativeRef
    ) external view returns (Veecode condenserRef);

    /// @notice     Gets the auction module for a given lot ID
    ///
    /// @param      lotId_  ID of the auction lot
    /// @return     module  The auction module
    function getAuctionModuleForId(uint96 lotId_) external view returns (IAuction module);

    /// @notice     Gets the derivative module for a given lot ID
    /// @dev        Will revert if the lot does not have a derivative module
    ///
    /// @param      lotId_  ID of the auction lot
    /// @return     module  The derivative module
    function getDerivativeModuleForId(uint96 lotId_) external view returns (IDerivative module);
}

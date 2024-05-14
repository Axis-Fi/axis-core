// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import {IAuction} from "src/interfaces/IAuction.sol";
import {ICallback} from "src/interfaces/ICallback.sol";

import {Keycode} from "src/modules/Keycode.sol";

/// @title  IAuctionHouse
/// @notice Interface for the Axis AuctionHouse contracts
interface IAuctionHouse {
    // ========= DATA STRUCTURES ========== //

    /// @notice     Auction routing information provided as input parameters
    ///
    /// @param      auctionType         Auction type, represented by the Keycode for the auction submodule
    /// @param      baseToken           Token provided by seller. Declared as an address to avoid dependency hell.
    /// @param      quoteToken          Token to accept as payment. Declared as an address to avoid dependency hell.
    /// @param      curator             (optional) Address of the proposed curator
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
        ICallback callbacks;
        bytes callbackData;
        Keycode derivativeType;
        bytes derivativeParams;
        bool wrapDerivative;
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

    // ========== AUCTION INFORMATION ========== //

    /// @notice     Gets the module for a given lot ID
    ///
    /// @param      lotId_  ID of the auction lot
    /// @return     module  The auction module
    function getModuleForId(uint96 lotId_) external view returns (IAuction module);
}

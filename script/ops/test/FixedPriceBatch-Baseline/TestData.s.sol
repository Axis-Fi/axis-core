// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";

// System contracts
import {IBatchAuctionHouse} from "src/interfaces/IBatchAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {toKeycode} from "src/modules/Modules.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {IAuction} from "src/interfaces/modules/IAuction.sol";
import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {BALwithAllocatedAllowlist} from
    "src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";

// Generic contracts
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

contract TestData is Script, WithEnvironment {
    BatchAuctionHouse public auctionHouse;

    function mintTestTokens(address token, address receiver) public {
        // Mint tokens to address
        vm.broadcast();
        MockERC20(token).mint(receiver, 1e24);
    }

    function createAuction(
        string calldata chain_,
        address quoteToken_,
        address baseToken_,
        address callback_,
        bytes32 merkleRoot
    ) public returns (uint96) {
        // Load addresses from .env
        _loadEnv(chain_);
        auctionHouse = BatchAuctionHouse(_envAddressNotZero("deployments.BatchAuctionHouse"));

        vm.startBroadcast();

        // Create Fixed Price Batch auction
        IAuctionHouse.RoutingParams memory routingParams;
        routingParams.auctionType = toKeycode("FPBA");
        routingParams.baseToken = baseToken_;
        routingParams.quoteToken = quoteToken_;
        routingParams.callbacks = ICallback(callback_);
        if (callback_ != address(0)) {
            console2.log("Setting callback parameters");
            routingParams.callbackData = abi.encode(
                BaselineAxisLaunch.CreateData({
                    floorReservesPercent: 50e2, // 50%
                    anchorTickWidth: 3,
                    discoveryTickWidth: 100,
                    allowlistParams: abi.encode(merkleRoot)
                })
            );

            // No spending approval necessary, since the callback will handle it
        } else {
            console2.log("Callback disabled");

            // Approve spending of the base token
            ERC20(baseToken_).approve(address(auctionHouse), 10e18);
        }

        IFixedPriceBatch.AuctionDataParams memory auctionDataParams;
        auctionDataParams.price = 1e18; // 1 quote tokens per base token
        auctionDataParams.minFillPercent = uint24(1000); // 10%
        bytes memory implParams = abi.encode(auctionDataParams);

        uint48 duration = 86_400; // 1 day

        IFixedPriceBatch.AuctionParams memory auctionParams;
        auctionParams.start = uint48(0); // immediately
        auctionParams.duration = duration;
        // capaity is in base token
        auctionParams.capacity = 10e18; // 10 base tokens
        auctionParams.implParams = implParams;

        string memory infoHash = "";

        uint96 lotId = auctionHouse.auction(routingParams, auctionParams, infoHash);

        vm.stopBroadcast();

        console2.log("Fixed Price Batch auction created with lot ID: ", lotId);

        // Get the conclusion timestamp from the auction
        (, uint48 conclusion,,,,,,) =
            IAuction(address(auctionHouse.getBatchModuleForId(lotId))).lotData(lotId);
        console2.log("Auction ends at timestamp", conclusion);

        return lotId;
    }

    function cancelAuction(string calldata chain_, uint96 lotId_) public {
        _loadEnv(chain_);
        auctionHouse = BatchAuctionHouse(_envAddressNotZero("deployments.BatchAuctionHouse"));
        vm.broadcast();
        auctionHouse.cancel(lotId_, bytes(""));
    }

    function placeBid(
        string calldata chain_,
        uint96 lotId_,
        uint256 amount_,
        bytes32 merkleProof_,
        uint256 allocatedAmount_
    ) public {
        _loadEnv(chain_);
        auctionHouse = BatchAuctionHouse(_envAddressNotZero("deployments.BatchAuctionHouse"));

        // Approve spending of the quote token
        {
            (,, address quoteTokenAddress,,,,,,) = auctionHouse.lotRouting(lotId_);

            vm.broadcast();
            ERC20(quoteTokenAddress).approve(address(auctionHouse), amount_);

            console2.log("Approved spending of quote token by BatchAuctionHouse");
        }

        bytes32[] memory allowlistProof = new bytes32[](1);
        allowlistProof[0] = merkleProof_;

        vm.broadcast();
        uint64 bidId = auctionHouse.bid(
            IBatchAuctionHouse.BidParams({
                lotId: lotId_,
                bidder: msg.sender,
                referrer: address(0),
                amount: amount_,
                auctionData: abi.encode(""),
                permit2Data: bytes("")
            }),
            abi.encode(allowlistProof, allocatedAmount_)
        );

        console2.log("Bid placed with ID: ", bidId);
    }

    function settleAuction(string calldata chain_, uint96 lotId_) public {
        _loadEnv(chain_);
        auctionHouse = BatchAuctionHouse(_envAddressNotZero("deployments.BatchAuctionHouse"));

        console2.log("Timestamp is", block.timestamp);

        vm.broadcast();
        auctionHouse.settle(lotId_, 100, abi.encode(""));

        console2.log("Auction settled with lot ID: ", lotId_);
    }
}

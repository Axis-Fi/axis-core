// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";
import {WithEnvironment} from "../../../deploy/WithEnvironment.s.sol";

// System contracts
import {IBatchAuctionHouse} from "../../../../src/interfaces/IBatchAuctionHouse.sol";
import {BatchAuctionHouse} from "../../../../src/BatchAuctionHouse.sol";
import {IAuctionHouse} from "../../../../src/interfaces/IAuctionHouse.sol";
import {toKeycode} from "../../../../src/modules/Modules.sol";
import {ICallback} from "../../../../src/interfaces/ICallback.sol";
import {IFixedPriceBatch} from "../../../../src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {IAuction} from "../../../../src/interfaces/modules/IAuction.sol";

// Callbacks
// import {BaseDirectToLiquidity} from "../../../../src/callbacks/liquidity/BaseDTL.sol";
// import {UniswapV2DirectToLiquidity} from "../../../../src/callbacks/liquidity/UniswapV2DTL.sol";

// Generic contracts
import {ERC20} from "@solmate-6.7.0/tokens/ERC20.sol";
import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";

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
        uint24 uniswapV3PoolFee_
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
            console2.log("Callback enabled");

            bytes memory callbackImplParams = abi.encode("");
            if (uniswapV3PoolFee_ > 0) {
                console2.log("Setting Uniswap V3 pool fee to", uniswapV3PoolFee_);
                callbackImplParams = abi.encode(uniswapV3PoolFee_);
            }

            routingParams.callbackData = abi.encode("");
            // BaseDirectToLiquidity.OnCreateParams({
            //     proceedsUtilisationPercent: 5000, // 50%
            //     vestingStart: 0,
            //     vestingExpiry: 0,
            //     recipient: msg.sender,
            //     implParams: callbackImplParams
            // })

            // Approve spending of the base token by the callback (for deposit into the liquidity pool)
            ERC20(baseToken_).approve(callback_, 10e18);
        } else {
            console2.log("Callback disabled");
        }

        // Approve spending of the base token by the AuctionHouse
        ERC20(baseToken_).approve(address(auctionHouse), 10e18);

        IFixedPriceBatch.AuctionDataParams memory auctionDataParams;
        auctionDataParams.price = 2e18; // 2 quote tokens per base token
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

    function placeBid(string calldata chain_, uint96 lotId_, uint256 amount_) public {
        _loadEnv(chain_);
        auctionHouse = BatchAuctionHouse(_envAddressNotZero("deployments.BatchAuctionHouse"));

        // Approve spending of the quote token
        {
            (,, address quoteTokenAddress,,,,,,) = auctionHouse.lotRouting(lotId_);

            vm.broadcast();
            ERC20(quoteTokenAddress).approve(address(auctionHouse), amount_);

            console2.log("Approved spending of quote token by BatchAuctionHouse");
        }

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
            abi.encode("")
        );

        console2.log("Bid placed with ID: ", bidId);
    }

    function settleAuction(string calldata chain_, uint96 lotId_) public {
        _loadEnv(chain_);
        auctionHouse = BatchAuctionHouse(_envAddressNotZero("deployments.BatchAuctionHouse"));

        console2.log("Timestamp is", block.timestamp);

        // bytes memory callbackData =
        // abi.encode(UniswapV2DirectToLiquidity.OnSettleParams({maxSlippage: 50})); // 0.5%
        bytes memory callbackData = abi.encode("");

        vm.broadcast();
        auctionHouse.settle(lotId_, 100, callbackData);

        console2.log("Auction settled with lot ID: ", lotId_);
    }
}

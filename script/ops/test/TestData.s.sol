/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";

// System contracts
import {AuctionHouse} from "src/AuctionHouse.sol";
import {toKeycode} from "src/modules/Modules.sol";
import {LocalSealedBidBatchAuction as LSBBA} from "src/modules/auctions/LSBBA/LSBBA.sol";

// Generic contracts
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

contract TestData is Script {
    AuctionHouse public auctionHouse;
    MockERC20 public quoteToken;
    MockERC20 public baseToken;

    function deployTestTokens(address seller, address buyer) public {
        vm.startBroadcast();

        // Deploy mock tokens
        quoteToken = new MockERC20("Quote Token", "QTK", 18);
        baseToken = new MockERC20("Base Token", "BTK", 18);

        // Mint quote tokens to buyer
        quoteToken.mint(buyer, 1e25);

        // Mint base tokens to seller
        baseToken.mint(seller, 1e24);

        vm.stopBroadcast();
    }

    function createAuction(bytes memory publicKey, address buyer) public returns (uint96) {
        // Load addresses from .env
        auctionHouse = AuctionHouse(vm.envAddress("AUCTION_HOUSE"));

        // Require the public key to be 128 bytes
        require(publicKey.length == 128, "public key must be 128 bytes");

        // Deploy test tokens and store addresses
        deployTestTokens(msg.sender, buyer);

        vm.startBroadcast();

        // Approve auction house for base token since it will be pre-funded
        baseToken.approve(address(auctionHouse), 1e24);

        // Create LSBBA auction with the provided public key
        AuctionHouse.RoutingParams memory routingParams;
        routingParams.auctionType = toKeycode("LSBBA");
        routingParams.baseToken = baseToken;
        routingParams.quoteToken = quoteToken;
        // No hooks, allowlist, derivative, or other routing params needed

        LSBBA.AuctionDataParams memory auctionDataParams;
        auctionDataParams.minFillPercent = uint24(10_000); // 10%
        auctionDataParams.minBidPercent = uint24(4000); // 4%
        auctionDataParams.minimumPrice = 3e18; // 3 quote tokens per base token
        auctionDataParams.publicKeyModulus = publicKey;
        bytes memory implParams = abi.encode(auctionDataParams);

        LSBBA.AuctionParams memory auctionParams;
        auctionParams.start = uint48(block.timestamp) + 3600; // 1 hour from now
        auctionParams.duration = uint48(86_400); // 1 day
        // capaity is in base token
        auctionParams.capacity = 100e18; // 100 base tokens
        auctionParams.implParams = implParams;

        uint96 lotId = auctionHouse.auction(routingParams, auctionParams);

        vm.stopBroadcast();

        return lotId;
    }

    function cancelAuction(uint96 lotId) public {
        auctionHouse = AuctionHouse(vm.envAddress("AUCTION_HOUSE"));
        vm.broadcast();
        auctionHouse.cancel(lotId);
    }
}

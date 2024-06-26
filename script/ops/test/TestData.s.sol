// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";

// System contracts
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {toKeycode, toVeecode} from "src/modules/Modules.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/batch/EMP.sol";
import {ECIES, Point} from "src/lib/ECIES.sol";
import {uint2str} from "src/lib/Uint2Str.sol";
import {FixedPriceBatch} from "src/modules/auctions/batch/FPB.sol";

// Generic contracts
import {MockERC20, ERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

contract TestData is Script {
    BatchAuctionHouse public auctionHouse;
    MockERC20 public quoteToken;
    MockERC20 public baseToken;

    function deployTestTokens(address seller, address buyer) public {
        vm.startBroadcast();

        // Deploy mock tokens
        quoteToken = new MockERC20("Test Token 1", "TT1", 18);
        console2.log("Quote token deployed at address: ", address(quoteToken));
        baseToken = new MockERC20("Test Token 2", "TT2", 18);
        console2.log("Base token deployed at address: ", address(baseToken));

        // Mint quote tokens to buyer
        quoteToken.mint(buyer, 1e25);

        // Mint base tokens to seller
        baseToken.mint(seller, 1e25);

        vm.stopBroadcast();
    }

    function mintTestTokens(address token, address receiver) public {
        // Mint tokens to address
        vm.broadcast();
        MockERC20(token).mint(receiver, 1e24);
    }

    function createAuction(
        uint256 pubKeyX,
        uint256 pubKeyY,
        address buyer
    ) public returns (uint96) {
        // Load addresses from .env
        auctionHouse = BatchAuctionHouse(vm.envAddress("AUCTION_HOUSE"));

        Point memory publicKey = Point(pubKeyX, pubKeyY);

        // // Deploy test tokens and store addresses
        // deployTestTokens(msg.sender, buyer);

        vm.startBroadcast();

        quoteToken = MockERC20(address(0x8e5a555bcaB474C91dcA326bE3DFdDa7e30c3765));
        baseToken = MockERC20(address(0x532cEd32173222d5D51Ac908e39EA2824d334607));

        // Approve auction house for base token since it will be pre-funded
        baseToken.approve(address(auctionHouse), 1e24);

        // Create LSBBA auction with the provided public key
        IAuctionHouse.RoutingParams memory routingParams;
        routingParams.auctionType = toKeycode("EMPA");
        routingParams.baseToken = address(baseToken);
        routingParams.quoteToken = address(quoteToken);
        // No callbacks, allowlist, derivative, or other routing params needed

        EncryptedMarginalPrice.AuctionDataParams memory auctionDataParams;
        auctionDataParams.minPrice = 2e18; // 2 quote tokens per base token
        auctionDataParams.minFillPercent = uint24(10_000); // 10%
        auctionDataParams.minBidSize = 2e17; // 0.2 quote tokens
        auctionDataParams.publicKey = publicKey;
        bytes memory implParams = abi.encode(auctionDataParams);

        EncryptedMarginalPrice.AuctionParams memory auctionParams;
        auctionParams.start = uint48(0); // immediately
        auctionParams.duration = uint48(86_400); // 1 day
        // capaity is in base token
        auctionParams.capacity = 100e18; // 100 base tokens
        auctionParams.implParams = implParams;

        string memory infoHash = "";

        uint96 lotId = auctionHouse.auction(routingParams, auctionParams, infoHash);

        vm.stopBroadcast();

        return lotId;
    }

    function createFPBAuction() public returns (uint96) {
        // Load addresses from .env
        auctionHouse = BatchAuctionHouse(vm.envAddress("AUCTION_HOUSE"));

        vm.startBroadcast();

        quoteToken = MockERC20(address(0x47F12ccE28D1A2ac9184777fa8a993C6067Df728));
        baseToken = MockERC20(address(0x914e2477Cb36273db3E4c6c6D4cefF1B75aC1Db0));

        // Approve auction house for base token since it will be pre-funded
        baseToken.approve(address(auctionHouse), 1e24);

        // Create LSBBA auction with the provided public key
        IAuctionHouse.RoutingParams memory routingParams;
        routingParams.auctionType = toKeycode("FPBA");
        routingParams.baseToken = address(baseToken);
        routingParams.quoteToken = address(quoteToken);
        // No callbacks, allowlist, derivative, or other routing params needed

        FixedPriceBatch.AuctionDataParams memory auctionDataParams;
        auctionDataParams.price = 5e18; // 5 quote tokens per base token
        auctionDataParams.minFillPercent = uint24(10_000); // 10%
        bytes memory implParams = abi.encode(auctionDataParams);

        FixedPriceBatch.AuctionParams memory auctionParams;
        auctionParams.start = uint48(0); // immediately
        auctionParams.duration = uint48(86_400); // 1 day
        // capaity is in base token
        auctionParams.capacity = 100e18; // 100 base tokens
        auctionParams.implParams = implParams;

        string memory infoHash = "";

        uint96 lotId = auctionHouse.auction(routingParams, auctionParams, infoHash);

        vm.stopBroadcast();

        return lotId;
    }

    function cancelAuction(uint96 lotId) public {
        auctionHouse = BatchAuctionHouse(vm.envAddress("AUCTION_HOUSE"));
        vm.broadcast();
        auctionHouse.cancel(lotId, bytes(""));
    }

    // function placeBid(uint96 lotId, uint256 amount, uint256 minAmountOut) public {
    //     auctionHouse = AuctionHouse(vm.envAddress("AUCTION_HOUSE"));
    //     EMPAM module = EMPAM(address(auctionHouse.getModuleForVeecode(toVeecode("01EMPAM"))));

    //     // Get the public key modulus for the lot
    //     (,,,,,, bytes memory publicKeyModulus) = module.auctionData(lotId);

    //     bytes memory encryptedAmountOut = RSAOAEP.encrypt(
    //         abi.encodePacked(minAmountOut),
    //         abi.encodePacked(uint2str(uint256(lotId))),
    //         abi.encodePacked(uint24(0x10001)),
    //         publicKeyModulus,
    //         keccak256(
    //             abi.encodePacked(
    //                 "TESTSEED", "NOTFORPRODUCTION", msg.sender, lotId, amount, minAmountOut
    //             )
    //         )
    //     );

    //     Router.BidParams memory bidParams = Router.BidParams({
    //         lotId: lotId,
    //         recipient: msg.sender,
    //         referrer: address(0),
    //         amount: amount,
    //         auctionData: encryptedAmountOut,
    //         allowlistProof: bytes(""),
    //         permit2Data: bytes("")
    //     });

    //     // Get quote token and approve the auction house
    //     (,,, ERC20 qt,,,,,,) = auctionHouse.lotRouting(lotId);

    //     vm.startBroadcast();
    //     qt.approve(address(auctionHouse), amount);

    //     // Submit bid and emit ID
    //     uint96 bidId = auctionHouse.bid(bidParams);
    //     console2.log("Bid placed with ID: ", bidId);

    //     vm.stopBroadcast();
    // }
}

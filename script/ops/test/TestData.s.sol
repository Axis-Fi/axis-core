// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "@forge-std-1.9.1/Script.sol";

// System contracts
import {BatchAuctionHouse} from "../../../src/BatchAuctionHouse.sol";
import {IAuctionHouse} from "../../../src/interfaces/IAuctionHouse.sol";
import {toKeycode} from "../../../src/modules/Modules.sol";
import {EncryptedMarginalPrice} from "../../../src/modules/auctions/batch/EMP.sol";
import {Point} from "../../../src/lib/ECIES.sol";

// Generic contracts
import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";

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
        console2.log("Minted 1e25 quote tokens to buyer");

        // Mint base tokens to seller
        baseToken.mint(seller, 1e25);
        console2.log("Minted 1e25 base tokens to seller");

        vm.stopBroadcast();
    }

    function mintTestTokens(address token, address receiver) public {
        // Mint tokens to address
        vm.broadcast();
        MockERC20(token).mint(receiver, 1e24);
    }

    function createAuction(uint256 pubKeyX, uint256 pubKeyY) public returns (uint96) {
        // Load addresses from .env
        auctionHouse = BatchAuctionHouse(vm.envAddress("AUCTION_HOUSE"));

        Point memory publicKey = Point(pubKeyX, pubKeyY);

        vm.startBroadcast();

        quoteToken = MockERC20(address(0x8e5a555bcaB474C91dcA326bE3DFdDa7e30c3765));
        baseToken = MockERC20(address(0x532cEd32173222d5D51Ac908e39EA2824d334607));

        // Approve auction house for base token since it will be pre-funded
        baseToken.approve(address(auctionHouse), 1e24);

        // Create EMP auction with the provided public key
        IAuctionHouse.RoutingParams memory routingParams;
        routingParams.auctionType = toKeycode("EMPA");
        routingParams.baseToken = address(baseToken);
        routingParams.quoteToken = address(quoteToken);
        // No callbacks, allowlist, derivative, or other routing params needed

        EncryptedMarginalPrice.AuctionDataParams memory auctionDataParams;
        auctionDataParams.minPrice = 2e18; // 2 quote tokens per base token
        auctionDataParams.minFillPercent = uint24(1000); // 10%
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

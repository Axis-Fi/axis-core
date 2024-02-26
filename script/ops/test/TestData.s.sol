// /// SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.19;

// // Scripting libraries
// import {Script, console2} from "forge-std/Script.sol";

// // System contracts
// import {AuctionHouse, Router} from "src/AuctionHouse.sol";
// import {toKeycode, toVeecode} from "src/modules/Modules.sol";
// import {LocalSealedBidBatchAuction as LSBBA} from "src/modules/auctions/LSBBA/LSBBA.sol";
// import {RSAOAEP} from "src/lib/RSA.sol";
// import {uint2str} from "src/lib/Uint2Str.sol";

// // Generic contracts
// import {MockERC20, ERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";

// contract TestData is Script {
//     AuctionHouse public auctionHouse;
//     MockERC20 public quoteToken;
//     MockERC20 public baseToken;

//     function deployTestTokens(address seller, address buyer) public {
//         vm.startBroadcast();

//         // Deploy mock tokens
//         quoteToken = new MockERC20("Stormlight Orbs", "SLO", 18);
//         console2.log("Quote token deployed at address: ", address(quoteToken));
//         baseToken = new MockERC20("Atium Beads", "ATUM", 18);
//         console2.log("Base token deployed at address: ", address(baseToken));

//         // Mint quote tokens to buyer
//         quoteToken.mint(buyer, 1e25);

//         // Mint base tokens to seller
//         baseToken.mint(seller, 1e24);

//         vm.stopBroadcast();
//     }

//     function mintTestTokens(address token, address receiver) public {
//         // Mint tokens to address
//         vm.broadcast();
//         MockERC20(token).mint(receiver, 1e24);
//     }

//     function createAuction(bytes memory publicKey, address buyer) public returns (uint96) {
//         // Load addresses from .env
//         auctionHouse = AuctionHouse(vm.envAddress("AUCTION_HOUSE"));

//         // Require the public key to be 128 bytes
//         require(publicKey.length == 128, "public key must be 128 bytes");

//         // Deploy test tokens and store addresses
//         deployTestTokens(msg.sender, buyer);

//         vm.startBroadcast();

//         // Approve auction house for base token since it will be pre-funded
//         baseToken.approve(address(auctionHouse), 1e24);

//         // Create LSBBA auction with the provided public key
//         AuctionHouse.RoutingParams memory routingParams;
//         routingParams.auctionType = toKeycode("LSBBA");
//         routingParams.baseToken = baseToken;
//         routingParams.quoteToken = quoteToken;
//         // No hooks, allowlist, derivative, or other routing params needed

//         LSBBA.AuctionDataParams memory auctionDataParams;
//         auctionDataParams.minFillPercent = uint24(10_000); // 10%
//         auctionDataParams.minBidPercent = uint24(4000); // 4%
//         auctionDataParams.minimumPrice = 3e18; // 3 quote tokens per base token
//         auctionDataParams.publicKeyModulus = publicKey;
//         bytes memory implParams = abi.encode(auctionDataParams);

//         LSBBA.AuctionParams memory auctionParams;
//         auctionParams.start = uint48(0); // immediately
//         auctionParams.duration = uint48(86_400); // 1 day
//         // capaity is in base token
//         auctionParams.capacity = 100e18; // 100 base tokens
//         auctionParams.implParams = implParams;

//         string memory infoHash = "";

//         uint96 lotId = auctionHouse.auction(routingParams, auctionParams, infoHash);

//         vm.stopBroadcast();

//         return lotId;
//     }

//     function cancelAuction(uint96 lotId) public {
//         auctionHouse = AuctionHouse(vm.envAddress("AUCTION_HOUSE"));
//         vm.broadcast();
//         auctionHouse.cancel(lotId);
//     }

//     function placeBid(uint96 lotId, uint256 amount, uint256 minAmountOut) public {
//         auctionHouse = AuctionHouse(vm.envAddress("AUCTION_HOUSE"));
//         LSBBA module = LSBBA(address(auctionHouse.getModuleForVeecode(toVeecode("01LSBBA"))));

//         // Get the public key modulus for the lot
//         (,,,,,, bytes memory publicKeyModulus) = module.auctionData(lotId);

//         bytes memory encryptedAmountOut = RSAOAEP.encrypt(
//             abi.encodePacked(minAmountOut),
//             abi.encodePacked(uint2str(uint256(lotId))),
//             abi.encodePacked(uint24(0x10001)),
//             publicKeyModulus,
//             keccak256(
//                 abi.encodePacked(
//                     "TESTSEED", "NOTFORPRODUCTION", msg.sender, lotId, amount, minAmountOut
//                 )
//             )
//         );

//         Router.BidParams memory bidParams = Router.BidParams({
//             lotId: lotId,
//             recipient: msg.sender,
//             referrer: address(0),
//             amount: amount,
//             auctionData: encryptedAmountOut,
//             allowlistProof: bytes(""),
//             permit2Data: bytes("")
//         });

//         // Get quote token and approve the auction house
//         (,,, ERC20 qt,,,,,,) = auctionHouse.lotRouting(lotId);

//         vm.startBroadcast();
//         qt.approve(address(auctionHouse), amount);

//         // Submit bid and emit ID
//         uint96 bidId = auctionHouse.bid(bidParams);
//         console2.log("Bid placed with ID: ", bidId);

//         vm.stopBroadcast();
//     }
// }

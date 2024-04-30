// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";

// System contracts
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {IBatchAuctionHouse} from "src/interfaces/IBatchAuctionHouse.sol";
import {toKeycode, toVeecode} from "src/modules/Modules.sol";
import {EncryptedMarginalPrice} from "src/modules/auctions/EMP.sol";
import {ECIES, Point} from "src/lib/ECIES.sol";

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
        auctionDataParams.minPrice = 2e18; // 3 quote tokens per base token
        auctionDataParams.minFillPercent = uint24(10_000); // 10%
        auctionDataParams.minBidPercent = uint24(4000); // 4%
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

    function placeBid(uint96 lotId, uint96 amount, uint128 minAmountOut) public {
        auctionHouse = BatchAuctionHouse(vm.envAddress("AUCTION_HOUSE"));
        EncryptedMarginalPrice module =
            EncryptedMarginalPrice(address(auctionHouse.getModuleForVeecode(toVeecode("01EMPA"))));

        // Get the public key modulus for the lot
        (,,,,,,,,, Point memory publicKey,) = module.auctionData(lotId);

        // Get a random value to use as the bid private key (not secure but fine for testing)
        uint256 bidPrivKey;
        {
            string[] memory inputs = new string[](3);
            inputs[0] = "bash";
            inputs[1] = "-c";
            inputs[2] = string.concat("echo $RANDOM | cast to-uint256");

            bidPrivKey = abi.decode(vm.ffi(inputs), (uint256));
        }

        // Use the bid private key to create a seed to mask the bid amount out with
        uint128 seed = uint128(uint256(keccak256(abi.encodePacked(bidPrivKey))));

        uint256 message;
        unchecked {
            message = uint256(minAmountOut - seed);
        }

        // Calculate the salt for the bid
        uint256 salt = uint256(keccak256(abi.encodePacked(lotId, msg.sender, amount)));

        // Encrypt the amount out using the ECIES library
        (uint256 encryptedAmountOut, Point memory bidPubKey) =
            ECIES.encrypt(message, publicKey, bidPrivKey, salt);

        // Construct bid parameters
        IBatchAuctionHouse.BidParams memory bidParams = IBatchAuctionHouse.BidParams({
            lotId: lotId,
            referrer: address(0),
            amount: amount,
            auctionData: abi.encode(encryptedAmountOut, bidPubKey),
            permit2Data: bytes("")
        });

        // Get quote token and approve the auction house
        (,, ERC20 qt,,,,,,) = auctionHouse.lotRouting(lotId);

        vm.startBroadcast();
        qt.approve(address(auctionHouse), amount);

        // Submit bid and emit ID
        uint96 bidId = auctionHouse.bid(bidParams, bytes(""));
        console2.log("Bid placed with ID: ", bidId);

        vm.stopBroadcast();
    }
}

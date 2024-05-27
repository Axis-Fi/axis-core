// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "forge-std/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";

// System contracts
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {toKeycode} from "src/modules/Modules.sol";
import {ICallback} from "src/interfaces/ICallback.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";
import {BaselineAxisLaunch} from "src/callbacks/liquidity/BaselineV2/BaselineAxisLaunch.sol";
import {BALwithAllocatedAllowlist} from "src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";

// Generic contracts
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
        auctionHouse = BatchAuctionHouse(_envAddressNotZero("axis.BatchAuctionHouse"));

        vm.startBroadcast();

        // No spending approval necessary, since the callback will handle it

        // Create Fixed Price Batch auction
        IAuctionHouse.RoutingParams memory routingParams;
        routingParams.auctionType = toKeycode("FPBA");
        routingParams.baseToken = baseToken_;
        routingParams.quoteToken = quoteToken_;
        routingParams.callbacks = ICallback(callback_);
        routingParams.callbackData = abi.encode(BaselineAxisLaunch.CreateData({
            discoveryTickWidth: 100,
            allowlistParams: abi.encode(
                BALwithAllocatedAllowlist.AllocatedAllowlistCreateParams({
                    merkleRoot: merkleRoot
                })
            )
        }));

        IFixedPriceBatch.AuctionDataParams memory auctionDataParams;
        auctionDataParams.price = 1e18; // 1 quote tokens per base token
        auctionDataParams.minFillPercent = uint24(10_000); // 10%
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
        console2.log("Auction ends at timestamp", block.timestamp + duration);

        return lotId;
    }

    function cancelAuction(string calldata chain_, uint96 lotId_) public {
        _loadEnv(chain_);
        auctionHouse = BatchAuctionHouse(_envAddressNotZero("axis.BatchAuctionHouse"));
        vm.broadcast();
        auctionHouse.cancel(lotId_, bytes(""));
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

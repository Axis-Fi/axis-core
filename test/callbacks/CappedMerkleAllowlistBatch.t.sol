// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

import {CappedMerkleAllowlist} from "src/callbacks/allowlists/CappedMerkleAllowlist.sol";

import {WithSalts} from "test/lib/WithSalts.sol";

contract CappedMerkleAllowlistBatchTest is Test, Permit2User, WithSalts {
    using Callbacks for CappedMerkleAllowlist;

    address internal constant _OWNER = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _PROTOCOL = address(0x3);
    address internal constant _BUYER = address(0x4);
    address internal constant _BUYER_TWO = address(0x5);
    address internal constant _BASE_TOKEN = address(0x6);
    address internal constant _QUOTE_TOKEN = address(0x7);
    address internal constant _SELLER_TWO = address(0x8);
    address internal constant _BUYER_THREE = address(0x9);

    uint256 internal constant _LOT_CAPACITY = 10e18;

    uint96 internal _lotId = 1;

    BatchAuctionHouse internal _auctionHouse;
    CappedMerkleAllowlist internal _allowlist;

    uint256 internal constant _BUYER_LIMIT = 1e18;
    // Generated from: https://lab.miguelmota.com/merkletreejs/example/
    // Includes _BUYER, _BUYER_TWO but not _BUYER_THREE
    bytes32 internal constant _MERKLE_ROOT =
        0x40e51f1c845d99162de6c210a9eaff4729f433ac605be8f3cde6d2e0afa44aeb;
    bytes32[] internal _merkleProof;

    function setUp() public {
        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        BatchAuctionHouse auctionHouse = new BatchAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = BatchAuctionHouse(address(0x000000000000000000000000000000000000000A));
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        // Get the salt
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: false,
            onBid: true,
            onClaimProceeds: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });
        bytes memory args = abi.encode(address(_auctionHouse), permissions);
        bytes32 salt =
            _getSalt("CappedMerkleAllowlist", type(CappedMerkleAllowlist).creationCode, args);

        vm.broadcast();
        _allowlist = new CappedMerkleAllowlist{salt: salt}(address(_auctionHouse), permissions);

        _merkleProof.push(
            bytes32(0x421df1fa259221d02aa4956eb0d35ace318ca24c0a33a64c1af96cf67cf245b6)
        ); // Corresponds to _BUYER
            // _merkleProof.push(
            //     bytes32(0xa876da518a393dbd067dc72abfa08d475ed6447fca96d92ec3f9e7eba503ca61)
            // ); // Corresponds to _BUYER_TWO
    }

    modifier givenBatchOnCreate() {
        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT, _BUYER_LIMIT)
        );
        _;
    }

    function _onBid(uint96 lotId_, address buyer_, uint256 amount_) internal {
        vm.prank(address(_auctionHouse));
        _allowlist.onBid(lotId_, 1, buyer_, amount_, abi.encode(_merkleProof));
    }

    // onCreate
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the seller is not the seller for the allowlist
    //  [X] it sets the merkle root and buyer limit
    // [X] if the lot is already registered
    //  [X] it reverts
    // [X] it sets the merkle root and buyer limit

    function test_onCreate_callerNotAuctionHouse_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT, _BUYER_LIMIT)
        );
    }

    function test_onCreate_sellerNotSeller() public {
        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId,
            _SELLER_TWO,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT, _BUYER_LIMIT)
        );

        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");
        assertEq(_allowlist.lotMerkleRoot(_lotId), _MERKLE_ROOT, "lotMerkleRoot");
        assertEq(_allowlist.lotBuyerLimit(_lotId), _BUYER_LIMIT, "lotBuyerLimit");
    }

    function test_onCreate_alreadyRegistered_reverts() public givenBatchOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT, _BUYER_LIMIT)
        );
    }

    function test_onCreate() public givenBatchOnCreate {
        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");
        assertEq(_allowlist.lotMerkleRoot(_lotId), _MERKLE_ROOT, "lotMerkleRoot");
        assertEq(_allowlist.lotBuyerLimit(_lotId), _BUYER_LIMIT, "lotBuyerLimit");
    }

    // onBid
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the lot is not registered
    //  [X] it reverts
    // [X] if the buyer is not in the merkle tree
    //  [X] it reverts
    // [X] if the amount is greater than the buyer limit
    //  [X] it reverts
    // [X] if the previous buyer spent plus the amount is greater than the buyer limit
    //  [X] it reverts
    // [X] it updates the buyer spent

    function test_onBid_callerNotAuctionHouse_reverts() public givenBatchOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.onBid(_lotId, 1, _BUYER, 1e18, "");
    }

    function test_onBid_lotNotRegistered_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER, 1e18);
    }

    function test_onBid_buyerNotInMerkleTree_reverts() public givenBatchOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER_THREE, 1e18);
    }

    function test_onBid_amountGreaterThanBuyerLimit_reverts() public givenBatchOnCreate {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(CappedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER, _BUYER_LIMIT + 1);
    }

    function test_onBid_previousBuyerSpentPlusAmountGreaterThanBuyerLimit_reverts()
        public
        givenBatchOnCreate
    {
        _onBid(_lotId, _BUYER, _BUYER_LIMIT);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(CappedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER, 1);
    }

    function test_onBid(uint256 amount_) public givenBatchOnCreate {
        uint256 amount = bound(amount_, 1, _BUYER_LIMIT);

        _onBid(_lotId, _BUYER, amount);

        assertEq(_allowlist.lotBuyerSpent(_lotId, _BUYER), amount, "lotBuyerSpent");
    }
}

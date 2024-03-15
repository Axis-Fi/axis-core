// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {AuctionHouse} from "src/AuctionHouse.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

import {CappedMerkleAllowlist} from "src/callbacks/allowlists/CappedMerkleAllowlist.sol";

contract CappedMerkleAllowlistTest is Test, Permit2User {
    using Callbacks for CappedMerkleAllowlist;

    address internal constant _PROTOCOL = address(0x1);
    address internal constant _SELLER = address(0x2);
    address internal constant _BUYER = address(0x3);
    address internal constant _BUYER_TWO = address(0x4);
    address internal constant _BASE_TOKEN = address(0x5);
    address internal constant _QUOTE_TOKEN = address(0x6);
    address internal constant _SELLER_TWO = address(0x7);
    address internal constant _BUYER_THREE = address(0x8);

    uint96 internal constant _LOT_CAPACITY = 10e18;

    uint96 internal _lotId = 1;

    AuctionHouse internal _auctionHouse;
    CappedMerkleAllowlist internal _allowlist;

    uint96 internal _BUYER_LIMIT = 1e18;
    // Generated from: https://lab.miguelmota.com/merkletreejs/example/
    // Includes _BUYER, _BUYER_TWO but not _BUYER_THREE
    bytes32 internal _MERKLE_ROOT =
        0xf15a9691daa2aa0627e155c750530c1abcd6a00d93e4888dab4f50e11a29c36b;
    bytes32[] internal _MERKLE_PROOF;

    function setUp() public {
        _auctionHouse = new AuctionHouse(address(this), _PROTOCOL, _permit2Address);

        // // 10011000 = 0x98
        // // cast create2 -s 98 -i $(cat ./bytecode/CappedMerkleAllowlist98.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(CappedMerkleAllowlist).creationCode,
        //     abi.encode(address(_auctionHouse), Callbacks.Permissions({
        //         onCreate: true,
        //         onCancel: false,
        //         onCurate: false,
        //         onPurchase: true,
        //         onBid: true,
        //         onClaimProceeds: false,
        //         receiveQuoteTokens: false,
        //         sendBaseTokens: false
        //     }), _SELLER)
        // );
        // vm.writeFile(
        //     "./bytecode/CappedMerkleAllowlist98.bin",
        //     vm.toString(bytecode)
        // );

        bytes32 salt = bytes32(0x79c0dc0e1b403ae86906210c4f44234245b3b5ec7180f72f5b4680347f908435);
        vm.broadcast();
        _allowlist = new CappedMerkleAllowlist{salt: salt}(
            address(_auctionHouse),
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: true,
                onClaimProceeds: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            _SELLER
        );

        // _MERKLE_PROOF.push(
        //     bytes32(0x5b70e80538acdabd6137353b0f9d8d149f4dba91e8be2e7946e409bfdbe685b9)
        // ); // Corresponds to _BUYER
        _MERKLE_PROOF.push(
            bytes32(0x90b0d289ea211dca8e020c9cc8c5d6ba2f416fe15fa692b47184a4b946b2214d)
        ); // Corresponds to _BUYER_TWO
    }

    modifier givenOnCreate() {
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

    function _onPurchase(uint96 lotId_, address buyer_, uint96 amount_) internal {
        vm.prank(address(_auctionHouse));
        _allowlist.onPurchase(lotId_, buyer_, amount_, 0, false, abi.encode(_MERKLE_PROOF));
    }

    function _onBid(uint96 lotId_, address buyer_, uint96 amount_) internal {
        vm.prank(address(_auctionHouse));
        _allowlist.onBid(lotId_, 1, buyer_, amount_, abi.encode(_MERKLE_PROOF));
    }

    // onCreate
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the seller is not the seller for the allowlist
    //  [X] it reverts
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

    function test_onCreate_sellerNotSeller_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

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
    }

    function test_onCreate_alreadyRegistered_reverts() public givenOnCreate {
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

    function test_onCreate() public givenOnCreate {
        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");
        assertEq(_allowlist.lotMerkleRoot(_lotId), _MERKLE_ROOT, "lotMerkleRoot");
        assertEq(_allowlist.lotBuyerLimit(_lotId), _BUYER_LIMIT, "lotBuyerLimit");
    }

    // onPurchase
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

    function test_onPurchase_callerNotAuctionHouse_reverts() public givenOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.onPurchase(_lotId, _BUYER, 1e18, 0, false, "");
    }

    function test_onPurchase_lotNotRegistered_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, 1e18);
    }

    function test_onPurchase_buyerNotInMerkleTree_reverts() public givenOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER_THREE, 1e18);
    }

    function test_onPurchase_amountGreaterThanBuyerLimit_reverts() public givenOnCreate {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(CappedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, _BUYER_LIMIT + 1);
    }

    function test_onPurchase_previousBuyerSpentPlusAmountGreaterThanBuyerLimit_reverts()
        public
        givenOnCreate
    {
        _onPurchase(_lotId, _BUYER, _BUYER_LIMIT);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(CappedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, 1);
    }

    function test_onPurchase(uint96 amount_) public givenOnCreate {
        uint96 amount = uint96(bound(amount_, 1, _BUYER_LIMIT));

        _onPurchase(_lotId, _BUYER, amount);

        assertEq(_allowlist.lotBuyerSpent(_lotId, _BUYER), amount, "lotBuyerSpent");
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

    function test_onBid_callerNotAuctionHouse_reverts() public givenOnCreate {
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

    function test_onBid_buyerNotInMerkleTree_reverts() public givenOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER_THREE, 1e18);
    }

    function test_onBid_amountGreaterThanBuyerLimit_reverts() public givenOnCreate {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(CappedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER, _BUYER_LIMIT + 1);
    }

    function test_onBid_previousBuyerSpentPlusAmountGreaterThanBuyerLimit_reverts()
        public
        givenOnCreate
    {
        _onBid(_lotId, _BUYER, _BUYER_LIMIT);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(CappedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onBid(_lotId, _BUYER, 1);
    }

    function test_onBid(uint96 amount_) public givenOnCreate {
        uint96 amount = uint96(bound(amount_, 1, _BUYER_LIMIT));

        _onBid(_lotId, _BUYER, amount);

        assertEq(_allowlist.lotBuyerSpent(_lotId, _BUYER), amount, "lotBuyerSpent");
    }
}

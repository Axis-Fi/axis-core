// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";
import {BatchAuctionHouse} from "src/BatchAuctionHouse.sol";

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

    uint256 internal constant _LOT_CAPACITY = 10e18;

    uint96 internal _lotId = 1;

    AtomicAuctionHouse internal _atomicAuctionHouse;
    BatchAuctionHouse internal _batchAuctionHouse;
    CappedMerkleAllowlist internal _atomicAllowlist;
    CappedMerkleAllowlist internal _batchAllowlist;

    uint256 internal _BUYER_LIMIT = 1e18;
    // Generated from: https://lab.miguelmota.com/merkletreejs/example/
    // Includes _BUYER, _BUYER_TWO but not _BUYER_THREE
    bytes32 internal _MERKLE_ROOT =
        0xf15a9691daa2aa0627e155c750530c1abcd6a00d93e4888dab4f50e11a29c36b;
    bytes32[] internal _MERKLE_PROOF;

    function setUp() public {
        _atomicAuctionHouse = new AtomicAuctionHouse(address(this), _PROTOCOL, _permit2Address);
        _batchAuctionHouse = new BatchAuctionHouse(address(this), _PROTOCOL, _permit2Address);

        // // 10010000 = 0x90
        // // cast create2 -s 90 -i $(cat ./bytecode/CappedMerkleAllowlistAtomic90.bin)
        // bytes memory bytecode = abi.encodePacked(
        //     type(CappedMerkleAllowlist).creationCode,
        //     abi.encode(
        //         address(_atomicAuctionHouse),
        //         Callbacks.Permissions({
        //             onCreate: true,
        //             onCancel: false,
        //             onCurate: false,
        //             onPurchase: true,
        //             onBid: false,
        //             onClaimProceeds: false,
        //             receiveQuoteTokens: false,
        //             sendBaseTokens: false
        //         }),
        //         _SELLER
        //     )
        // );
        // vm.writeFile("./bytecode/CappedMerkleAllowlistAtomic90.bin", vm.toString(bytecode));
        // // 10001000 = 0x88
        // // cast create2 -s 88 -i $(cat ./bytecode/CappedMerkleAllowlistBatch88.bin)
        // bytecode = abi.encodePacked(
        //     type(CappedMerkleAllowlist).creationCode,
        //     abi.encode(
        //         address(_batchAuctionHouse),
        //         Callbacks.Permissions({
        //             onCreate: true,
        //             onCancel: false,
        //             onCurate: false,
        //             onPurchase: false,
        //             onBid: true,
        //             onClaimProceeds: false,
        //             receiveQuoteTokens: false,
        //             sendBaseTokens: false
        //         }),
        //         _SELLER
        //     )
        // );
        // vm.writeFile("./bytecode/CappedMerkleAllowlistBatch88.bin", vm.toString(bytecode));

        bytes32 atomicSalt =
            bytes32(0xc4593baf2f710bfc172b576140b3fdc420c18f8c5eed79407dd77ea042986371);
        vm.broadcast();
        _atomicAllowlist = new CappedMerkleAllowlist{salt: atomicSalt}(
            address(_atomicAuctionHouse),
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: true,
                onBid: false,
                onClaimProceeds: false,
                receiveQuoteTokens: false,
                sendBaseTokens: false
            }),
            _SELLER
        );

        bytes32 batchSalt =
            bytes32(0x1cb7a271aa2536ad06f1246cf64e56d66323cca283886a0ae6e13225ae85619d);
        vm.broadcast();
        _batchAllowlist = new CappedMerkleAllowlist{salt: batchSalt}(
            address(_batchAuctionHouse),
            Callbacks.Permissions({
                onCreate: true,
                onCancel: false,
                onCurate: false,
                onPurchase: false,
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

    modifier givenAtomicOnCreate() {
        vm.prank(address(_atomicAuctionHouse));
        _atomicAllowlist.onCreate(
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

    modifier givenBatchOnCreate() {
        vm.prank(address(_batchAuctionHouse));
        _batchAllowlist.onCreate(
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

    function _onPurchase(uint96 lotId_, address buyer_, uint256 amount_) internal {
        vm.prank(address(_atomicAuctionHouse));
        _atomicAllowlist.onPurchase(lotId_, buyer_, amount_, 0, false, abi.encode(_MERKLE_PROOF));
    }

    function _onBid(uint96 lotId_, address buyer_, uint256 amount_) internal {
        vm.prank(address(_batchAuctionHouse));
        _batchAllowlist.onBid(lotId_, 1, buyer_, amount_, abi.encode(_MERKLE_PROOF));
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

        _atomicAllowlist.onCreate(
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

        vm.prank(address(_atomicAuctionHouse));
        _atomicAllowlist.onCreate(
            _lotId,
            _SELLER_TWO,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT, _BUYER_LIMIT)
        );
    }

    function test_onCreate_alreadyRegistered_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_InvalidParams.selector);
        vm.expectRevert(err);

        vm.prank(address(_atomicAuctionHouse));
        _atomicAllowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(_MERKLE_ROOT, _BUYER_LIMIT)
        );
    }

    function test_onCreate() public givenAtomicOnCreate {
        assertEq(_atomicAllowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");
        assertEq(_atomicAllowlist.lotMerkleRoot(_lotId), _MERKLE_ROOT, "lotMerkleRoot");
        assertEq(_atomicAllowlist.lotBuyerLimit(_lotId), _BUYER_LIMIT, "lotBuyerLimit");
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

    function test_onPurchase_callerNotAuctionHouse_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _atomicAllowlist.onPurchase(_lotId, _BUYER, 1e18, 0, false, "");
    }

    function test_onPurchase_lotNotRegistered_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, 1e18);
    }

    function test_onPurchase_buyerNotInMerkleTree_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER_THREE, 1e18);
    }

    function test_onPurchase_amountGreaterThanBuyerLimit_reverts() public givenAtomicOnCreate {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(CappedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, _BUYER_LIMIT + 1);
    }

    function test_onPurchase_previousBuyerSpentPlusAmountGreaterThanBuyerLimit_reverts()
        public
        givenAtomicOnCreate
    {
        _onPurchase(_lotId, _BUYER, _BUYER_LIMIT);

        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(CappedMerkleAllowlist.Callback_ExceedsLimit.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, 1);
    }

    function test_onPurchase(uint256 amount_) public givenAtomicOnCreate {
        uint256 amount = bound(amount_, 1, _BUYER_LIMIT);

        _onPurchase(_lotId, _BUYER, amount);

        assertEq(_atomicAllowlist.lotBuyerSpent(_lotId, _BUYER), amount, "lotBuyerSpent");
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

        _batchAllowlist.onBid(_lotId, 1, _BUYER, 1e18, "");
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

        assertEq(_batchAllowlist.lotBuyerSpent(_lotId, _BUYER), amount, "lotBuyerSpent");
    }
}

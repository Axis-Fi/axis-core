// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {Permit2User} from "test/lib/permit2/Permit2User.sol";

import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {AtomicAuctionHouse} from "src/AtomicAuctionHouse.sol";

import {BaseCallback} from "src/callbacks/BaseCallback.sol";

import {TokenAllowlist, ITokenBalance} from "src/callbacks/allowlists/TokenAllowlist.sol";

import {toVeecode} from "src/modules/Keycode.sol";
import {WithSalts} from "test/lib/WithSalts.sol";
import {TestConstants} from "test/Constants.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract TokenAllowlistAtomicTest is Test, Permit2User, WithSalts, TestConstants {
    using Callbacks for TokenAllowlist;

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

    AtomicAuctionHouse internal _auctionHouse;
    TokenAllowlist internal _allowlist;

    MockERC20 internal _token;
    uint96 internal constant _BUYER_LIMIT = 1e18;

    function setUp() public {
        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        AtomicAuctionHouse auctionHouse = new AtomicAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = AtomicAuctionHouse(_AUCTION_HOUSE);
        vm.etch(address(_auctionHouse), address(auctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        // Get the salt
        Callbacks.Permissions memory permissions = Callbacks.Permissions({
            onCreate: true,
            onCancel: false,
            onCurate: false,
            onPurchase: true,
            onBid: false,
            onSettle: false,
            receiveQuoteTokens: false,
            sendBaseTokens: false
        });
        bytes memory args = abi.encode(address(_auctionHouse), permissions);
        bytes32 salt = _getTestSalt("TokenAllowlist", type(TokenAllowlist).creationCode, args);

        vm.broadcast();
        _allowlist = new TokenAllowlist{salt: salt}(address(_auctionHouse), permissions);

        // Create the token
        _token = new MockERC20("Gating Token", "GT", 18);
    }

    modifier givenAtomicOnCreate() {
        vm.prank(address(_auctionHouse));
        _allowlist.onCreate(
            _lotId,
            _SELLER,
            _BASE_TOKEN,
            _QUOTE_TOKEN,
            _LOT_CAPACITY,
            false,
            abi.encode(address(_token), _BUYER_LIMIT)
        );
        _;
    }

    function _onPurchase(uint96 lotId_, address buyer_, uint256 amount_) internal {
        vm.prank(address(_auctionHouse));
        _allowlist.onPurchase(lotId_, buyer_, amount_, 0, false, abi.encode(""));
    }

    // onCreate
    // [X] when the allowlist parameters are in an incorrect format
    //  [X] it reverts
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the seller is not the seller for the allowlist
    //  [X] it sets the token address and buyer limit
    // [X] if the lot is already registered
    //  [X] it reverts
    // [X] if the token is not a contract
    //  [X] it reverts
    // [X] if the token balance is not retrievable
    //  [X] it reverts
    // [X] it sets the token address and buyer limit

    function test_onCreate_allowlistParametersIncorrectFormat_reverts() public {
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
            abi.encode(address(_token), _BUYER_LIMIT, uint256(20))
        );
    }

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
            abi.encode(address(_token), _BUYER_LIMIT)
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
            abi.encode(address(_token), _BUYER_LIMIT)
        );

        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");

        (ITokenBalance token_, uint256 threshold_) = _allowlist.lotChecks(_lotId);
        assertEq(address(token_), address(token_), "token");
        assertEq(threshold_, _BUYER_LIMIT, "threshold");
    }

    function test_onCreate_alreadyRegistered_reverts() public givenAtomicOnCreate {
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
            abi.encode(address(_token), _BUYER_LIMIT)
        );
    }

    function test_onCreate_tokenNotContract_reverts() public {
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
            abi.encode(address(_SELLER), _BUYER_LIMIT)
        );
    }

    function test_onCreate_tokenBalanceNotRetrievable_reverts() public {
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
            abi.encode(_AUCTION_HOUSE, _BUYER_LIMIT)
        );
    }

    function test_onCreate() public givenAtomicOnCreate {
        assertEq(_allowlist.lotIdRegistered(_lotId), true, "lotIdRegistered");

        (ITokenBalance token_, uint256 threshold_) = _allowlist.lotChecks(_lotId);
        assertEq(address(token_), address(token_), "token");
        assertEq(threshold_, _BUYER_LIMIT, "threshold");
    }

    // onPurchase
    // [X] if the caller is not the auction house
    //  [X] it reverts
    // [X] if the lot is not registered
    //  [X] it reverts
    // [X] if the buyer has below the threshold
    //  [X] it reverts
    // [X] it success

    function test_onPurchase_callerNotAuctionHouse_reverts() public givenAtomicOnCreate {
        // Mint the token balance
        _token.mint(_BUYER, _BUYER_LIMIT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _allowlist.onBid(_lotId, 1, _BUYER, 1e18, "");
    }

    function test_onPurchase_lotNotRegistered_reverts() public {
        // Mint the token balance
        _token.mint(_BUYER, _BUYER_LIMIT);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, 1e18);
    }

    function test_onPurchase_belowThreshold_reverts(
        uint256 bidAmount_,
        uint256 tokenBalance_
    ) public givenAtomicOnCreate {
        uint256 bidAmount = bound(bidAmount_, 1, _BUYER_LIMIT);
        uint256 tokenBalance = bound(tokenBalance_, 0, _BUYER_LIMIT - 1);

        // Mint the token balance
        _token.mint(_BUYER, tokenBalance);

        // Expect revert
        bytes memory err = abi.encodeWithSelector(BaseCallback.Callback_NotAuthorized.selector);
        vm.expectRevert(err);

        _onPurchase(_lotId, _BUYER, bidAmount);
    }

    function test_onPurchase(
        uint256 bidAmount_,
        uint256 tokenBalance_
    ) public givenAtomicOnCreate {
        uint256 bidAmount = bound(bidAmount_, 1, _BUYER_LIMIT);
        uint256 tokenBalance = bound(tokenBalance_, _BUYER_LIMIT, _BUYER_LIMIT * 2);

        // Mint the token balance
        _token.mint(_BUYER, tokenBalance);

        _onPurchase(_lotId, _BUYER, bidAmount);
    }
}

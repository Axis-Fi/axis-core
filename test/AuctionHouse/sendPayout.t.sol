// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Test} from "@forge-std-1.9.1/Test.sol";
import {Transfer} from "../../src/lib/Transfer.sol";

import {MockAuctionHouse} from "./MockAuctionHouse.sol";
import {MockAtomicAuctionModule} from "../modules/Auction/MockAtomicAuctionModule.sol";
import {MockDerivativeModule} from "../modules/derivatives/mocks/MockDerivativeModule.sol";
import {MockCondenserModule} from "../modules/Condenser/MockCondenserModule.sol";
import {MockFeeOnTransferERC20} from "../lib/mocks/MockFeeOnTransferERC20.sol";
import {Permit2User} from "../lib/permit2/Permit2User.sol";
import {MockWrappedDerivative} from "../lib/mocks/MockWrappedDerivative.sol";

import {ERC20} from "@solmate-6.8.0/tokens/ERC20.sol";
import {ICallback} from "../../src/interfaces/ICallback.sol";
import {IAuctionHouse} from "../../src/interfaces/IAuctionHouse.sol";

import {Veecode, toVeecode} from "../../src/modules/Modules.sol";

contract SendPayoutTest is Test, Permit2User {
    MockAuctionHouse internal _auctionHouse;
    MockAtomicAuctionModule internal _mockAuctionModule;
    MockDerivativeModule internal _mockDerivativeModule;
    MockCondenserModule internal _mockCondenserModule;
    MockWrappedDerivative internal _derivativeWrappedImplementation;

    address internal constant _OWNER = address(0x1);
    address internal constant _PROTOCOL = address(0x2);
    address internal constant _USER = address(0x3);
    address internal constant _SELLER = address(0x4);
    address internal constant _RECIPIENT = address(0x5);

    uint48 internal constant _DERIVATIVE_EXPIRY = 1 days;

    // Function parameters
    uint96 internal _lotId = 1;
    uint256 internal _payoutAmount = 10e18;
    MockFeeOnTransferERC20 internal _quoteToken;
    MockFeeOnTransferERC20 internal _payoutToken;
    Veecode internal _derivativeReference;
    uint256 internal _derivativeTokenId;
    bytes internal _derivativeParams;
    bool internal _wrapDerivative;
    ERC20 internal _wrappedDerivative;
    uint256 internal _auctionOutputMultiplier;
    bytes internal _auctionOutput;

    IAuctionHouse.Routing internal _routingParams;

    function setUp() public {
        // Set reasonable starting block
        vm.warp(1_000_000);

        // Create an AuctionHouse at a deterministic address, since it is used as input to callbacks
        MockAuctionHouse mockAuctionHouse = new MockAuctionHouse(_OWNER, _PROTOCOL, _permit2Address);
        _auctionHouse = MockAuctionHouse(address(0x000000000000000000000000000000000000000A));
        vm.etch(address(_auctionHouse), address(mockAuctionHouse).code);
        vm.store(address(_auctionHouse), bytes32(uint256(0)), bytes32(abi.encode(_OWNER))); // Owner
        vm.store(address(_auctionHouse), bytes32(uint256(6)), bytes32(abi.encode(1))); // Reentrancy
        vm.store(address(_auctionHouse), bytes32(uint256(10)), bytes32(abi.encode(_PROTOCOL))); // Protocol

        _mockAuctionModule = new MockAtomicAuctionModule(address(_auctionHouse));
        _mockDerivativeModule = new MockDerivativeModule(address(_auctionHouse));

        vm.prank(_OWNER);
        _auctionHouse.installModule(_mockAuctionModule);

        _derivativeWrappedImplementation = new MockWrappedDerivative("name", "symbol", 18);
        _mockDerivativeModule.setWrappedImplementation(_derivativeWrappedImplementation);

        _mockCondenserModule = new MockCondenserModule(address(_auctionHouse));

        _quoteToken = new MockFeeOnTransferERC20("Quote Token", "QUOTE", 18);
        _quoteToken.setTransferFee(0);

        _payoutToken = new MockFeeOnTransferERC20("Payout Token", "PAYOUT", 18);
        _payoutToken.setTransferFee(0);

        _derivativeReference = toVeecode(bytes7(""));
        _derivativeParams = bytes("");
        _wrapDerivative = false;
        _auctionOutputMultiplier = 2;
        _auctionOutput =
            abi.encode(MockAtomicAuctionModule.Output({multiplier: _auctionOutputMultiplier})); // Does nothing unless the condenser is set

        _routingParams = IAuctionHouse.Routing({
            auctionReference: _mockAuctionModule.VEECODE(),
            seller: _SELLER,
            baseToken: address(_payoutToken),
            quoteToken: address(_quoteToken),
            callbacks: ICallback(address(0)),
            derivativeReference: _derivativeReference,
            derivativeParams: _derivativeParams,
            wrapDerivative: _wrapDerivative,
            funding: 0
        });
    }

    modifier givenTokenTakesFeeOnTransfer() {
        _payoutToken.setTransferFee(1000);
        _;
    }

    modifier givenAuctionHouseHasBalance(
        uint256 amount_
    ) {
        _payoutToken.mint(address(_auctionHouse), amount_);
        _;
    }

    // ========== Non-hooks flow ========== //

    // [X] given the auction does not have hooks defined
    //  [X] given transferring the payout token would result in a lesser amount being received
    //   [X] it reverts
    //  [X] it succeeds - transfers the payout from the _auctionHouse to the recipient

    function test_noHooks_feeOnTransfer_reverts()
        public
        givenAuctionHouseHasBalance(_payoutAmount)
        givenTokenTakesFeeOnTransfer
    {
        // Expect revert
        bytes memory err =
            abi.encodeWithSelector(Transfer.UnsupportedToken.selector, address(_payoutToken));
        vm.expectRevert(err);

        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);
    }

    function test_noHooks_insufficientBalance_reverts() public {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FAILED"));

        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);
    }

    function test_noHooks() public givenAuctionHouseHasBalance(_payoutAmount) {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);

        // Check balances
        assertEq(_payoutToken.balanceOf(_USER), 0, "user balance mismatch");
        assertEq(_payoutToken.balanceOf(_SELLER), 0, "seller balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)), 0, "_auctionHouse balance mismatch"
        );
        assertEq(_payoutToken.balanceOf(_RECIPIENT), _payoutAmount, "recipient balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_mockDerivativeModule)),
            0,
            "derivative module balance mismatch"
        );
    }

    // ========== Derivative flow ========== //

    // [X] given the base token is a derivative
    //  [X] given a condenser is set
    //   [X] given the derivative parameters are invalid
    //     [X] it reverts
    //   [X] it uses the condenser to determine derivative parameters
    //  [X] given a condenser is not set
    //   [X] given the derivative is wrapped
    //    [X] given the derivative parameters are invalid
    //     [X] it reverts
    //    [X] it mints wrapped derivative tokens to the recipient using the derivative module
    //   [X] given the derivative is not wrapped
    //    [X] given the derivative parameters are invalid
    //     [X] it reverts
    //    [X] it mints derivative tokens to the recipient using the derivative module

    modifier givenAuctionHasDerivative() {
        // Install the derivative module
        vm.prank(_OWNER);
        _auctionHouse.installModule(_mockDerivativeModule);

        // Deploy a new derivative token
        MockDerivativeModule.DerivativeParams memory deployParams =
            MockDerivativeModule.DerivativeParams({expiry: _DERIVATIVE_EXPIRY, multiplier: 0});
        (uint256 tokenId,) =
            _mockDerivativeModule.deploy(address(_payoutToken), abi.encode(deployParams), false);

        // Update parameters
        _derivativeReference = _mockDerivativeModule.VEECODE();
        _derivativeTokenId = tokenId;
        _derivativeParams = abi.encode(deployParams);
        _routingParams.derivativeReference = _derivativeReference;
        _routingParams.derivativeParams = _derivativeParams;
        _;
    }

    modifier givenDerivativeIsWrapped() {
        // Deploy a new wrapped derivative token
        MockDerivativeModule.DerivativeParams memory deployParams =
            MockDerivativeModule.DerivativeParams({expiry: _DERIVATIVE_EXPIRY + 1, multiplier: 0}); // Different expiry which leads to a different token id
        (uint256 tokenId_, address wrappedToken_) =
            _mockDerivativeModule.deploy(address(_payoutToken), abi.encode(deployParams), true);

        // Update parameters
        _wrappedDerivative = ERC20(wrappedToken_);
        _derivativeTokenId = tokenId_;
        _derivativeParams = abi.encode(deployParams);
        _routingParams.derivativeParams = _derivativeParams;

        _wrapDerivative = true;
        _routingParams.wrapDerivative = _wrapDerivative;
        _;
    }

    modifier givenDerivativeHasCondenser() {
        // Install the condenser module
        vm.prank(_OWNER);
        _auctionHouse.installModule(_mockCondenserModule);

        // Set the condenser
        vm.startPrank(_OWNER);
        _auctionHouse.setCondenser(
            _mockAuctionModule.VEECODE(),
            _mockDerivativeModule.VEECODE(),
            _mockCondenserModule.VEECODE()
        );
        vm.stopPrank();
        _;
    }

    modifier givenDerivativeParamsAreInvalid() {
        _derivativeParams = abi.encode("one", "two", uint256(2));
        _routingParams.derivativeParams = _derivativeParams;
        _;
    }

    function test_derivative_invalidParams()
        public
        givenAuctionHouseHasBalance(_payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeParamsAreInvalid
    {
        // Expect revert while decoding parameters
        vm.expectRevert();

        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);
    }

    function test_derivative_insufficientBalance_reverts() public givenAuctionHasDerivative {
        // Expect revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);
    }

    function test_derivative()
        public
        givenAuctionHouseHasBalance(_payoutAmount)
        givenAuctionHasDerivative
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);

        // Check balances of the derivative token
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_USER, _derivativeTokenId),
            0,
            "derivative token: user balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_SELLER, _derivativeTokenId),
            0,
            "derivative token: seller balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(
                address(_auctionHouse), _derivativeTokenId
            ),
            0,
            "derivative token: _auctionHouse balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_RECIPIENT, _derivativeTokenId),
            _payoutAmount,
            "derivative token: recipient balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(
                address(_mockDerivativeModule), _derivativeTokenId
            ),
            0,
            "derivative token: derivative module balance mismatch"
        );

        // Check balances of payout token
        assertEq(_payoutToken.balanceOf(_USER), 0, "payout token: user balance mismatch");
        assertEq(_payoutToken.balanceOf(_SELLER), 0, "payout token: seller balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)),
            0,
            "payout token: _auctionHouse balance mismatch"
        );
        assertEq(_payoutToken.balanceOf(_RECIPIENT), 0, "payout token: recipient balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_mockDerivativeModule)),
            _payoutAmount,
            "payout token: derivative module balance mismatch"
        );
    }

    function test_derivative_wrapped()
        public
        givenAuctionHouseHasBalance(_payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeIsWrapped
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);

        // Check balances of the wrapped derivative token
        assertEq(
            _wrappedDerivative.balanceOf(_USER),
            0,
            "wrapped derivative token: user balance mismatch"
        );
        assertEq(
            _wrappedDerivative.balanceOf(_SELLER),
            0,
            "wrapped derivative token: seller balance mismatch"
        );
        assertEq(
            _wrappedDerivative.balanceOf(address(_auctionHouse)),
            0,
            "wrapped derivative token: _auctionHouse balance mismatch"
        );
        assertEq(
            _wrappedDerivative.balanceOf(_RECIPIENT),
            _payoutAmount,
            "wrapped derivative token: recipient balance mismatch"
        );
        assertEq(
            _wrappedDerivative.balanceOf(address(_mockDerivativeModule)),
            0,
            "wrapped derivative token: derivative module balance mismatch"
        );

        // Check balances of the derivative token
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_USER, _derivativeTokenId),
            0,
            "derivative token: user balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_SELLER, _derivativeTokenId),
            0,
            "derivative token: seller balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(
                address(_auctionHouse), _derivativeTokenId
            ),
            0,
            "derivative token: _auctionHouse balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_RECIPIENT, _derivativeTokenId),
            0, // No raw derivative
            "derivative token: recipient balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(
                address(_mockDerivativeModule), _derivativeTokenId
            ),
            0,
            "derivative token: derivative module balance mismatch"
        );

        // Check balances of payout token
        assertEq(_payoutToken.balanceOf(_USER), 0, "payout token: user balance mismatch");
        assertEq(_payoutToken.balanceOf(_SELLER), 0, "payout token: seller balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)),
            0,
            "payout token: _auctionHouse balance mismatch"
        );
        assertEq(_payoutToken.balanceOf(_RECIPIENT), 0, "payout token: recipient balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_mockDerivativeModule)),
            _payoutAmount,
            "payout token: derivative module balance mismatch"
        );
    }

    function test_derivative_wrapped_invalidParams()
        public
        givenAuctionHouseHasBalance(_payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeIsWrapped
        givenDerivativeParamsAreInvalid
    {
        // Expect revert while decoding parameters
        vm.expectRevert();

        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);
    }

    function test_derivative_condenser_invalidParams_reverts()
        public
        givenAuctionHouseHasBalance(_payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeHasCondenser
        givenDerivativeParamsAreInvalid
    {
        // Expect revert while decoding parameters
        vm.expectRevert();

        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);
    }

    function test_derivative_condenser()
        public
        givenAuctionHouseHasBalance(_payoutAmount)
        givenAuctionHasDerivative
        givenDerivativeHasCondenser
    {
        // Call
        vm.prank(_USER);
        _auctionHouse.sendPayout(_RECIPIENT, _payoutAmount, _routingParams, _auctionOutput);

        // Check balances of the derivative token
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_USER, _derivativeTokenId),
            0,
            "user balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_SELLER, _derivativeTokenId),
            0,
            "seller balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(
                address(_auctionHouse), _derivativeTokenId
            ),
            0,
            "_auctionHouse balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(_RECIPIENT, _derivativeTokenId),
            _payoutAmount * _auctionOutputMultiplier, // Condenser multiplies the payout
            "recipient balance mismatch"
        );
        assertEq(
            _mockDerivativeModule.derivativeToken().balanceOf(
                address(_mockDerivativeModule), _derivativeTokenId
            ),
            0,
            "derivative module balance mismatch"
        );

        // Check balances of payout token
        assertEq(_payoutToken.balanceOf(_USER), 0, "user balance mismatch");
        assertEq(_payoutToken.balanceOf(_SELLER), 0, "seller balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_auctionHouse)), 0, "_auctionHouse balance mismatch"
        );
        assertEq(_payoutToken.balanceOf(_RECIPIENT), 0, "recipient balance mismatch");
        assertEq(
            _payoutToken.balanceOf(address(_mockDerivativeModule)),
            _payoutAmount,
            "derivative module balance mismatch"
        );
    }
}

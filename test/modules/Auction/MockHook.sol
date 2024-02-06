// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {Auctioneer} from "src/bases/Auctioneer.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract MockHook is IHooks {
    using SafeTransferLib for ERC20;

    ERC20 public quoteToken;
    ERC20 public payoutToken;
    ERC20[] public tokens;

    address[] public balanceAddresses;

    /// @notice     Use this to determine if the hook was called at the right time
    mapping(ERC20 token_ => mapping(address user_ => uint256 balance_)) public preHookBalances;

    /// @notice     Use this to determine if the hook was called
    bool public preHookCalled;
    bool public preHookReverts;

    /// @notice     Use this to determine if the hook was called at the right time
    mapping(ERC20 token_ => mapping(address user_ => uint256 balance_)) public midHookBalances;

    /// @notice     Use this to determine if the hook was called
    bool public midHookCalled;
    bool public midHookReverts;
    uint256 public midHookMultiplier;

    /// @notice     Use this to determine if the hook was called at the right time
    mapping(ERC20 token_ => mapping(address user_ => uint256 balance_)) public postHookBalances;

    /// @notice     Use this to determine if the hook was called
    bool public postHookCalled;
    bool public postHookReverts;

    uint256 public preAuctionCreateMultiplier;

    constructor(address quoteToken_, address payoutToken_) {
        quoteToken = ERC20(quoteToken_);
        payoutToken = ERC20(payoutToken_);

        tokens = new ERC20[](2);
        tokens[0] = quoteToken;
        tokens[1] = payoutToken;

        midHookMultiplier = 10_000;
    }

    function pre(uint96, uint256) external override {
        if (preHookReverts) {
            revert("revert");
        }

        preHookCalled = true;

        // Iterate over tokens and balance addresses
        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20 token = tokens[i];
            if (address(token) == address(0)) {
                continue;
            }

            for (uint256 j = 0; j < balanceAddresses.length; j++) {
                preHookBalances[token][balanceAddresses[j]] = token.balanceOf(balanceAddresses[j]);
            }
        }

        // Does nothing at the moment
    }

    function setPreHookReverts(bool reverts_) external {
        preHookReverts = reverts_;
    }

    function mid(uint96, uint256, uint256 payout_) external override {
        if (midHookReverts) {
            revert("revert");
        }

        midHookCalled = true;

        // Iterate over tokens and balance addresses
        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20 token = tokens[i];
            if (address(token) == address(0)) {
                continue;
            }

            for (uint256 j = 0; j < balanceAddresses.length; j++) {
                midHookBalances[token][balanceAddresses[j]] = token.balanceOf(balanceAddresses[j]);
            }
        }

        uint256 actualPayout = (payout_ * midHookMultiplier) / 10_000;

        // Has to transfer the payout token to the router
        ERC20(payoutToken).safeTransfer(msg.sender, actualPayout);
    }

    function setMidHookReverts(bool reverts_) external {
        midHookReverts = reverts_;
    }

    function setMidHookMultiplier(uint256 multiplier_) external {
        midHookMultiplier = multiplier_;
    }

    function post(uint96, uint256) external override {
        if (postHookReverts) {
            revert("revert");
        }

        postHookCalled = true;

        // Iterate over tokens and balance addresses
        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20 token = tokens[i];
            if (address(token) == address(0)) {
                continue;
            }

            for (uint256 j = 0; j < balanceAddresses.length; j++) {
                postHookBalances[token][balanceAddresses[j]] = token.balanceOf(balanceAddresses[j]);
            }
        }

        // Does nothing at the moment
    }

    function setPostHookReverts(bool reverts_) external {
        postHookReverts = reverts_;
    }

    function setBalanceAddresses(address[] memory addresses_) external {
        for (uint256 i = 0; i < addresses_.length; i++) {
            balanceAddresses.push(addresses_[i]);
        }
    }

    function setQuoteToken(address quoteToken_) external {
        quoteToken = ERC20(quoteToken_);
    }

    function setPayoutToken(address payoutToken_) external {
        payoutToken = ERC20(payoutToken_);
    }

    function setPreAuctionCreateMultiplier(uint256 multiplier_) external {
        preAuctionCreateMultiplier = multiplier_;
    }

    function preAuctionCreate(uint96 lotId_) external override {
        // Get the lot information
        Auctioneer.Routing memory routing = Auctioneer(msg.sender).getRouting(lotId_);

        // If pre-funding is required
        if (routing.prefunding > 0) {
            // Get the capacity
            uint256 capacity = Auctioneer(msg.sender).remainingCapacity(lotId_);

            // If the multiplier is set, apply that
            if (preAuctionCreateMultiplier > 0) {
                capacity = (capacity * preAuctionCreateMultiplier) / 10_000;
            }

            // Approve transfer
            routing.baseToken.safeApprove(address(msg.sender), capacity);

            // Transfer the base token to the auctioneer
            routing.baseToken.safeTransfer(msg.sender, capacity);
        }
    }
}

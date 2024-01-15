// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IHooks} from "src/bases/Auctioneer.sol";

contract MockHook is IHooks {
    address public preHookToken;
    address public preHookUser;
    uint256 public preHookBalance;
    bool public preHookReverts;

    address public midHookToken;
    address public midHookUser;
    uint256 public midHookBalance;
    bool public midHookReverts;

    address public postHookToken;
    address public postHookUser;
    uint256 public postHookBalance;
    bool public postHookReverts;

    function pre(uint256, uint256) external override {
        if (preHookReverts) {
            revert("revert");
        }

        if (preHookToken != address(0) && preHookUser != address(0)) {
            preHookBalance = ERC20(preHookToken).balanceOf(preHookUser);
        } else {
            preHookBalance = 0;
        }
    }

    function setPreHookValues(address token_, address user_) external {
        preHookToken = token_;
        preHookUser = user_;
    }

    function setPreHookReverts(bool reverts_) external {
        preHookReverts = reverts_;
    }

    function mid(uint256, uint256, uint256) external override {
        if (midHookReverts) {
            revert("revert");
        }

        if (midHookToken != address(0) && midHookUser != address(0)) {
            midHookBalance = ERC20(midHookToken).balanceOf(midHookUser);
        } else {
            midHookBalance = 0;
        }
    }

    function setMidHookValues(address token_, address user_) external {
        midHookToken = token_;
        midHookUser = user_;
    }

    function setMidHookReverts(bool reverts_) external {
        midHookReverts = reverts_;
    }

    function post(uint256, uint256) external override {
        if (postHookReverts) {
            revert("revert");
        }

        if (postHookToken != address(0) && postHookUser != address(0)) {
            postHookBalance = ERC20(postHookToken).balanceOf(postHookUser);
        } else {
            postHookBalance = 0;
        }
    }

    function setPostHookValues(address token_, address user_) external {
        postHookToken = token_;
        postHookUser = user_;
    }

    function setPostHookReverts(bool reverts_) external {
        postHookReverts = reverts_;
    }
}

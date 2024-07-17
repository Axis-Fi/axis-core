// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {MockERC20} from "@solmate-6.7.0/test/utils/mocks/MockERC20.sol";

contract MockFeeOnTransferERC20 is MockERC20 {
    uint256 public transferFee;
    bool public revertOnZero;

    mapping(address => bool) public blacklist;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) MockERC20(name_, symbol_, decimals_) {}

    function setTransferFee(uint256 transferFee_) external {
        transferFee = transferFee_;
    }

    function setRevertOnZero(bool revertOnZero_) external {
        revertOnZero = revertOnZero_;
    }

    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        if (revertOnZero && amount_ == 0) {
            revert("MockFeeOnTransferERC20: amount is zero");
        }

        if (blacklist[recipient_]) {
            revert("blacklist");
        }

        uint256 fee = amount_ * transferFee / 10_000;
        return super.transfer(recipient_, amount_ - fee);
    }

    function transferFrom(
        address sender_,
        address recipient_,
        uint256 amount_
    ) public override returns (bool) {
        if (revertOnZero && amount_ == 0) {
            revert("MockFeeOnTransferERC20: amount is zero");
        }

        if (blacklist[recipient_]) {
            revert("blacklist");
        }

        uint256 fee = amount_ * transferFee / 10_000;
        return super.transferFrom(sender_, recipient_, amount_ - fee);
    }

    function setBlacklist(address account_, bool value_) external {
        blacklist[account_] = value_;
    }
}

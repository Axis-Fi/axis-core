// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockFeeOnTransferERC20 is MockERC20 {
    uint256 public transferFee;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) MockERC20(name_, symbol_, decimals_) {}

    function setTransferFee(uint256 transferFee_) external {
        transferFee = transferFee_;
    }

    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        uint256 fee = amount_ * transferFee / 10_000;
        return super.transfer(recipient_, amount_ - fee);
    }

    function transferFrom(
        address sender_,
        address recipient_,
        uint256 amount_
    ) public override returns (bool) {
        uint256 fee = amount_ * transferFee / 10_000;
        return super.transferFrom(sender_, recipient_, amount_ - fee);
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

interface IHooks {
    function pre(uint256 id_, uint256 amount_) external;

    function mid(uint256 id_, uint256 amount_, uint256 payout_) external;

    function post(uint256 id_, uint256 payout_) external;
}

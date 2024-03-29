// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

contract CallbacksTest is Test {

    // validateCallbacksPermissions
    // [ ] all false
    // [ ] onCreate is true
    // [ ] onCancel is true
    // [ ] onCurate is true
    // [ ] onPurchase is true
    // [ ] onBid is true
    // [ ] onClaimProceeds is true
    // [ ] receiveQuoteTokens is true
    // [ ] sendBaseTokens is true

    // hasPermission
    // [ ] ON_CREATE_FLAG
    // [ ] ON_CANCEL_FLAG
    // [ ] ON_CURATE_FLAG
    // [ ] ON_PURCHASE_FLAG
    // [ ] ON_BID_FLAG
    // [ ] ON_CLAIM_PROCEEDS_FLAG
    // [ ] RECEIVE_QUOTE_TOKENS_FLAG
    // [ ] SEND_BASE_TOKENS_FLAG

    // isValidCallbacksAddress
    // [ ] zero address
    // [ ] if no flags are set, revert
    // [ ] if only RECEIVE_QUOTE_TOKENS_FLAG is set, return true
    // [ ] if any callback function is set, return true

}
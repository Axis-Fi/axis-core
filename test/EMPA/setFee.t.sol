// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {EmpaTest} from "test/EMPA/EMPATest.sol";

import {FeeManager} from "src/EMPA.sol";

contract EmpaSetFeeTest is EmpaTest {
    uint24 internal constant _MAX_FEE = 1e5;

    // [X] when called by a non-owner
    //  [X] it reverts
    // [X] when the fee is more than the maximum
    //  [X] it reverts
    // [X] when the fee type is protocol
    //  [X] it sets the protocol fee
    // [X] when the fee type is referrer
    //  [X] it sets the referrer fee
    // [X] when the fee type is curator
    //  [X] it sets the maximum curator fee

    function test_unauthorized() public {
        // Expect reverts
        vm.expectRevert("UNAUTHORIZED");

        vm.prank(_CURATOR);
        _auctionHouse.setFee(FeeManager.FeeType.Protocol, 100);
    }

    function test_maxFee_reverts() public {
        // Expect revert
        bytes memory err = abi.encodeWithSelector(FeeManager.InvalidFee.selector);
        vm.expectRevert(err);

        _auctionHouse.setFee(FeeManager.FeeType.Protocol, _MAX_FEE + 1);
    }

    function test_protocolFee(uint24 fee_) public {
        uint24 fee = uint24(bound(fee_, 0, _MAX_FEE));

        _auctionHouse.setFee(FeeManager.FeeType.Protocol, fee);

        // Validate
        (uint24 protocolFee, uint24 referrerFee, uint24 maxCuratorFee) = _auctionHouse.fees();
        assertEq(protocolFee, fee);
        assertEq(referrerFee, 0);
        assertEq(maxCuratorFee, _CURATOR_MAX_FEE_PERCENT);
    }

    function test_referrerFee(uint24 fee_) public {
        uint24 fee = uint24(bound(fee_, 0, _MAX_FEE));

        _auctionHouse.setFee(FeeManager.FeeType.Referrer, fee);

        // Validate
        (uint24 protocolFee, uint24 referrerFee, uint24 maxCuratorFee) = _auctionHouse.fees();
        assertEq(protocolFee, 0);
        assertEq(referrerFee, fee);
        assertEq(maxCuratorFee, _CURATOR_MAX_FEE_PERCENT);
    }

    function test_curatorFee(uint24 fee_) public {
        uint24 fee = uint24(bound(fee_, 0, _MAX_FEE));

        _auctionHouse.setFee(FeeManager.FeeType.MaxCurator, fee);

        // Validate
        (uint24 protocolFee, uint24 referrerFee, uint24 maxCuratorFee) = _auctionHouse.fees();
        assertEq(protocolFee, 0);
        assertEq(referrerFee, 0);
        assertEq(maxCuratorFee, fee);
    }
}

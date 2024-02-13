// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library StringHelper {
    function trim(
        string calldata str,
        uint256 start,
        uint256 end
    ) external pure returns (string memory) {
        return str[start:end];
    }
}

/// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Scripting libraries
import {Script, console2} from "lib/forge-std/src/Script.sol";
import {WithEnvironment} from "script/deploy/WithEnvironment.s.sol";
import {WithSalts} from "script/salts/WithSalts.s.sol";

import {BALwithAllocatedAllowlist} from
    "src/callbacks/liquidity/BaselineV2/BALwithAllocatedAllowlist.sol";

contract BaselineAllocatedAllowlistSalts is Script, WithEnvironment, WithSalts {
    string internal constant _ADDRESS_PREFIX = "EF";

    address internal _envBatchAuctionHouse;

    function _setUp(string calldata chain_) internal {
        _loadEnv(chain_);
        _createBytecodeDirectory();

        // Cache auction houses
        _envBatchAuctionHouse = _envAddressNotZero("axis.BatchAuctionHouse");
        console2.log("BatchAuctionHouse:", _envBatchAuctionHouse);
    }

    function generate(
        string calldata chain_,
        string calldata baselineKernel_,
        string calldata baselineOwner_,
        string calldata reserveToken_
    ) public {
        _setUp(chain_);

        _generateSalt(
            abi.encode(
                _envBatchAuctionHouse,
                vm.parseAddress(baselineKernel_),
                vm.parseAddress(reserveToken_),
                vm.parseAddress(baselineOwner_)
            )
        );
    }

    function _generateSalt(bytes memory contractArgs_) internal {
        bytes memory contractCode = type(BALwithAllocatedAllowlist).creationCode;

        (string memory bytecodePath, bytes32 bytecodeHash) =
            _writeBytecode("BaselineAllocatedAllowlist", contractCode, contractArgs_);
        _setSalt(bytecodePath, _ADDRESS_PREFIX, "BaselineAllocatedAllowlist", bytecodeHash);
    }
}

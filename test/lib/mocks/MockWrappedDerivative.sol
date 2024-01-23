// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC6909} from "solmate/tokens/ERC6909.sol";

import {Clone} from "src/lib/clones/Clone.sol";

contract MockWrappedDerivative is ERC20, Clone {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_, decimals_) {}

    function underlyingToken() public pure returns (ERC6909) {
        return ERC6909(_getArgAddress(0));
    }

    function underlyingTokenId() public pure returns (uint256) {
        return _getArgUint256(20); // address offset is 20
    }

    function deposit(uint256 amount_, address to_) external {
        // Transfer token to wrap
        underlyingToken().transferFrom(msg.sender, address(this), underlyingTokenId(), amount_);

        // Mint wrapped token
        _mint(to_, amount_);
    }

    function withdraw(uint256 amount_, address to_) external {
        // Burn wrapped token
        _burn(msg.sender, amount_);

        // Transfer token to unwrap
        underlyingToken().transfer(to_, underlyingTokenId(), amount_);
    }
}

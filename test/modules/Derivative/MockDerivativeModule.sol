// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

// Modules
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

// Auctions
import {DerivativeModule} from "src/modules/Derivative.sol";

contract MockDerivativeModule is DerivativeModule {
    bool internal validateFails;

    constructor(address _owner) Module(_owner) {}

    function VEECODE() public pure virtual override returns (Veecode) {
        return wrapVeecode(toKeycode("DERV"), 1);
    }

    function TYPE() public pure virtual override returns (Type) {
        return Type.Derivative;
    }

    function deploy(
        bytes memory params_,
        bool wrapped_
    ) external virtual override returns (uint256, address) {}

    function mint(
        address to_,
        bytes memory params_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override returns (uint256, address, uint256) {}

    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override returns (uint256, address, uint256) {}

    function redeem(uint256 tokenId_, uint256 amount_, bool wrapped_) external virtual override {}

    function exercise(uint256 tokenId_, uint256 amount, bool wrapped_) external virtual override {}

    function reclaim(uint256 tokenId_) external virtual override {}

    function transform(
        uint256 tokenId_,
        address from_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override {}

    function wrap(uint256 tokenId_, uint256 amount_) external virtual override {}

    function unwrap(uint256 tokenId_, uint256 amount_) external virtual override {}

    function exerciseCost(
        bytes memory data,
        uint256 amount
    ) external view virtual override returns (uint256) {}

    function convertsTo(
        bytes memory data,
        uint256 amount
    ) external view virtual override returns (uint256) {}

    function computeId(bytes memory params_) external pure virtual override returns (uint256) {}

    function validate(bytes memory params_) external view virtual override returns (bool) {
        if (validateFails) revert("validation error");

        return true;
    }

    function setValidateFails(bool validateFails_) external {
        validateFails = validateFails_;
    }
}

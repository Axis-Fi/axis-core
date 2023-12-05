/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC6909} from "lib/solmate/src/tokens/ERC6909.sol";
import "src/monolithic/modules/Modules.sol";

abstract contract Derivative {

    // ========== DATA STRUCTURES ========== //

    struct Token {
        bool exists;
        address wrapped;
        uint8 decimals;
        string name;
        string symbol;
        // TODO clarify what kind of data could be contained here
        bytes data;
    }

    // ========== STATE VARIABLES ========== //
    mapping(Keycode dType => address) public wrappedImplementations;
    mapping(uint256 tokenId => Token metadata) tokenMetadata;
    mapping(uint256 lotId => uint256[] tokenIds) public lotDerivatives;

    // ========== DERIVATIVE MANAGEMENT ========== //

    function deploy(bytes memory data, bool wrap) external virtual returns (uint256, address);

    function mint(bytes memory data, uint256 amount, bool wrap) external virtual returns (bytes memory);
    function mint(uint256 tokenId, uint256 amount, bool wrap) external virtual returns (bytes memory);

    function redeem(bytes memory data, uint256 amount) external virtual;

    // function batchRedeem(bytes[] memory data, uint256[] memory amounts) external virtual;

    function exercise(bytes memory data, uint256 amount) external virtual;

    // TODO how is this different to exercise or redeem?
    function reclaim(bytes memory data) external virtual;

    // TODO what does this do?
    function convert(bytes memory data, uint256 amount) external virtual;

    // TODO Consider best inputs for UX
    function wrap(uint256 tokenId, uint256 amount) external virtual;
    function unwrap(uint256 tokenId, uint256 amount) external virtual;

    // ========== DERIVATIVE INFORMATION ========== //

    // TODO view function to format implementation specific token data correctly and return to user

    function exerciseCost(bytes memory data, uint256 amount) external view virtual returns (uint256);

    function convertsTo(bytes memory data, uint256 amount) external view virtual returns (uint256);

    // Compute unique token ID for params on the submodule
    function computeId(bytes memory params_) external pure virtual returns (uint256);
}

abstract contract DerivativeModule is Derivative, ERC6909, Module {



}
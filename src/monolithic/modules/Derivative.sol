/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC6909} from "lib/solmate/src/tokens/ERC6909.sol";
import "src/monolithic/modules/Modules.sol";

abstract contract VaultStorage {

    // ========== DATA STRUCTURES ========== //

    struct Token {
        bool exists;
        address wrapped;
        uint8 decimals;
        string name;
        string symbol;
        bytes data;
    }
    
    // struct Storage {
    //     mapping(uint256 tokenId => Token metadata) tokenMetadata;
    // }

    // struct Derivative {
    //     bool exists;
    //     SubKeycode dType;
    //     bytes params;
    // }

    // ========== STATE VARIABLES ========== //
    // mapping(SubKeycode dType => Storage dStorage) public store;
    // TODO a lot (market) can have multiple derivatives that it uses, e.g. in the case of fixed term vesting
    // mapping(uint256 lotId => Derivative derivative) public lotDerivatives;
    mapping(Keycode dType => address) public wrappedImplementations;
    mapping(uint256 tokenId => Token metadata) tokenMetadata;
    mapping(uint256 lotId => uint256[] tokenIds) public lotDerivatives;
}

abstract contract DerivativeModule is VaultStorage, ERC6909, Module {

    // ========== DERIVATIVE MANAGEMENT ========== //

    function deploy(bytes memory params_) external virtual returns (uint256);

    function create(bytes memory data, uint256 amount) external virtual returns (bytes memory);

    function redeem(bytes memory data, uint256 amount) external virtual;

    // function batchRedeem(bytes[] memory data, uint256[] memory amounts) external virtual;

    function exercise(bytes memory data, uint256 amount) external virtual;

    function reclaim(bytes memory data) external virtual;

    function convert(bytes memory data, uint256 amount) external virtual;

    // ========== DERIVATIVE INFORMATION ========== //

    function exerciseCost(bytes memory data, uint256 amount) external view virtual returns (uint256);

    function convertsTo(bytes memory data, uint256 amount) external view virtual returns (uint256);

    // Compute unique token ID for params on the submodule
    function computeId(bytes memory params_) external pure virtual returns (uint256);

}
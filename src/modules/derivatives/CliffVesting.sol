// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

// import {ClonesWithImmutableArgs} from "src/lib/clones/ClonesWithImmutableArgs.sol";
// import {ERC20} from "solmate/tokens/ERC20.sol";
// import "src/modules/Derivative.sol";

// // TODO this only uses the ERC20 clones, need to convert to ERC6909 with optional ERC20 via wrapping the ERC6909
// contract CliffVesting is DerivativeModule {
//     using ClonesWithImmutableArgs for address;

//     // ========== EVENTS ========== //

//     // ========== ERRORS ========== //

//     // ========== STATE VARIABLES ========== //

//     struct Cliff {
//         ERC20 base;
//         uint48 expiry;
//     }

//     // ========== MODULE SETUP ========== //

//     constructor(Module parent_) Module(parent_) {}

//     function ID() public pure override returns (Keycode, uint8) {
//         return (toKeycode("CFV"), uint8(1));
//     }

//     // ========== DERIVATIVE MANAGEMENT ========== //

//     function deploy(bytes memory params_) external override onlyParent returns (bytes32) {
//         // Extract parameters from data
//         (ERC20 base, uint48 expiry) = _decodeAndNormalize(params_);

//         // Revert if expiry is in the past
//         if (uint256(expiry) < block.timestamp) revert VAULT_InvalidParams();

//         // Get id from provided parameters
//         uint256 id = _computeId(base, expiry);

//         // Load derivative token data from storage
//         Token storage t = tokenMetadata[id];

//         // Check if derivative already exists, if not deploy it
//         if (!t.exists) {

//             // If wrapping, deploy ERC20 clone using ID as salt
//             // Note: token implementations implement view functions, but they are just a passthrough to get data from the tokenMetadata mapping on the vault contract
//             // Therefore, we don't need to store the data redundantly on the token contract
//             Keycode dType = KEYCODE();
//             if (wrapped_) {
//                 // TODO think about collisions from different contract code and salts
//                 t.wrapped = wrappedImplementations[dType].clone3(abi.encodePacked(
//                     id,
//                     address(this)
//                 ), bytes32(id));
//             }

//             // Store derivative data
//             t.exists = true;
//             (t.name, t.symbol) = _getNameAndSymbol(base, expiry);
//             t.decimals = base.decimals();
//             t.data = abi.encode(FixedExpiry(base, expiry));

//             // Emit event
//             emit DerivativeCreated(dType, id, t.wrapped, base, expiry);
//         }

//         // // Get address of fixed expiry token using salt
//         // address feToken = ClonesWithImmutableArgs.addressOfClone3(salt);

// // Check if the token already exists. If not, deploy it.
// if (feToken.code.length == 0) {
//     (string memory name, string memory symbol) = _getNameAndSymbol(underlying_, expiry);
//     bytes memory tokenData = abi.encodePacked(
//         bytes32(bytes(name)),
//         bytes32(bytes(symbol)),
//         uint8(base.decimals()),
//         base,
//         uint256(expiry),
//         address(this)
//     );
//     feToken = address(dStore.implementation).clone3(tokenData, salt);
//     emit FixedExpiryERC20Created(feToken, base, expiry);
// }
// return bytes32(uint256(uint160(feToken)));
// }

//     function create(bytes memory data, uint256 amount) external override onlyParent returns (bytes memory) {}

// function redeem(bytes memory data, uint256 amount) external override onlyParent {}

// // function batchRedeem(bytes[] memory data, uint256[] memory amounts) external override {}

// function exercise(bytes memory data, uint256 amount) external override {}

// function reclaim(bytes memory data) external override {}

// function convert(bytes memory data, uint256 amount) external override {}

// // ========== DERIVATIVE INFORMATION ========== //

// function exerciseCost(bytes memory data, uint256 amount) external view override returns (uint256) {}

// function convertsTo(bytes memory data, uint256 amount) external view override returns (uint256) {}

// function derivativeForMarket(uint256 id_) external view override returns (bytes memory) {}

// // ========== INTERNAL FUNCTIONS ========== //

// // unique to this submodule by using the hash of the params and then hashing again with the subkeycode
// function _computeId(ERC20 base_, uint48 expiry_) internal pure returns (uint256) {
//     return uint256(keccak256(
//         abi.encodePacked(
//             SUBKEYCODE(),
//             keccak256(
//                 abi.encode(
//                     base_,
//                     expiry_
//                 )
//             )
//         )
//     ));
// }

// function _decodeAndNormalize(bytes memory params_) internal pure returns (ERC20 base, uint48 expiry) {
//     (base, expiry) = abi.decode(params_, (ERC20, uint48));

//     // Expiry is rounded to the nearest day at 0000 UTC (in seconds) since fixed expiry tokens
//     // are only unique to a day, not a specific timestamp.
//     expiry = uint48(expiry / 1 days) * 1 days;
// }

// function computeId(bytes memory params_) external pure override returns (uint256) {
//     (ERC20 base, uint48 expiry) = _decodeAndNormalize(params_);
//     return _computeId(base, expiry);
// }

// }

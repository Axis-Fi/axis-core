/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;


import {ERC6909} from "lib/solmate/src/tokens/ERC6909.sol";
import "src/Submodules.sol";


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
    mapping(SubKeycode dType => address) public wrappedImplementations;
    mapping(uint256 tokenId => Token metadata) tokenMetadata;
    mapping(uint256 lotId => uint256[] tokenIds) public lotDerivatives;
}

abstract contract VAULTv1 is VaultStorage, ERC6909, ModuleWithSubmodules {

    // Requirements
    // [ ] - Store collateral / backing for derivative tokens
    // [ ] - Issue derivative tokens
    // [ ] - Verify and redeem derivative tokens
    // [ ] - Extensible. Allow for adding new types of derivatives
    //     Initial types
    //     [ ] - Fixed Expiry Vesting (ERC-20 Clone)
    //     [ ] - Fixed Term Vesting (ERC1155/ERC6909 or ERC-20 Clone)
    //     [ ] - Fixed Strike Option (ERC-20 Clone)
    //     Future types
    //     [ ] - Fixed Term Linear Vesting (Soulbound ERC1155/ERC6909 or custom Notes)
    //     [ ] - Oracle Strike Option (ERC-20 Clone)
    //     [ ] - Fixed Expiry Convertible Vesting (ERC-20 Clone)
    //     [ ] - Success (Vesting + Option) (ERC-20 Clone)

    // Design
    // VAULT is core module with set of functions used by all derivative types.
    // Submodules implement derivative-specific logic and store data about their derivatives.
    // 

    // TODO rethink this
    function registerLot(uint256 lotId_, SubKeycode dType_, bytes memory params_) external {
        // Check if lot is already registered
        if (lotDerivatives[lotId_].exists) revert VAULT_LotAlreadyRegistered(lotId_);

        // Get submodule, will revert if not installed
        address submodule = address(_getSubmoduleIfInstalled(dType_));

        // Evaluate submodule logic
        (bool success, bytes memory data) = submodule.delegatecall(abi.encodeWithSelector(VaultSubmodule.registerLot.selector, params_));

        // Revert if call failed
        if (!success) revert VAULT_SubmoduleExecutionReverted(data);

        // Store lot derivate data
        lotDerivatives[lotId_] = Derivative({
            exists: true,
            dType: dType_,
            params: params_
        });
    }

    // ========== DERIVATIVE MANAGEMENT ========== //

    // TODO determine best combination of deploy and create functions
    // Options:
    // - Deploy from params with wrap flag -> returns tokenId and wrapped address
    // - Deploy from params -> returns tokenId
    // - Deploy wrapped from params -> returns wrapped address
    // - Create from params (deploys if not already deployed) with wrap flag -> can be used to just deploy by providing a zero amount. Downside is you have a lot of return types.
    // - Create from params (deploys if not already deployed) -> same as above with one fewer return type
    // - Create wrapped from params (deploys if not already deployed) -> same as above with one fewer return type
    // - Create from tokenId with wrapped flag, requires deploy first
    // - Create from tokenId
    // - Create wrapped from tokenId
    // - Create wrapped from wrapped address


    /// @notice Deploy a new derivative token. Optionally, deploys an ERC20 wrapper for composability.
    /// @param dType_ SubKeycode of the derivative type, must be a valid submodule
    /// @param params_ ABI-encoded parameters for the derivative to be created
    /// @param wrapped_ Whether (true) or not (false) the derivative should be wrapped in an ERC20 token for composability
    /// @return tokenId_ The ID of the newly created derivative token
    /// @return wrappedAddress_ The address of the ERC20 wrapped derivative token, if wrapped_ is true, otherwise, it's the zero address.
    /// @return amountCreated_ The amount of derivative tokens created
    function deploy(SubKeycode dType_, bytes memory params_, bool wrapped_) external virtual returns (uint256, address, uint256);

    /// @notice Mint new derivative tokens. Deploys the derivative token if it does not already exist.
    /// @param dType_ SubKeycode of the derivative type, must be a valid submodule
    /// @param params_ ABI-encoded parameters for the derivative to be created
    /// @param amount_ The amount of derivative tokens to create
    /// @param wrapped_ Whether (true) or not (false) the derivative should be wrapped in an ERC20 token for composability
    /// @return tokenId_ The ID of the newly created derivative token
    /// @return wrappedAddress_ The address of the ERC20 wrapped derivative token, if wrapped_ is true, otherwise, it's the zero address.
    /// @return amountCreated_ The amount of derivative tokens created
    function mint(SubKeycode dType_, bytes memory params_, uint256 amount_, bool wrapped_) external virtual returns (uint256, address, uint256);

    /// @notice Mint new derivative tokens for a specific token Id
    /// @param tokenId_ The ID of the derivative token
    /// @param amount_ The amount of derivative tokens to create
    /// @param wrapped_ Whether (true) or not (false) the derivative should be wrapped in an ERC20 token for composability
    /// @return tokenId_ The ID of the derivative token
    /// @return wrappedAddress_ The address of the ERC20 wrapped derivative token, if wrapped_ is true, otherwise, it's the zero address.
    /// @return amountCreated_ The amount of derivative tokens created
    function mint(uint256 tokenId_, uint256 amount_, bool wrapped_) external virtual returns (uint256, address, uint256);

    /// @notice Redeem derivative tokens
    /// @param tokenId_ The ID of the derivative token to redeem
    /// @param amount_ The amount of derivative tokens to redeem
    /// @param wrapped_ Whether (true) or not (false) to redeem wrapped ERC20 derivative tokens
    function redeem(uint256 tokenId_, uint256 amount_, bool wrapped_) external virtual;

    // Wrap an existing derivative into an ERC20 token for composability
    // Deploys the ERC20 wrapper if it does not already exist
    function wrap(SubKeycode dType_, uint256 tokenId_, uint256 amount_) external virtual;

    // Unwrap an ERC20 derivative token into the underlying ERC6909 derivative
    function unwrap(SubKeycode dType_, uint256 tokenId_, uint256 amount_) external virtual;

    // Unwrap an ERC20 derivative token into the underlying ERC6909 derivative
    function unwrap(SubKeycode dType_, address wrappedAddress_, uint256 amount_) external virtual;



}

abstract contract VaultSubmodule is VaultStorage, ERC6909, Submodule {
    
    // ========== SUBMODULE SETUP ========== //
    function PARENT() public pure override returns (Keycode) {
        return toKeycode("VAULT");
    }

    function _VAULT() internal view returns (VAULTv1) {
        return VAULTv1(address(parent));
    }

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
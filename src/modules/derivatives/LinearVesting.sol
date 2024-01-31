/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC6909} from "solmate/tokens/ERC6909.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ClonesWithImmutableArgs} from "src/lib/clones/ClonesWithImmutableArgs.sol";

import {Derivative, DerivativeModule} from "src/modules/Derivative.sol";
import {Module, Veecode, toKeycode, wrapVeecode} from "src/modules/Modules.sol";

contract LinearVesting is DerivativeModule {
    using SafeTransferLib for ERC20;
    using ClonesWithImmutableArgs for address;

    // ========== EVENTS ========== //

    // ========== ERRORS ========== //

    error BrokenInvariant();
    error InsufficientBalance();
    error NotPermitted();
    error InvalidParams();

    // ========== DATA STRUCTURES ========== //

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting begins
    /// @param      expiry      The timestamp at which the vesting ends
    /// @param      baseToken   The address of the token to vest
    struct VestingData {
        uint48 start;
        uint48 expiry;
        ERC20 baseToken;
    }

    /// @notice     Stores the parameters for a particular derivative
    ///
    /// @param      start       The timestamp at which the vesting begins
    /// @param      expiry      The timestamp at which the vesting ends
    struct VestingParams {
        uint48 start;
        uint48 expiry;
    }

    // ========== STATE VARIABLES ========== //

    ERC20 internal erc20Implementation;

    /// @notice     Stores the vesting data for a particular token id
    mapping(uint256 tokenId => VestingData) public vestingData;

    /// @notice     Stores the amount of tokens that have been claimed for a particular token id and owner
    mapping(address owner => mapping(uint256 tokenId => uint256 claimed)) internal claimed;

    // ========== MODULE SETUP ========== //

    constructor(address parent_) Module(parent_) {}

    /// @inheritdoc Module
    function TYPE() public pure override returns (Type) {
        return Type.Derivative;
    }

    /// @inheritdoc Module
    function VEECODE() public pure override returns (Veecode) {
        return wrapVeecode(toKeycode("LIV"), 1);
    }

    // TODO
    // [X] prevent transfer
    // [X] prevent transferFrom
    // [X] prevent approve
    // [X] claim
    // [X] claimable
    // [ ] wrap
    // [ ] unwrap
    // [ ] deploy
    // [ ] mint

    /// @inheritdoc ERC6909
    /// @dev        Vesting tokens are soulbound/not transferable
    function transfer(address, uint256, uint256) public virtual override returns (bool) {
        revert NotPermitted();
    }

    /// @inheritdoc ERC6909
    /// @dev        Vesting tokens are soulbound/not transferable
    function transferFrom(
        address,
        address,
        uint256,
        uint256
    ) public virtual override returns (bool) {
        revert NotPermitted();
    }

    /// @inheritdoc ERC6909
    /// @dev        Vesting tokens are soulbound/not transferable
    function approve(address, uint256, uint256) public virtual override returns (bool) {
        revert NotPermitted();
    }

    /// @inheritdoc Derivative
    /// @dev        This function performs the following:
    ///             - Validates the parameters
    ///             - Deploys the derivative token if it does not already exist
    ///
    ///             This function reverts if:
    ///             - The parameters are in an invalid format
    ///             - The parameters fail validation
    ///
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             The abi-encoded `VestingParams` for the derivative token
    /// @param      wrapped_            Whether or not to wrap the derivative token
    /// @return     tokenId_            The ID of the derivative token
    /// @return     wrappedAddress_     The address of the wrapped derivative token (if applicable)
    function deploy(
        address underlyingToken_,
        bytes memory params_,
        bool wrapped_
    ) external virtual override returns (uint256 tokenId_, address wrappedAddress_) {
        // Decode parameters
        VestingParams memory params = abi.decode(params_, (VestingParams));

        // Validate parameters
        {
            // Re-encode the parameters
            VestingData memory data = VestingData({
                start: params.start,
                expiry: params.expiry,
                baseToken: ERC20(underlyingToken_)
            });

            if (_validate(data) == false) revert InvalidParams();
        }

        // If necessary, deploy and store the data
        (uint256 tokenId, address wrappedAddress) =
            _deployIfNeeded(underlyingToken_, params, wrapped_);

        return (tokenId, wrappedAddress);
    }

    /// @inheritdoc Derivative
    /// @dev        This function performs the following:
    ///             - Validates the parameters
    ///             - Deploys the derivative token if it does not already exist
    ///             - Mints the derivative token to the recipient
    ///
    ///             This function reverts if:
    ///             - The parameters are in an invalid format
    ///             - The parameters fail validation
    ///             - `amount_` is 0
    ///
    /// @param      to_                 The address of the recipient of the derivative token
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             The abi-encoded `VestingParams` for the derivative token
    /// @param      amount_             The amount of the derivative token to mint
    /// @param      wrapped_            Whether or not to wrap the derivative token
    /// @return     tokenId_            The ID of the derivative token
    /// @return     wrappedAddress_     The address of the wrapped derivative token (if applicable)
    /// @return     amountCreated_      The amount of the derivative token that was minted
    function mint(
        address to_,
        address underlyingToken_,
        bytes memory params_,
        uint256 amount_,
        bool wrapped_
    )
        external
        virtual
        override
        returns (uint256 tokenId_, address wrappedAddress_, uint256 amountCreated_)
    {
        // Can't mint 0
        if (amount_ == 0) revert InvalidParams();

        // Decode parameters
        VestingParams memory params = abi.decode(params_, (VestingParams));

        // Validate parameters
        {
            // Re-encode the parameters
            VestingData memory data = VestingData({
                start: params.start,
                expiry: params.expiry,
                baseToken: ERC20(underlyingToken_)
            });

            if (_validate(data) == false) revert InvalidParams();
        }

        // If necessary, deploy and store the data
        (uint256 tokenId, address wrappedAddress) =
            _deployIfNeeded(underlyingToken_, params, wrapped_);

        // Check that the wrapped status is correct
        if (wrappedAddress != address(0) && wrapped_ == false) revert InvalidParams();

        // Transfer collateral token to this contract
        ERC20(underlyingToken_).safeTransferFrom(msg.sender, address(this), amount_);

        // If wrapped, mint
        if (wrapped_) {
            // TODO
        }
        // Otherwise mint as normal
        else {
            _mint(to_, tokenId, amount_);
        }

        return (tokenId, wrappedAddress, amount_);
    }

    /// @inheritdoc Derivative
    /// @dev        This function performs the following:
    ///             - Mints the derivative token to the recipient
    ///
    ///             This function reverts if:
    ///             - `tokenId_` does not exist
    ///             - The amount to mint is 0
    ///
    /// @param      to_                 The address of the recipient of the derivative token
    /// @param      tokenId_            The ID of the derivative token
    /// @param      amount_             The amount of the derivative token to mint
    /// @param      wrapped_            Whether or not to wrap the derivative token
    /// @return     uint256             The ID of the derivative token
    /// @return     adress              The address of the wrapped derivative token (if applicable)
    /// @return     uint256             The amount of the derivative token that was minted
    function mint(
        address to_,
        uint256 tokenId_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override returns (uint256, address, uint256) {
        // Can't mint 0
        if (amount_ == 0) revert InvalidParams();

        Token storage token = tokenMetadata[tokenId_];

        // Validate that the token id exists
        if (token.exists == false) revert InvalidParams();

        // If the token exists, it is already deployed. However, ensure the wrapped status is consistent.
        if (wrapped_) {
            _deployWrapIfNeeded(tokenId_, token);
        }

        // Transfer collateral token to this contract
        VestingData memory data = abi.decode(token.data, (VestingData));
        data.baseToken.safeTransferFrom(msg.sender, address(this), amount_);

        // If wrapped, mint
        if (wrapped_) {
            // TODO
        } else {
            _mint(to_, tokenId_, amount_);
        }

        return (tokenId_, token.wrapped, amount_);
    }

    /// @inheritdoc Derivative
    function redeem(uint256 tokenId_, uint256 amount_, bool wrapped_) external virtual override {
        // Get the redeemable amount
        uint256 redeemableAmount = redeemable(msg.sender, tokenId_);

        // If the redeemable amount is 0, revert
        if (redeemableAmount == 0) revert InsufficientBalance();

        // If the redeemable amount is less than the requested amount, revert
        if (redeemableAmount < amount_) revert InsufficientBalance();

        // Update claimed amount
        claimed[msg.sender][tokenId_] += amount_;

        // Burn the derivative token
        if (wrapped_) {
            // TODO burn wrapped token
            // What does wrapped_ signify here?
        } else {
            _burn(msg.sender, tokenId_, amount_);
        }

        // Transfer the underlying token to the owner
        vestingData[tokenId_].baseToken.safeTransfer(msg.sender, amount_);
    }

    /// @notice     Returns the amount of vested tokens that can be redeemed for the underlying base token
    /// @dev        The redeemable amount is computed as:
    ///             - The amount of tokens that have vested
    ///               - x: number of vestable tokens
    ///               - t: current timestamp
    ///               - s: start timestamp
    ///               - T: end timestamp
    ///               - Vested = x * (t - s) / (T - s)
    ///             - Minus the amount of tokens that have already been redeemed
    ///
    /// @param      owner_      The address of the owner of the derivative token
    /// @param      tokenId_    The ID of the derivative token
    /// @return     uint256     The amount of tokens that can be redeemed
    function redeemable(address owner_, uint256 tokenId_) public view returns (uint256) {
        // Get the vesting data
        VestingData storage data = vestingData[tokenId_];

        // If before the start time, 0
        if (block.timestamp < data.start) return 0;

        // TODO what if there is a wrapped balance?
        uint256 ownerBalance = balanceOf[owner_][tokenId_];
        uint256 claimedBalance = claimed[owner_][tokenId_];
        uint256 totalAmount = ownerBalance + claimedBalance;
        uint256 vested;

        // If after the end time, all tokens are redeemable
        if (block.timestamp >= data.expiry) {
            vested = totalAmount;
        }
        // If before the end time, calculate what has vested already
        else {
            vested = (totalAmount * (block.timestamp - data.start)) / (data.expiry - data.start);
        }

        // Check invariant: cannot have claimed more than vested
        if (vested < claimedBalance) {
            revert BrokenInvariant();
        }

        // Deduct already claimed tokens
        vested -= claimedBalance;

        return vested;
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function exercise(uint256, uint256, bool) external virtual override {
        revert Derivative.Derivative_NotImplemented();
    }

    function reclaim(uint256 tokenId_) external virtual override {}

    function transform(
        uint256 tokenId_,
        address from_,
        uint256 amount_,
        bool wrapped_
    ) external virtual override {}

    function wrap(uint256 tokenId_, uint256 amount_) external virtual override {}

    function unwrap(uint256 tokenId_, uint256 amount_) external virtual override {}

    function _validate(VestingData memory data_) internal view returns (bool) {
        // Revert if start or expiry are 0
        if (data_.start == 0 || data_.expiry == 0) return false;

        // Revert if start and expiry are the same (as it would result in a divide by 0 error)
        if (data_.start == data_.expiry) return false;

        // Check that the start time is before the end time
        if (data_.start >= data_.expiry) return false;

        // Check that the expiry time is in the future
        if (data_.expiry < block.timestamp) return false;

        // Check that the base token is not the zero address
        if (address(data_.baseToken) == address(0)) return false;

        return true;
    }

    /// @inheritdoc Derivative
    function validate(bytes memory params_) public view virtual override returns (bool) {
        // Decode the parameters
        VestingData memory data = abi.decode(params_, (VestingData));

        return _validate(data);
    }

    /// @inheritdoc Derivative
    /// @dev        Not implemented
    function exerciseCost(bytes memory, uint256) external view virtual override returns (uint256) {
        revert Derivative.Derivative_NotImplemented();
    }

    /// @inheritdoc Derivative
    function convertsTo(
        bytes memory data,
        uint256 amount
    ) external view virtual override returns (uint256) {}

    /// @notice     Computes the ID of a derivative token
    /// @dev        The ID is computed as the hash of the parameters and hashed again with the module identifier.
    ///
    /// @param      base_       The address of the underlying token
    /// @param      start_      The timestamp at which the vesting begins
    /// @param      expiry_     The timestamp at which the vesting ends
    /// @return     uint256     The ID of the derivative token
    function _computeId(
        ERC20 base_,
        uint48 start_,
        uint48 expiry_
    ) internal pure returns (uint256) {
        return uint256(
            keccak256(abi.encodePacked(VEECODE(), keccak256(abi.encode(base_, start_, expiry_))))
        );
    }

    /// @inheritdoc Derivative
    function computeId(bytes memory params_) external pure virtual override returns (uint256) {
        // Decode the parameters
        VestingData memory data = abi.decode(params_, (VestingData));

        // Compute the ID
        return _computeId(data.baseToken, data.start, data.expiry);
    }

    function _computeNameAndSymbol(
        ERC20 base_,
        uint48 start_,
        uint48 expiry_
    ) internal view returns (string memory, string memory) {
        return (
            string(abi.encodePacked(base_.name(), "-", start_, "-", expiry_)),
            string(abi.encodePacked(base_.symbol(), "-", start_, "-", expiry_))
        );
    }

    /// @notice     Deploys the derivative token if it does not already exist
    /// @dev        If the derivative token does not exist, it will be deployed using a token id
    ///             computed from the parameters.
    ///
    /// @param      underlyingToken_    The address of the underlying token
    /// @param      params_             The parameters for the derivative token
    /// @param      wrapped_            Whether or not to wrap the derivative token
    /// @return     tokenId_            The ID of the derivative token
    /// @return     wrappedAddress_     The address of the wrapped derivative token
    function _deployIfNeeded(
        address underlyingToken_,
        VestingParams memory params_,
        bool wrapped_
    ) internal returns (uint256 tokenId_, address wrappedAddress_) {
        // Compute the token ID
        ERC20 underlyingToken = ERC20(underlyingToken_);
        tokenId_ = _computeId(underlyingToken, params_.start, params_.expiry);

        // Record the token metadata, if needed
        Token storage token = tokenMetadata[tokenId_];
        if (token.exists == false) {
            // Store derivative data
            token.exists = true;
            token.data = abi.encode(
                VestingData({
                    start: params_.start,
                    expiry: params_.expiry,
                    baseToken: underlyingToken
                })
            ); // Store this so that the tokenId can be used as a lookup
                // TODO are the other metadata fields needed?

            tokenMetadata[tokenId_] = token;
        }

        // Create a wrapped derivative, if needed
        if (wrapped_) {
            _deployWrapIfNeeded(tokenId_, token);
        }

        return (tokenId_, token.wrapped);
    }

    /// @notice     Deploys the wrapped derivative token if it does not already exist
    /// @dev        If the wrapped derivative token does not exist, it will be deployed
    ///
    /// @param      tokenId_            The ID of the derivative token
    /// @param      token_              The metadata for the derivative token
    /// @return     wrappedAddress      The address of the wrapped derivative token
    function _deployWrapIfNeeded(
        uint256 tokenId_,
        Token storage token_
    ) internal returns (address wrappedAddress) {
        // Create a wrapped derivative, if needed
        if (token_.wrapped == address(0)) {
            // Cannot deploy if there isn't a clonable implementation
            if (address(erc20Implementation) == address(0)) revert InvalidParams();

            // Get the parameters
            VestingData memory data = abi.decode(token_.data, (VestingData));

            // Deploy the wrapped implementation
            (string memory name, string memory symbol) =
                _computeNameAndSymbol(data.baseToken, data.start, data.expiry);
            token_.wrapped = address(erc20Implementation).clone3(
                abi.encodePacked(name, symbol, data.baseToken.decimals()), bytes32(tokenId_)
            );
        }

        return token_.wrapped;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

interface IPreAsset {
    function seed() external returns (uint256);

    function setBAsset(address bAsset_) external;

    function claim() external returns (uint256);
}

interface IBAsset {
    function baseline() external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IBaselineFactory {
    function deploy(
        address preAsset_,
        string memory name_,
        string memory symbol_,
        address reserve_,
        bytes32 salt_,
        address feeRecipient_,
        int24 initTick_,
        uint256 initFloor_,
        uint256 initDisc_
    ) external returns (address baseline);
}

/// @notice     This contract is a replacement PreAsset for a Baseline pool that allows depositing proceeds from a Batch auction directly into Baseline.
/// @dev        The contract is the base token that should be auctioned. It provides a pre-asset token that buyers can then use to claim bAssets from after the Baseline Market is deployed.
///
///             This contract is designed to be used with a single auction and Baseline pool
contract BaselinePreAsset is ERC20, BaseCallback, IPreAsset {
    // ========== ERRORS ========== //

    error Callback_AlreadyComplete();
    error Callback_MissingFunds();
    error PreAsset_AuctionNotComplete();
    error PreAsset_AlreadySeeded();
    error PreAsset_BAssetAlreadySet();
    error PreAsset_BAssetNotSet();
    error PreAsset_NotAuthorized();
    error PreAsset_PoolNotSeeded();

    // ========== EVENTS ========== //

    event Seeded(uint256 totalReserves);
    event Claim(address indexed user, uint256 amount);

    // ========== STATE VARIABLES ========== //

    // Baseline Variables
    ERC20 public immutable RESERVE;
    IBaselineFactory public immutable BASELINE_FACTORY;
    IBAsset public bAsset;

    /// @notice Lot ID of the auction for the baseline market. This callback only supports one lot.
    uint96 public lotId;
    bool public auctionComplete;
    bool public seeded;
    uint256 public totalPreAssets;
    uint256 public totalBAssets;

    // ========== CONSTRUCTOR ========== //

    constructor(
        string memory preAssetName_,
        string memory preAssetSymbol_,
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address seller_,
        address reserve_,
        address baselineFactory_
    )
        ERC20(preAssetName_, preAssetSymbol_, 18)
        BaseCallback(auctionHouse_, permissions_, seller_)
    {
        // Check that the reserve token has 18 decimals
        if (ERC20(reserve_).decimals() != 18) revert Callback_InvalidParams();

        // Store immutable variables
        RESERVE = ERC20(reserve_);
        BASELINE_FACTORY = IBaselineFactory(baselineFactory_);

        // Set lot ID to max uint(96) initially
        lotId = type(uint96).max;
    }

    // ========== CALLBACK FUNCTIONS ========== //

    // CALLBACK PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: false
    // onBid: false
    // onClaimProceeds: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11100111 = 0xE7

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Sets the lot ID
    ///                 - Mints the required preAsset tokens to the AuctionHouse
    ///
    ///                 This function reverts if:
    ///                 - `baseToken_` is not the pre asset (this contract)
    ///                 - `quoteToken_` is not the reserve
    ///                 - `prefund_` is false
    ///                 - `lotId` is already set
    function _onCreate(
        uint96 lotId_,
        address,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata
    ) internal override {
        // Validate the base token is the pre asset (this contract)
        // and the quote token is the reserve
        if (baseToken_ != address(this) || quoteToken_ != address(RESERVE)) {
            revert Callback_InvalidParams();
        }

        // Validate that prefund is true
        if (!prefund_) revert Callback_InvalidParams();

        // Validate that the lot ID is not already set
        if (lotId != type(uint96).max) revert Callback_InvalidParams();

        // Set the lot ID
        lotId = lotId_;

        // Mint the capacity of preAsset tokens to the auction house (as is expected when `prefund_` is true)
        _mint(msg.sender, capacity_);
    }

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Burns the refunded preAsset tokens
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///                 - The AuctionHouse has already sent the correct amount of preAsset tokens
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - `prefunded_` is false
    function _onCancel(
        uint96 lotId_,
        uint256 refund_,
        bool prefunded_,
        bytes calldata
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that prefunded is true
        if (!prefunded_) revert Callback_InvalidParams();

        // Burn the refund amount of preAsset tokens that was sent from the auction house
        // Will revert if the auction house did not send the correct amount of preAsset tokens
        _burn(address(this), refund_);
    }

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Mints the required amount of preAsset tokens to the AuctionHouse for paying the curator fee
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - `prefund_` is false
    function _onCurate(
        uint96 lotId_,
        uint256 curatorFee_,
        bool prefund_,
        bytes calldata
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that prefund is true
        if (!prefund_) revert Callback_InvalidParams();

        // Mint the curator fee amount of preAsset tokens to the auction house
        _mint(msg.sender, curatorFee_);
    }

    /// @inheritdoc     BaseCallback
    /// @dev            This function reverts as it is not implemented
    function _onPurchase(
        uint96,
        address,
        uint256,
        uint256,
        bool,
        bytes calldata
    ) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @inheritdoc     BaseCallback
    /// @dev            This function reverts as it is not implemented
    function _onBid(uint96, uint64, address, uint256, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Sets the auction as complete
    ///                 - Burns any refunded preAsset tokens
    ///                 - Calculates the deployment parameters for the Baseline pool
    ///                 - Deploys the Baseline pool
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///                 - The AuctionHouse has already sent the correct amount of quote tokens (proceeds)
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - The auction is already complete
    ///                 - The reported proceeds received are less than the reserve balance
    ///                 - The BAsset is not set
    ///                 - The BAsset's Baseline factory is not consistent with `BASELINE_FACTORY`
    function _onClaimProceeds(
        uint96 lotId_,
        uint256 proceeds_,
        uint256 refund_,
        bytes calldata callbackData
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that the auction is not already complete
        if (auctionComplete) revert Callback_AlreadyComplete();

        // Validate that the callback received the correct amount of proceeds
        if (proceeds_ < RESERVE.balanceOf(address(this))) revert Callback_MissingFunds();

        // Decode callback data to get bAsset initialization parameters
        (string memory name, string memory symbol, bytes32 salt, address feeRecipient) =
            abi.decode(callbackData, (string, string, bytes32, address));

        // Set the auction as complete
        auctionComplete = true;

        // Burn any refunded preAsset tokens that were sent from the auction house
        _burn(address(this), refund_);

        // Store the total supply of preAsset tokens at the point of baseline deployment
        totalPreAssets = totalSupply;

        // Calculate the clearing price in quote tokens per base token
        // TODO discuss with baseline team
        uint256 clearingPrice = (proceeds_ * 1e18) / totalPreAssets;
        int24 initTick = 0; // TODO calculate from clearing price
        uint256 initFloor = 0; // TODO liquidity in floor
        uint256 initDisc = 0; // TODO liquidity in discovery

        // Deploy the baseline pool
        // This function will re-enter this contract to set the bAsset and seed the pool
        // At the end of the call, this contract should have the initial supply of bAssets
        // We store them to use for claiming
        BASELINE_FACTORY.deploy(
            address(this),
            name,
            symbol,
            address(RESERVE),
            salt,
            feeRecipient,
            initTick,
            initFloor,
            initDisc
        );

        // The BAsset is set by now
        // Validate that the BAsset has been set
        if (address(bAsset) == address(0)) revert Callback_InvalidParams();

        // Validate that the Baseline factory is consistent
        if (address(bAsset.baseline()) != address(BASELINE_FACTORY)) {
            revert Callback_InvalidParams();
        }

        // Store the total bAssets received
        totalBAssets = bAsset.balanceOf(address(this));
    }

    // ========== BASELINE PREASSET FUNCTIONS ========== //

    /// @notice     Transfer reserves to Baseline to seed the pool
    /// @dev        This function performs the following:
    ///             - Performs validation
    ///             - Sets the preAsset as seeded
    ///             - Transfers the reserves to the baseline pool
    ///
    ///             This function has the following assumptions:
    ///             - The BAsset address and factory has already been checked in `onClaimProceeds()`
    ///
    ///             This function reverts if:
    ///             - The auction is not complete
    ///             - The Baseline pool has already been seeded through `onClaimProceeds()`
    ///             - The caller is not the baseline contract
    ///
    /// @return     The reserves transferred to the Baseline pool
    function seed() external override onlyBaselineFactory returns (uint256) {
        // Ensure the auction is complete
        if (!auctionComplete) revert PreAsset_AuctionNotComplete();

        // Ensure that the baseline market hasn't already been seeded
        if (seeded) revert PreAsset_AlreadySeeded();

        // Set the preAsset as seeded
        seeded = true;

        // Transfer reserves to the Baseline pool
        uint256 totalReserves = RESERVE.balanceOf(address(this));
        RESERVE.transfer(bAsset.baseline(), totalReserves);

        emit Seeded(totalReserves);
        return totalReserves;
    }

    /// @notice     Set the precalculated BAsset address
    /// @dev        This function must be called before baseline deployment
    ///
    ///             This function performs the following:
    ///             - Performs validation
    ///             - Sets the BAsset address
    ///
    ///             This function reverts if:
    ///             - The caller is not the Baseline factory
    ///             - The BAsset has already been set
    ///
    /// @param      bAsset_ The address of the BAsset
    function setBAsset(address bAsset_) external override onlyBaselineFactory {
        // Ensure the bAsset has not already been set
        if (address(bAsset) != address(0)) revert PreAsset_BAssetAlreadySet();

        // Set the bAsset
        bAsset = IBAsset(bAsset_);
    }

    /// @notice     Allows a user to claim bAssets after the Baseline pool has been deployed
    /// @dev        This is required, as the auction bidders will have received preAsset tokens, but need to have bAsset tokens.
    ///
    ///             This function performs the following:
    ///             - Performs validation
    ///             - Calculates the amount of bAssets claimable
    ///             - Transfers the claimable bAssets to the caller
    ///
    ///             This function reverts if:
    ///             - The pool has not been seeded
    ///
    /// @return     The amount of bAssets claimed
    function claim() external returns (uint256) {
        // Validate that pool has been seeded and the preasset received the bAssets
        if (!seeded) revert PreAsset_PoolNotSeeded();

        // Get the user's balance of preAsset tokens
        uint256 preAssetBalance = balanceOf[msg.sender];

        // If balance is 0, return 0
        if (preAssetBalance == 0) return 0;

        // Calculate amount claimable
        uint256 claimable = (preAssetBalance * totalBAssets) / totalPreAssets;

        bAsset.transfer(msg.sender, claimable);

        emit Claim(msg.sender, claimable);
        return claimable;
    }

    // ========== MODIFIERS ========== //

    /// @notice Ensure caller is the Baseline factory contract
    modifier onlyBaselineFactory() {
        if (msg.sender != address(BASELINE_FACTORY)) revert PreAsset_NotAuthorized();
        _;
    }
}

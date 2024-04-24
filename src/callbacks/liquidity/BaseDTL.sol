// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Callbacks
import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";

// AuctionHouse
import {LinearVesting} from "src/modules/derivatives/LinearVesting.sol";
import {AuctionHouse} from "src/bases/AuctionHouse.sol";
import {Keycode, wrapVeecode} from "src/modules/Modules.sol";

abstract contract BaseDirectToLiquidity is BaseCallback {
    using SafeTransferLib for ERC20;

    // ========== ERRORS ========== //

    error Callback_InsufficientBalance(
        address token_, address account_, uint256 balance_, uint256 required_
    );

    error Callback_Params_InvalidAddress();

    error Callback_Params_PercentOutOfBounds(uint24 actual_, uint24 min_, uint24 max_);

    error Callback_Params_PoolExists();

    error Callback_Params_InvalidVestingParams();

    error Callback_LinearVestingModuleNotFound();

    // ========== STRUCTS ========== //

    /// @notice     Configuration for the DTL callback
    ///
    /// @param      recipient                   The recipient of the LP tokens
    /// @param      lotCapacity                 The capacity of the lot
    /// @param      lotCuratorPayout            The maximum curator payout of the lot
    /// @param      proceedsUtilisationPercent  The percentage of the proceeds to deposit into the pool
    /// @param      vestingStart                The start of the vesting period for the LP tokens (0 if disabled)
    /// @param      vestingExpiry               The end of the vesting period for the LP tokens (0 if disabled)
    /// @param      linearVestingModule         The LinearVesting module for the LP tokens (only set if linear vesting is enabled)
    /// @param      active                      Whether the lot is active
    /// @param      implParams                  The implementation-specific parameters
    struct DTLConfiguration {
        address recipient;
        uint256 lotCapacity;
        uint256 lotCuratorPayout;
        uint24 proceedsUtilisationPercent;
        uint48 vestingStart;
        uint48 vestingExpiry;
        LinearVesting linearVestingModule;
        bool active;
        bytes implParams;
    }

    /// @notice     Parameters used in the onCreate callback
    ///
    /// @param      proceedsUtilisationPercent   The percentage of the proceeds to use in the pool
    /// @param      vestingStart                 The start of the vesting period for the LP tokens (0 if disabled)
    /// @param      vestingExpiry                The end of the vesting period for the LP tokens (0 if disabled)
    /// @param      recipient                    The recipient of the LP tokens
    /// @param      implParams                   The implementation-specific parameters
    struct OnCreateParams {
        uint24 proceedsUtilisationPercent;
        uint48 vestingStart;
        uint48 vestingExpiry;
        address recipient;
        bytes implParams;
    }

    // ========== STATE VARIABLES ========== //

    uint24 public constant MAX_PERCENT = 1e5;
    bytes5 public constant LINEAR_VESTING_KEYCODE = 0x4c49560000; // "LIV"

    /// @notice     Maps the lot id to the DTL configuration
    mapping(uint96 lotId => DTLConfiguration) public lotConfiguration;

    // ========== CONSTRUCTOR ========== //

    constructor(address auctionHouse_)
        BaseCallback(
            auctionHouse_,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: false,
                onBid: false,
                onClaimProceeds: true,
                receiveQuoteTokens: true,
                sendBaseTokens: false
            })
        )
    {}

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseCallback
    /// @notice     Callback for when a lot is created
    /// @dev        This function performs the following:
    ///             - Validates the input data
    ///             - Calls the Uniswap-specific implementation
    ///             - Stores the configuration for the lot
    ///
    ///             This function reverts if:
    ///             - OnCreateParams.proceedsUtilisationPercent is out of bounds
    ///             - OnCreateParams.vestingStart or OnCreateParams.vestingExpiry do not pass validation
    ///             - Vesting is enabled and the linear vesting module is not found
    ///             - The OnCreateParams.recipient address is the zero address
    ///
    /// @param      lotId_          The lot ID
    /// @param      baseToken_      The base token address
    /// @param      quoteToken_     The quote token address
    /// @param      capacity_       The capacity of the lot
    /// @param      callbackData_   Encoded OnCreateParams struct
    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual override onlyIfLotDoesNotExist(lotId_) {
        // Decode callback data into the params
        OnCreateParams memory params = abi.decode(callbackData_, (OnCreateParams));

        // Validate the parameters
        // Proceeds utilisation
        if (
            params.proceedsUtilisationPercent == 0
                || params.proceedsUtilisationPercent > MAX_PERCENT
        ) {
            revert Callback_Params_PercentOutOfBounds(
                params.proceedsUtilisationPercent, 1, MAX_PERCENT
            );
        }

        // Vesting
        LinearVesting linearVestingModule;

        // If vesting is enabled
        if (params.vestingStart != 0 || params.vestingExpiry != 0) {
            // Get the linear vesting module (or revert)
            linearVestingModule = LinearVesting(_getLatestLinearVestingModule());

            // Validate
            if (
                // We will actually use the LP tokens, but this is a placeholder as we really want to validate the vesting parameters
                !linearVestingModule.validate(
                    address(baseToken_),
                    _getEncodedVestingParams(params.vestingStart, params.vestingExpiry)
                )
            ) {
                revert Callback_Params_InvalidVestingParams();
            }
        }

        // If the recipient is the zero address
        if (params.recipient == address(0)) {
            revert Callback_Params_InvalidAddress();
        }

        // Store the configuration
        lotConfiguration[lotId_] = DTLConfiguration({
            recipient: params.recipient,
            lotCapacity: capacity_,
            lotCuratorPayout: 0,
            proceedsUtilisationPercent: params.proceedsUtilisationPercent,
            vestingStart: params.vestingStart,
            vestingExpiry: params.vestingExpiry,
            linearVestingModule: linearVestingModule,
            active: true,
            implParams: params.implParams
        });

        // Call the Uniswap-specific implementation
        __onCreate(lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, callbackData_);
    }

    /// @notice     Uniswap-specific implementation of the onCreate callback
    /// @dev        The implementation will be called by the _onCreate function
    ///             after the `callbackData_` has been validated and after the
    ///             lot configuration is stored.
    ///
    ///             The implementation should perform the following:
    ///             - Additional validation
    ///
    /// @param      lotId_          The lot ID
    /// @param      seller_         The seller address
    /// @param      baseToken_      The base token address
    /// @param      quoteToken_     The quote token address
    /// @param      capacity_       The capacity of the lot
    /// @param      prefund_        Whether the lot is prefunded
    /// @param      callbackData_   Encoded OnCreateParams struct
    function __onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal virtual;

    /// @notice     Callback for when a lot is cancelled
    /// @dev        This function performs the following:
    ///             - Marks the lot as inactive
    ///
    ///             This function reverts if:
    ///             - The lot is not registered
    ///
    /// @param      lotId_          The lot ID
    function _onCancel(
        uint96 lotId_,
        uint256,
        bool,
        bytes calldata
    ) internal override onlyIfLotExists(lotId_) {
        // Mark the lot as inactive to prevent further actions
        DTLConfiguration storage config = lotConfiguration[lotId_];
        config.active = false;
    }

    /// @notice     Callback for when a lot is curated
    /// @dev        This function performs the following:
    ///             - Records the curator payout
    ///
    ///             This function reverts if:
    ///             - The lot is not registered
    ///
    /// @param      lotId_          The lot ID
    /// @param      curatorPayout_  The maximum curator payout
    function _onCurate(
        uint96 lotId_,
        uint256 curatorPayout_,
        bool,
        bytes calldata
    ) internal override onlyIfLotExists(lotId_) {
        // Update the funding
        DTLConfiguration storage config = lotConfiguration[lotId_];
        config.lotCuratorPayout = curatorPayout_;
    }

    /// @notice     Callback for a purchase
    /// @dev        Not implemented
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

    /// @notice     Callback for a bid
    /// @dev        Not implemented
    function _onBid(uint96, uint64, address, uint256, bytes calldata) internal pure override {
        // Not implemented
        revert Callback_NotImplemented();
    }

    /// @notice     Callback for claiming the proceeds
    /// @dev        This function performs the following:
    ///             - Calculates the base and quote tokens to deposit into the pool
    ///             - Calls the Uniswap-specific implementation to mint and deposit into the pool
    ///             - If vesting is enabled, mints the vesting tokens, or transfers the LP tokens to the recipient
    ///             - Sends any remaining quote and base tokens to the seller
    ///
    ///             The assumptions are:
    ///             - the callback has `proceeds_` quantity of quote tokens (as `receiveQuoteTokens` flag is set)
    ///             - the seller has the required balance of base tokens
    ///             - the seller has approved the callback to spend the base tokens
    ///
    ///             This function reverts if:
    ///             - The lot is not registered
    ///
    /// @param      lotId_          The lot ID
    /// @param      proceeds_       The proceeds from the auction
    /// @param      refund_         The refund from the auction
    /// @param      callbackData_   Implementation-specific data
    function _onClaimProceeds(
        uint96 lotId_,
        uint256 proceeds_,
        uint256 refund_,
        bytes calldata callbackData_
    ) internal virtual override onlyIfLotExists(lotId_) {
        DTLConfiguration memory config = lotConfiguration[lotId_];
        address seller;
        address baseToken;
        address quoteToken;
        {
            ERC20 baseToken_;
            ERC20 quoteToken_;
            (seller, baseToken_, quoteToken_,,,,,,) = AuctionHouse(auctionHouse).lotRouting(lotId_);
            baseToken = address(baseToken_);
            quoteToken = address(quoteToken_);
        }

        uint256 baseTokensRequired;
        uint256 quoteTokensRequired;
        {
            // Calculate the actual lot capacity that was used
            uint256 capacityUtilised;
            {
                // If curation is enabled, refund_ will also contain the refund on the curator payout. Adjust for that.
                // Example:
                // 100 capacity + 10 curator
                // 90 capacity sold, 9 curator payout
                // 11 refund
                // Utilisation = 1 - 11/110 = 90%
                uint256 utilisationPercent =
                    1e5 - refund_ * 1e5 / (config.lotCapacity + config.lotCuratorPayout);

                capacityUtilised = (config.lotCapacity * utilisationPercent) / MAX_PERCENT;
            }

            // Calculate the base tokens required to create the pool
            baseTokensRequired =
                _tokensRequiredForPool(capacityUtilised, config.proceedsUtilisationPercent);
            quoteTokensRequired =
                _tokensRequiredForPool(proceeds_, config.proceedsUtilisationPercent);
        }

        // Ensure the required tokens are present before minting
        {
            // Check that sufficient balance exists
            uint256 baseTokenBalance = ERC20(baseToken).balanceOf(seller);
            if (baseTokenBalance < baseTokensRequired) {
                revert Callback_InsufficientBalance(
                    baseToken, seller, baseTokensRequired, baseTokenBalance
                );
            }

            ERC20(baseToken).safeTransferFrom(seller, address(this), baseTokensRequired);
        }

        // Mint and deposit into the pool
        (ERC20 poolToken) = _mintAndDeposit(
            lotId_, quoteToken, quoteTokensRequired, baseToken, baseTokensRequired, callbackData_
        );
        uint256 poolTokenQuantity = poolToken.balanceOf(address(this));

        // If vesting is enabled, create the vesting tokens
        if (address(config.linearVestingModule) != address(0)) {
            // Approve spending of the tokens
            poolToken.approve(address(config.linearVestingModule), poolTokenQuantity);

            // Mint the vesting tokens (it will deploy if necessary)
            config.linearVestingModule.mint(
                config.recipient,
                address(poolToken),
                _getEncodedVestingParams(config.vestingStart, config.vestingExpiry),
                poolTokenQuantity,
                true // Wrap vesting LP tokens so they are easily visible
            );
        }
        // Send the LP tokens to the seller
        else {
            poolToken.safeTransfer(config.recipient, poolTokenQuantity);
        }

        // Send any remaining quote tokens to the seller
        {
            uint256 quoteTokenBalance = ERC20(quoteToken).balanceOf(address(this));
            if (quoteTokenBalance > 0) {
                ERC20(quoteToken).safeTransfer(seller, quoteTokenBalance);
            }
        }

        // Send any remaining base tokens to the seller
        {
            uint256 baseTokenBalance = ERC20(baseToken).balanceOf(address(this));
            if (baseTokenBalance > 0) {
                ERC20(baseToken).safeTransfer(seller, baseTokenBalance);
            }
        }
    }

    /// @notice     Mint and deposit into the pool
    /// @dev        This function should be implemented by the Uniswap-specific callback
    ///
    ///             It is expected to:
    ///             - Create and initialize the pool
    ///             - Deposit the quote and base tokens into the pool
    ///             - The pool tokens should be received by this contract
    ///             - Return the ERC20 pool token
    ///
    /// @param      lotId_              The lot ID
    /// @param      quoteToken_         The quote token address
    /// @param      quoteTokenAmount_   The amount of quote tokens to deposit
    /// @param      baseToken_          The base token address
    /// @param      baseTokenAmount_    The amount of base tokens to deposit
    /// @param      callbackData_       Implementation-specific data
    /// @return     poolToken           The ERC20 pool token
    function _mintAndDeposit(
        uint96 lotId_,
        address quoteToken_,
        uint256 quoteTokenAmount_,
        address baseToken_,
        uint256 baseTokenAmount_,
        bytes memory callbackData_
    ) internal virtual returns (ERC20 poolToken);

    // ========== MODIFIERS ========== //

    modifier onlyIfLotDoesNotExist(uint96 lotId_) {
        if (lotConfiguration[lotId_].recipient != address(0)) {
            revert Callback_InvalidParams();
        }
        _;
    }

    modifier onlyIfLotExists(uint96 lotId_) {
        if (!lotConfiguration[lotId_].active) {
            revert Callback_InvalidParams();
        }
        _;
    }

    // ========== INTERNAL FUNCTIONS ========== //

    function _getAmountWithSlippage(
        uint256 amount_,
        uint24 slippage_
    ) internal pure returns (uint256) {
        if (slippage_ > MAX_PERCENT) {
            revert Callback_Params_PercentOutOfBounds(slippage_, 0, MAX_PERCENT);
        }

        return (amount_ * (MAX_PERCENT - slippage_)) / MAX_PERCENT;
    }

    function _tokensRequiredForPool(
        uint256 amount_,
        uint24 proceedsUtilisationPercent_
    ) internal pure returns (uint256) {
        return (amount_ * proceedsUtilisationPercent_) / MAX_PERCENT;
    }

    function _getLatestLinearVestingModule() internal view returns (address) {
        AuctionHouse auctionHouseContract = AuctionHouse(auctionHouse);
        Keycode moduleKeycode = Keycode.wrap(LINEAR_VESTING_KEYCODE);

        // Get the module status
        (uint8 latestVersion, bool isSunset) = auctionHouseContract.getModuleStatus(moduleKeycode);

        if (isSunset || latestVersion == 0) {
            revert Callback_LinearVestingModuleNotFound();
        }

        return address(
            auctionHouseContract.getModuleForVeecode(wrapVeecode(moduleKeycode, latestVersion))
        );
    }

    function _getEncodedVestingParams(
        uint48 start_,
        uint48 expiry_
    ) internal pure returns (bytes memory) {
        return abi.encode(LinearVesting.VestingParams({start: start_, expiry: expiry_}));
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// Axis dependencies
import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {BaseCallback} from "src/callbacks/BaseCallback.sol";
import {Callbacks} from "src/lib/Callbacks.sol";
import {IAuctionHouse} from "src/interfaces/IAuctionHouse.sol";
import {
    Keycode as AxisKeycode,
    keycodeFromVeecode,
    fromKeycode as fromAxisKeycode
} from "src/modules/Keycode.sol";
import {Module as AxisModule} from "src/modules/Modules.sol";
import {IFixedPriceBatch} from "src/interfaces/modules/auctions/IFixedPriceBatch.sol";

// Baseline dependencies
import {
    Kernel,
    Policy,
    Keycode as BaselineKeycode,
    toKeycode as toBaselineKeycode,
    Permissions as BaselinePermissions
} from "src/callbacks/liquidity/BaselineV2/lib/Kernel.sol";
import {Range, IBPOOLv1} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";
import {TimeslotLib} from "src/callbacks/liquidity/BaselineV2/lib/TimeslotLib.sol";
import {TickMath} from "lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

// Other libraries
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";

/// @notice     Axis auction callback to initialize a Baseline token using proceeds from a batch auction.
/// @dev        This contract combines Baseline's InitializeProtocol Policy and Axis' Callback functionality to build an Axis auction callback specific to Baseline V2 token launches
///             It is designed to be used with a single auction and Baseline pool
contract BaselineAxisLaunch is BaseCallback, Policy, Owned {
    using FixedPointMathLib for uint256;
    using TimeslotLib for uint256;

    // ========== ERRORS ========== //

    error Callback_AlreadyComplete();
    error Callback_MissingFunds();

    error InvalidModule();
    error Insolvent();

    // ========== EVENTS ========== //

    event LiquidityDeployed(int24 tickLower, int24 tickUpper, uint128 liquidity);

    // ========== DATA STRUCTURES ========== //

    /// @notice Data struct for the onCreate callback
    ///
    /// @param  discoveryTickWidth      The width of the discovery tick range, as a multiple of the pool tick spacing.
    /// @param  allowlistParams         Additional parameters for an allowlist, passed to `__onCreate()` for further processing
    struct CreateData {
        int24 discoveryTickWidth;
        bytes allowlistParams;
    }

    // ========== STATE VARIABLES ========== //

    // Baseline Modules
    // solhint-disable-next-line var-name-mixedcase
    IBPOOLv1 public BPOOL;

    // Pool variables
    ERC20 public immutable RESERVE;
    ERC20 public bAsset;

    // Accounting
    uint256 public initialCirculatingSupply;
    uint256 public reserveBalance;

    // Axis Auction Variables

    /// @notice Lot ID of the auction for the baseline market. This callback only supports one lot.
    /// @dev    This value is initialised with the uint96 max value to indicate that it has not been set yet.
    uint96 public lotId;

    /// @notice Indicates whether the auction is complete
    /// @dev    This is used to prevent the callback from being called multiple times. It is set in the `onSettle()` callback.
    bool public auctionComplete;

    // solhint-disable-next-line private-vars-leading-underscore
    uint48 internal constant ONE_HUNDRED_PERCENT = 100_000;

    // ========== CONSTRUCTOR ========== //

    /// @notice Constructor for BaselineAxisLaunch
    ///
    /// @param  auctionHouse_   The AuctionHouse the callback is paired with
    /// @param  baselineKernel_ Address of the Baseline kernel
    /// @param  reserve_        Address of the reserve token. This should match the quote token for the auction lot.
    /// @param  owner_          Address of the owner of this policy. Will be permitted to perform admin functions. This is explicitly required, as `msg.sender` cannot be used due to the use of CREATE2 for deployment.
    constructor(
        address auctionHouse_,
        address baselineKernel_,
        address reserve_,
        address owner_
    )
        BaseCallback(
            auctionHouse_,
            Callbacks.Permissions({
                onCreate: true,
                onCancel: true,
                onCurate: true,
                onPurchase: false,
                onBid: true,
                onSettle: true,
                receiveQuoteTokens: true,
                sendBaseTokens: true
            })
        )
        Policy(Kernel(baselineKernel_))
        Owned(owner_)
    {
        // Set lot ID to max uint(96) initially so it doesn't reference a lot
        lotId = type(uint96).max;

        // Set the reserve token
        RESERVE = ERC20(reserve_);
    }

    // ========== POLICY FUNCTIONS ========== //

    /// @inheritdoc Policy
    function configureDependencies()
        external
        override
        returns (BaselineKeycode[] memory dependencies)
    {
        BaselineKeycode bpool = toBaselineKeycode("BPOOL");

        // Populate the dependencies array
        dependencies = new BaselineKeycode[](1);
        dependencies[0] = bpool;

        // Set local values
        BPOOL = IBPOOLv1(getModuleAddress(bpool));
        bAsset = ERC20(address(BPOOL));

        // Require that the BPOOL's reserve token be the same as the callback's reserve token
        if (address(BPOOL.reserve()) != address(RESERVE)) revert InvalidModule();
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (BaselinePermissions[] memory requests)
    {
        BaselineKeycode bpool = toBaselineKeycode("BPOOL");

        requests = new BaselinePermissions[](6);
        requests[0] = BaselinePermissions(bpool, BPOOL.initializePool.selector);
        requests[1] = BaselinePermissions(bpool, BPOOL.addReservesTo.selector);
        requests[2] = BaselinePermissions(bpool, BPOOL.addLiquidityTo.selector);
        requests[3] = BaselinePermissions(bpool, BPOOL.burnAllBAssetsInContract.selector);
        requests[4] = BaselinePermissions(bpool, BPOOL.mint.selector);
        requests[5] = BaselinePermissions(bpool, BPOOL.setTicks.selector);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    // CALLBACK PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: false
    // onBid: true
    // onSettle: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11101111 = 0xEF

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Sets the `lotId`, `percentReservesFloor`, `anchorTickWidth`, and `discoveryTickWidth` variables
    ///                 - Calls the allowlist callback
    ///                 - Mints the required bAsset tokens to the AuctionHouse
    ///
    ///                 This function reverts if:
    ///                 - `baseToken_` is not the same as `bAsset`
    ///                 - `quoteToken_` is not the same as `RESERVE`
    ///                 - `lotId` is already set
    ///                 - `CreateData.percentReservesFloor` is less than 0% or greater than 100%
    ///                 - `CreateData.anchorTickWidth` is 0
    ///                 - `CreateData.discoveryTickWidth` is 0
    ///                 - The auction format is not supported
    ///                 - FPB auction format: `CreateData.initAnchorTick` is 0
    ///                 - The auction is not prefunded
    function _onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes calldata callbackData_
    ) internal override {
        // Validate the base token is the baseline token
        // and the quote token is the reserve
        if (baseToken_ != address(bAsset) || quoteToken_ != address(RESERVE)) {
            revert Callback_InvalidParams();
        }

        // Validate that the lot ID is not already set
        if (lotId != type(uint96).max) revert Callback_InvalidParams();

        // Decode the provided callback data (must be correctly formatted even if not using parts of it)
        CreateData memory cbData = abi.decode(callbackData_, (CreateData));

        // Validate the discovery tick width is at least 1 tick spacing
        if (cbData.discoveryTickWidth <= 0) {
            revert Callback_InvalidParams();
        }

        // Auction must be prefunded for batch auctions (which is the only type supported with this callback),
        // this can't fail because it's checked in the AH as well, but including for completeness
        if (!prefund_) revert Callback_InvalidParams();

        // Set the lot ID
        lotId = lotId_;

        // Get the auction format
        AxisKeycode auctionFormat = keycodeFromVeecode(
            AxisModule(address(IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId))).VEECODE()
        );

        // Only supports Fixed Price Batch Auctions initially
        if (fromAxisKeycode(auctionFormat) != bytes5("FPBA")) {
            revert Callback_InvalidParams();
        }

        // This contract can be extended with an allowlist for the auction
        // Call a lower-level function where this information can be used
        // We do this before token interactions to conform to CEI
        __onCreate(
            lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, cbData.allowlistParams
        );

        // Calculate the initial active tick from the auction price without rounding
        int24 activeTick;
        {
            IFixedPriceBatch auctionModule = IFixedPriceBatch(
                address(IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId_))
            );

            // Get the fixed price from the auction module
            // This value is in the number of reserve tokens per baseline token
            uint256 auctionPrice = auctionModule.getAuctionData(lotId_).price;
            (,,, uint8 baseTokenDecimals,,,,) = auctionModule.lotData(lotId_);

            // Calculate the active tick from the auction price
            // `getSqrtPriceX96` handles token ordering
            // The resulting tick will incorporate any differences in decimals between the tokens
            uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
                address(RESERVE), address(bAsset), auctionPrice, 10 ** baseTokenDecimals
            );
            activeTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

            // To avoid a situation where the pool's active tick is the same as the floor range's lower tick (which is possible due to rounding and tick spacing, and would cause a revert upon settlement), we pre-emptively do the rounding here.
            activeTick = _roundTickToSpacing(activeTick, BPOOL.TICK_SPACING());
        }

        // Initialize the Baseline pool at the tick determined by the auction price
        BPOOL.initializePool(activeTick);

        // Get the tick spacing from the Baseline pool
        int24 tickSpacing = BPOOL.TICK_SPACING();

        // Set the ticks for the Baseline pool initially with the following assumptions:
        // - The active tick is the upper floor tick
        // - There is no anchor (width of the anchor tick range is 0)
        // - The discovery range is set to the active tick plus the discovery tick width
        BPOOL.setTicks(Range.FLOOR, activeTick - tickSpacing, activeTick);
        BPOOL.setTicks(Range.ANCHOR, activeTick, activeTick);
        BPOOL.setTicks(
            Range.DISCOVERY, activeTick, activeTick + tickSpacing * cbData.discoveryTickWidth
        );

        // Mint the capacity of baseline tokens to the auction house to prefund the auction
        BPOOL.mint(msg.sender, capacity_);
        initialCirculatingSupply += capacity_;
    }

    /// @notice Override this function to implement allowlist functionality
    function __onCreate(
        uint96 lotId_,
        address seller_,
        address baseToken_,
        address quoteToken_,
        uint256 capacity_,
        bool prefund_,
        bytes memory allowlistData_
    ) internal virtual {}

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Burns the refunded bAsset tokens
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///                 - The AuctionHouse has already sent the correct amount of bAsset tokens
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - The auction is already complete
    ///                 - Sufficient quantity of `bAsset` have not been sent to the callback
    function _onCancel(uint96 lotId_, uint256 refund_, bool, bytes calldata) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that the lot is not already settled or cancelled
        if (auctionComplete) revert Callback_AlreadyComplete();

        // Burn any refunded tokens (all auctions are prefunded)
        // Verify that the callback received the correct amount of bAsset tokens
        if (bAsset.balanceOf(address(this)) < refund_) revert Callback_MissingFunds();

        // Set the auction lot to be cancelled
        auctionComplete = true;

        // Send tokens to BPOOL and then burn
        initialCirculatingSupply -= refund_;
        Transfer.transfer(bAsset, address(BPOOL), refund_, false);
        BPOOL.burnAllBAssetsInContract();
    }

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - The curator fee is non-zero
    function _onCurate(
        uint96 lotId_,
        uint256 curatorFee_,
        bool,
        bytes calldata
    ) internal view override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Require that the curator fee in the Auction House is zero
        // We do this to not dilute the buyer's backing (and therefore the price that the Baseline pool is initialized at)
        if (curatorFee_ > 0) revert Callback_InvalidParams();
    }

    /// @inheritdoc BaseCallback
    /// @dev        Not implemented since atomic auctions are not supported
    function _onPurchase(
        uint96,
        address,
        uint256,
        uint256,
        bool,
        bytes calldata
    ) internal pure override {
        revert Callback_NotImplemented();
    }

    /// @inheritdoc BaseCallback
    /// @dev        No logic is needed for this function here, but it can be overridden by a lower-level contract to provide allowlist functionality
    function _onBid(
        uint96 lotId_,
        uint64 bidId,
        address buyer_,
        uint256 amount_,
        bytes calldata callbackData_
    ) internal virtual override {}

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 - Performs validation
    ///                 - Sets the auction as complete
    ///                 - Burns any refunded bAsset tokens
    ///                 - Calculates the deployment parameters for the Baseline pool
    ///                 - EMP auction format: calculates the ticks based on the clearing price
    ///                 - Deploys reserves into the Baseline pool
    ///
    ///                 Note that there may be reserve assets left over after liquidity deployment, which must be manually withdrawn by the owner using `withdrawReserves()`.
    ///
    ///                 Next steps:
    ///                 - Activate the market making and credit facility policies in the Baseline stack, which cannot be enabled before the auction is settled and the pool is initialized
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///                 - The AuctionHouse has already sent the correct amount of quote tokens (proceeds)
    ///                 - The AuctionHouse is pre-funded, so does not require additional base tokens (bAssets) to be supplied
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
    ///                 - The auction is already complete
    ///                 - The reported proceeds received are less than the reserve balance
    ///                 - The reported refund received is less than the bAsset balance
    function _onSettle(
        uint96 lotId_,
        uint256 proceeds_,
        uint256 refund_,
        bytes calldata
    ) internal virtual override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Validate that the auction is not already complete
        if (auctionComplete) revert Callback_AlreadyComplete();

        // Validate that the callback received the correct amount of proceeds
        // As this is a single-use contract, reserve balance is likely 0 prior, but extra funds will not affect it
        if (proceeds_ > RESERVE.balanceOf(address(this))) revert Callback_MissingFunds();

        // Validate that the callback received the correct amount of base tokens as a refund
        // As this is a single-use contract and we control the minting of bAssets, bAsset balance is 0 prior
        if (refund_ > bAsset.balanceOf(address(this))) revert Callback_MissingFunds();

        // Set the auction as complete
        auctionComplete = true;

        //// Step 1: Burn any refunded bAsset tokens ////

        // Subtract refund from initial supply
        initialCirculatingSupply -= refund_;

        // Burn any refunded bAsset tokens that were sent from the auction house
        Transfer.transfer(bAsset, address(BPOOL), refund_, false);
        BPOOL.burnAllBAssetsInContract();

        //// Step 2: Deploy liquidity to the Baseline pool ////

        // Approve spending of the reserve token
        // There should not be any dangling approvals left
        Transfer.approve(RESERVE, address(BPOOL), proceeds_);

        // Add all of the proceeds to the Floor range
        BPOOL.addReservesTo(Range.FLOOR, proceeds_);

        // Add proportional liquidity to the Discovery range
        BPOOL.addLiquidityTo(Range.DISCOVERY, BPOOL.getLiquidity(Range.FLOOR) * 11 / 10);

        //// Step 3: Verify Solvency ////
        uint256 totalCapacity = BPOOL.getPosition(Range.FLOOR).capacity
            + BPOOL.getPosition(Range.ANCHOR).capacity + BPOOL.getPosition(Range.DISCOVERY).capacity;

        // Note: if this reverts, then the auction will not be able to be settled
        // and users will be able to claim refunds from the auction house
        if (totalCapacity < initialCirculatingSupply) revert Insolvent();

        // Emit an event
        {
            (int24 floorTickLower, int24 floorTickUpper) = BPOOL.getTicks(Range.FLOOR);
            emit LiquidityDeployed(floorTickLower, floorTickUpper, BPOOL.getLiquidity(Range.FLOOR));
        }
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Rounds the provided tick to the nearest tick spacing
    /// @dev    This function mimics the behaviour of BPOOL.getActiveTS() in handling edge cases.
    ///
    /// @param  tick        The tick to round
    /// @param  tickSpacing The tick spacing to round to
    function _roundTickToSpacing(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        int24 adjustedTick = (tick / tickSpacing) * tickSpacing;

        // Properly handle negative numbers and edge cases
        if (adjustedTick >= 0 || adjustedTick % tickSpacing == 0) {
            adjustedTick += tickSpacing;
        }

        return adjustedTick;
    }

    // ========== OWNER FUNCTIONS ========== //

    /// @notice Withdraws any remaining reserve tokens from the contract
    /// @dev    This is access-controlled to the owner
    ///
    /// @return withdrawnAmount The amount of reserve tokens withdrawn
    function withdrawReserves() external onlyOwner returns (uint256 withdrawnAmount) {
        withdrawnAmount = RESERVE.balanceOf(address(this));

        Transfer.transfer(RESERVE, owner, withdrawnAmount, false);

        return withdrawnAmount;
    }
}

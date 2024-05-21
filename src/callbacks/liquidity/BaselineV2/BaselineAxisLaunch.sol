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

// Baseline dependencies
import {
    Kernel,
    Policy,
    Keycode as BaselineKeycode,
    toKeycode as toBaselineKeycode,
    Permissions as BaselinePermissions
} from "src/callbacks/liquidity/BaselineV2/lib/Kernel.sol";
import {Range, Position, Ticks, IBPOOLv1} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";
import {ICREDTv1} from "src/callbacks/liquidity/BaselineV2/lib/ICREDT.sol";
import {LiquidityAmounts} from "lib/uniswap-v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TimeslotLib} from "src/callbacks/liquidity/BaselineV2/lib/TimeslotLib.sol";
import {TickMath} from "lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

// Other libraries
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {Transfer} from "src/lib/Transfer.sol";
import {SqrtPriceMath} from "src/lib/uniswap-v3/SqrtPriceMath.sol";

/// @notice     Axis auction callback to initialize a Baseline token using proceeds from an auction.
///
///
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

    event LiquidityDeployed(
        int24 floorTickLower,
        int24 floorTickUpper,
        int24 anchorTickUpper,
        uint256 floorReserves,
        uint256 anchorReserves
    );

    // ========== DATA STRUCTURES ========== //

    /// @notice Data struct for the onCreate callback
    ///
    /// @param  initAnchorTick           The initial anchor tick that the Baseline pool will be initialised at. Only used for fixed price sales.
    /// @param  percentReservesFloor    The percent of reserves to deploy in the floor range. The remainder will be deployed in the anchor range. (3 decimals of precision, e.g. 100% = 100_000 and 1% = 1_000)
    /// @param  anchorTickWidth         The width of the anchor tick range, as a multiple of the pool tick spacing. Stored as uint24 to prevent the anchor tick from being lower than the floor tick.
    /// @param  discoveryTickWidth      The width of the discovery tick range, as a multiple of the pool tick spacing. Stored as uint24 to prevent the discovery tick from being lower than the anchor tick.
    /// @param  allowlistParams         Additional parameters for an allowlist, passed to `__onCreate()` for further processing
    struct CreateData {
        int24 initAnchorTick;
        uint48 percentReservesFloor;
        uint24 anchorTickWidth;
        uint24 discoveryTickWidth;
        bytes allowlistParams;
    }

    // ========== STATE VARIABLES ========== //

    // Baseline Modules
    /* solhint-disable var-name-mixedcase */
    IBPOOLv1 public BPOOL;
    ICREDTv1 public CREDT;
    /* solhint-enable var-name-mixedcase */

    // Pool variables
    ERC20 public immutable RESERVE;
    ERC20 public bAsset;

    // Accounting
    uint256 public initialCirculatingSupply;
    uint256 public reserveBalance;

    // Config

    /// @notice The percent of reserves to deploy in the floor range (3 decimals of precision, e.g. 100% = 100_000 and 1% = 1_000)
    uint48 public percentReservesFloor;

    /// @notice The width of the anchor tick range, as a multiple of the pool tick spacing.
    uint24 public anchorTickWidth;

    /// @notice The width of the discovery tick range, as a multiple of the pool tick spacing.
    uint24 public discoveryTickWidth;

    // Axis Auction Variables

    /// @notice Lot ID of the auction for the baseline market. This callback only supports one lot.
    /// @dev    This value is initialised with the uint96 max value to indicate that it has not been set yet.
    uint96 public lotId;

    /// @notice The Axis Keycode corresponding to the auction format (module family) that the auction is using
    AxisKeycode public auctionFormat;

    /// @notice Indicates whether the auction is complete
    /// @dev    This is used to prevent the callback from being called multiple times. It is set in the `onSettle()` callback.
    bool public auctionComplete;

    // solhint-disable-next-line private-vars-leading-underscore
    uint48 internal constant ONE_HUNDRED_PERCENT = 100_000;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address baselineKernel_,
        address reserve_
    ) BaseCallback(auctionHouse_, permissions_) Policy(Kernel(baselineKernel_)) Owned(msg.sender) {
        // Set lot ID to max uint(96) initially
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
        BaselineKeycode credt = toBaselineKeycode("CREDT");

        // Populate the dependencies array
        dependencies = new BaselineKeycode[](2);
        dependencies[0] = bpool;
        dependencies[1] = credt;

        // Set local values
        BPOOL = IBPOOLv1(getModuleAddress(bpool));
        bAsset = ERC20(address(BPOOL));
        CREDT = ICREDTv1(getModuleAddress(credt));

        // Require that the BPOOL's reserve token be the same as the callback's reserve token
        if (address(BPOOL.reserve()) != address(RESERVE)) revert InvalidModule();

        // Require CREDT bAsset equal to BPOOL bAsset
        if (address(CREDT.bAsset()) != address(bAsset)) revert InvalidModule();
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (BaselinePermissions[] memory requests)
    {
        BaselineKeycode bpool = toBaselineKeycode("BPOOL");

        requests = new BaselinePermissions[](5);
        requests[0] = BaselinePermissions(bpool, BPOOL.initializePool.selector);
        requests[1] = BaselinePermissions(bpool, BPOOL.addReservesTo.selector);
        requests[2] = BaselinePermissions(bpool, BPOOL.addLiquidityTo.selector);
        requests[3] = BaselinePermissions(bpool, BPOOL.burnAllBAssetsInContract.selector);
        requests[4] = BaselinePermissions(bpool, BPOOL.mint.selector);
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

        // Validate that the percent of reserves in the floor is greater than 0% and less than or equal to 100%
        if (cbData.percentReservesFloor == 0 || cbData.percentReservesFloor > 100_000) {
            revert Callback_InvalidParams();
        }

        // Validate that the anchor tick width is at least 1 tick spacing
        if (cbData.anchorTickWidth == 0) {
            revert Callback_InvalidParams();
        }

        // Validate the discovery tick width is at least 1 tick spacing
        if (cbData.discoveryTickWidth == 0) {
            revert Callback_InvalidParams();
        }

        // Set the lot ID
        lotId = lotId_;

        // Get the auction format and store locally
        auctionFormat = keycodeFromVeecode(
            AxisModule(address(IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId))).VEECODE()
        );

        // Set the configuration
        percentReservesFloor = cbData.percentReservesFloor;
        anchorTickWidth = cbData.anchorTickWidth;
        discoveryTickWidth = cbData.discoveryTickWidth;

        // This contract can be extended with an allowlist for the auction
        // Call a lower-level function where this information can be used
        // We do this before token interactions to conform to CEI
        __onCreate(
            lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, cbData.allowlistParams
        );

        // Case 1: EMP Batch Auction
        if (fromAxisKeycode(auctionFormat) == bytes5("EMPA")) {
            // We disregard the initAnchorTick for EMPA auctions since it will be determined by the clearing price
            // Therefore, this is a no-op.
        }
        // Case 2: Fixed Price Batch Auction
        else if (fromAxisKeycode(auctionFormat) == bytes5("FPBA")) {
            // Baseline pool must be initialized now with the correct tick parameters
            // They should have been passed into the callback data
            if (cbData.initAnchorTick == 0) {
                revert Callback_InvalidParams();
            }

            int24 tickSpacing = BPOOL.TICK_SPACING();

            (
                int24 floorTickLower,
                int24 floorTickUpper,
                int24 anchorTickUpper,
                int24 discoveryTickUpper
            ) = _calculateTicks(
                cbData.initAnchorTick, tickSpacing, anchorTickWidth, discoveryTickWidth
            );

            // Initialize the Baseline pool with the provided tick data, since we know it ahead of time.
            BPOOL.initializePool(anchorTickUpper);

            BPOOL.setTicks(Range.FLOOR, floorTickLower, floorTickUpper);
            BPOOL.setTicks(Range.ANCHOR, floorTickUpper, anchorTickUpper);
            BPOOL.setTicks(Range.DISCOVERY, anchorTickUpper, discoveryTickUpper);
        }
        // No other supported formats
        else {
            revert Callback_InvalidParams();
        }

        // Auction must be prefunded for batch auctions (which is the only type supported with this callback),
        // this can't fail because it's checked in the AH as well, but including for completeness
        if (!prefund_) revert Callback_InvalidParams();

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
    ///                 - Sufficient quantity of `bAsset` have not been sent to the callback
    function _onCancel(uint96 lotId_, uint256 refund_, bool, bytes calldata) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Burn any refunded tokens (all auctions are prefunded)
        // Verify that the callback received the correct amount of bAsset tokens
        if (bAsset.balanceOf(address(this)) < refund_) revert Callback_MissingFunds();

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
    ///                 Note that there may be reserve assets left over after liquidity deployment, which must be manually withdrawn by the owner using `withdrawReserves()`
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
        // As this is a single-use contract, reserve balance is 0 prior
        if (proceeds_ > RESERVE.balanceOf(address(this))) revert Callback_MissingFunds();

        // Validate that the callback received the correct amount of base tokens as a refund
        // As this is a single-use contract, bAsset balance is 0 prior
        if (refund_ > bAsset.balanceOf(address(this))) revert Callback_MissingFunds();

        // Set the auction as complete
        auctionComplete = true;

        // Subtract refund from initial supply
        initialCirculatingSupply -= refund_;

        // Burn any refunded bAsset tokens that were sent from the auction house
        Transfer.transfer(bAsset, address(BPOOL), refund_, false);
        BPOOL.burnAllBAssetsInContract();

        // If EMP Batch Auction, we need to calculate tick values and initialize the pool
        if (fromAxisKeycode(auctionFormat) == bytes5("EMPA")) {
            // Calculate sqrtPriceX96 for the clearing price
            // The library function will handle ordering the tokens correctly
            uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
                address(RESERVE), address(bAsset), proceeds_, initialCirculatingSupply
            );
            int24 initAnchorTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

            (
                int24 floorTickLower,
                int24 floorTickUpper,
                int24 anchorTickUpper,
                int24 discoveryTickUpper
            ) = _calculateTicks(
                initAnchorTick, BPOOL.TICK_SPACING(), anchorTickWidth, discoveryTickWidth
            );

            // Initialize the Baseline pool with the calculated tick data
            BPOOL.initializePool(anchorTickUpper);

            BPOOL.setTicks(Range.FLOOR, floorTickLower, floorTickUpper);
            BPOOL.setTicks(Range.ANCHOR, floorTickUpper, anchorTickUpper);
            BPOOL.setTicks(Range.DISCOVERY, anchorTickUpper, discoveryTickUpper);
        }

        // Calculate the reserves to deploy in each range
        // TODO per above, probably need to calculate the percent in each range based on the
        // desired initial premium instead of providing directly.
        uint256 floorReserves = (proceeds_ * percentReservesFloor) / ONE_HUNDRED_PERCENT;
        uint256 anchorReserves = proceeds_ - floorReserves;

        // Deploy the reserves to the Baseline pool
        _deployLiquidity(floorReserves, anchorReserves);

        // Emit an event
        {
            Ticks memory floorTicks = BPOOL.getTicks(Range.FLOOR);
            Ticks memory anchorTicks = BPOOL.getTicks(Range.ANCHOR);

            emit LiquidityDeployed(
                floorTicks.lower, floorTicks.upper, anchorTicks.upper, floorReserves, anchorReserves
            );
        }
    }

    // ========== BASELINE POOL INTERACTIONS ========== //

    /// @dev    Reproduces much of this function: https://github.com/0xBaseline/baseline-v2/blob/88bb34b23b1627207e4c8d3fcd9efad22332eb5f/src/policies/BaselineInit.sol#L166
    function _deployLiquidity(
        uint256 _initialReservesF,
        uint256 _initialReservesA
    ) internal returns (uint256 floorReservesAdded, uint256 anchorReservesAdded) {
        (, floorReservesAdded,) = BPOOL.addReservesTo(Range.FLOOR, _initialReservesF);
        (, anchorReservesAdded,) = BPOOL.addReservesTo(Range.ANCHOR, _initialReservesA);
        BPOOL.addLiquidityTo(Range.DISCOVERY, BPOOL.getLiquidity(Range.ANCHOR) * 11 / 10);

        // verify solvency
        if (calculateTotalCapacity() < initialCirculatingSupply) revert Insolvent();

        return (floorReservesAdded, anchorReservesAdded);
    }

    /// @dev    Reproduces much of this function: https://github.com/0xBaseline/baseline-v2/blob/88bb34b23b1627207e4c8d3fcd9efad22332eb5f/src/policies/BaselineInit.sol#L166
    function calculateTotalCapacity() public view returns (uint256 capacity_) {
        Position memory floor = BPOOL.getPosition(Range.FLOOR);
        Position memory anchor = BPOOL.getPosition(Range.ANCHOR);
        Position memory disc = BPOOL.getPosition(Range.DISCOVERY);

        // TODO consider if this should be using the updated logic: https://github.com/0xBaseline/baseline-v2/blob/88bb34b23b1627207e4c8d3fcd9efad22332eb5f/src/policies/BaselineInit.sol#L194
        (uint160 sqrtPriceA,,,,,,) = BPOOL.pool().slot0();
        uint160 floorSqrtPriceU = sqrtPriceA < floor.sqrtPriceU ? sqrtPriceA : floor.sqrtPriceU;

        bool anchorExists = anchor.sqrtPriceL != anchor.sqrtPriceU;

        uint128 virtualLiquidity = LiquidityAmounts.getLiquidityForAmount1(
            floor.sqrtPriceL, floorSqrtPriceU, CREDT.totalCreditIssued()
        );

        // add virtual capacity
        capacity_ += LiquidityAmounts.getAmount0ForLiquidity(
            floor.sqrtPriceL, floorSqrtPriceU, virtualLiquidity
        );

        // add the capacity of the floor
        capacity_ += LiquidityAmounts.getAmount0ForLiquidity(
            floor.sqrtPriceL, floorSqrtPriceU, floor.liquidity
        );

        // add the capacitiy of the anchor if it exists and is in range
        if (anchorExists && sqrtPriceA > anchor.sqrtPriceL) {
            capacity_ += LiquidityAmounts.getAmount0ForLiquidity(
                anchor.sqrtPriceL,
                sqrtPriceA < anchor.sqrtPriceU ? sqrtPriceA : anchor.sqrtPriceU,
                anchor.liquidity
            );
        }

        // add the capacity of the discovery if it is in range
        if (sqrtPriceA > disc.sqrtPriceL) {
            capacity_ += LiquidityAmounts.getAmount0ForLiquidity(
                disc.sqrtPriceL,
                sqrtPriceA < disc.sqrtPriceU ? sqrtPriceA : disc.sqrtPriceU,
                disc.liquidity
            );
        }
    }

    // ========== UNISWAP V3 FUNCTIONS ========== //

    /// @notice Rounds a tick to the nearest tick spacing
    function _roundTick(int24 tick_, int24 tickSpacing_) internal pure returns (int24) {
        // Round down to the nearest tick spacing
        int24 adjustedTick = tick_ / tickSpacing_ * tickSpacing_;

        return adjustedTick;
    }

    /// @notice Calculates tick ranges, given the upper boundary of the anchor tick
    /// @dev    As the ranges are stacked upon each other, the ticks are rounded to the nearest tick spacing in order to avoid gaps or overlaps
    function _calculateTicks(
        int24 anchorTick_,
        int24 tickSpacing,
        uint24 anchorTickWidth_,
        uint24 discoveryTickWidth_
    )
        internal
        pure
        returns (
            int24 floorTickLower,
            int24 floorTickUpper,
            int24 anchorTickUpper,
            int24 discoveryTickUpper
        )
    {
        // Round the anchor tick to get the upper tick of the anchor range
        anchorTickUpper = _roundTick(anchorTick_, tickSpacing);

        // Floor tick upper is the lower tick of the anchor range
        floorTickUpper =
            _roundTick(anchorTickUpper - int24(anchorTickWidth_) * tickSpacing, tickSpacing);

        // Floor tick lower is 1 tick spacing lower than floorTickUpper
        floorTickLower = _roundTick(floorTickUpper - tickSpacing, tickSpacing);

        // Calculate the discovery tick
        discoveryTickUpper =
            _roundTick(anchorTickUpper + int24(discoveryTickWidth_) * tickSpacing, tickSpacing);

        return (floorTickLower, floorTickUpper, anchorTickUpper, discoveryTickUpper);
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

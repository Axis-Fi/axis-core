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
import {Range, PositionData, IBPOOLv1} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";
import {ICREDTv1} from "src/callbacks/liquidity/BaselineV2/lib/ICREDT.sol";
import {LiquidityAmounts} from "lib/uniswap-v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TimeslotLib} from "src/callbacks/liquidity/BaselineV2/lib/TimeslotLib.sol";
import {TickMath} from "lib/uniswap-v3-core/contracts/libraries/TickMath.sol";

// Other libraries
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {Transfer} from "src/lib/Transfer.sol";

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

    // ========== DATA STRUCTURES ========== //

    struct CreateData {
        int24 initFloorTick; // only used for fixed price sales
        int24 initActiveTick; // only used for fixed price sales
        uint48 percentReservesFloor; // Percent with 3 decimals of precision, e.g. 100% = 100_000 and 1% = 1_000
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
    uint48 public percentReservesFloor;

    // Axis Auction Variables

    /// @notice Lot ID of the auction for the baseline market. This callback only supports one lot.
    /// @dev    This value is initialised with the uint96 max value to indicate that it has not been set yet.
    uint96 public lotId;

    /// @notice The Axis Keycode corresponding to the auction format (module family) that the auction is using
    AxisKeycode public auctionFormat;

    bool public auctionComplete;

    // solhint-disable-next-line private-vars-leading-underscore
    uint48 internal constant ONE_HUNDRED_PERCENT = 100_000;

    /// @notice The # of ticks required for the liquidity premium to double in size
    /// @dev    Source: https://github.com/0xBaseline/baseline-v2/blob/0eb04f6db1045b5079ed99609ec01d8bb0d2b43a/script/DeployDev.s.sol#L56
    uint256 internal constant _TICK_PREMIUM_FACTOR = 4800e18;

    /// @notice The maximum allowable liquidity premium as a factor of anchor liquidity.
    /// @dev    i.e. a max liquidity premium of 1e18 means the premium cannot be greater than 1x the anchor liquidity.
    ///
    ///         Source: https://github.com/0xBaseline/baseline-v2/blob/0eb04f6db1045b5079ed99609ec01d8bb0d2b43a/script/DeployDev.s.sol#L52
    uint256 internal constant _MAX_LIQUIDITY_PREMIUM = 3e18;

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
    ///                 - Sets the lot ID
    ///                 - Mints the required bAsset tokens to the AuctionHouse
    ///
    ///                 This function reverts if:
    ///                 - `baseToken_` is not the same as `bAsset`
    ///                 - `quoteToken_` is not the same as `RESERVE`
    ///                 - `lotId` is already set
    ///                 - `CreateData.percentReservesFloor` is less than 0% or greater than 100%
    ///                 - The auction format is not supported
    ///                 - The auction format is FPS and the tick parameters are not set
    ///                 - The auction format is FPS and the auction does not have linear vesting enabled
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

        // Set the lot ID
        lotId = lotId_;

        // Get the auction format and store locally
        auctionFormat = keycodeFromVeecode(
            AxisModule(address(IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId))).VEECODE()
        );

        // This contract can be extended with an allowlist for the auction
        // Call a lower-level function where this information can be used
        // We do this before token interactions to conform to CEI
        __onCreate(
            lotId_, seller_, baseToken_, quoteToken_, capacity_, prefund_, cbData.allowlistParams
        );

        // Case 1: EMP Batch Auction
        if (fromAxisKeycode(auctionFormat) == bytes5("EMPA")) {
            // We disregard the initFloorTick and initActiveTick for EMPA auctions since it will be determined by the clearing price
            // Therefore, this is a no-op.
        }
        // Case 2: Fixed Price Batch Auction
        else if (fromAxisKeycode(auctionFormat) == bytes5("FPBA")) {
            // Baseline pool must be initialized now with the correct tick parameters
            // They should have been passed into the callback data
            if (cbData.initFloorTick == 0 || cbData.initActiveTick == 0) {
                revert Callback_InvalidParams();
            }

            // No need to check if the floor tick is less than the active tick, as the BPOOL module will do so.

            // Initialize the Baseline pool with the provided tick data, since we know it ahead of time.
            BPOOL.initializePool(cbData.initFloorTick, cbData.initActiveTick);
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
    ///                 - Mints the required amount of bAsset tokens to the AuctionHouse for paying the curator fee
    ///
    ///                 This function has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///
    ///                 This function reverts if:
    ///                 - `lotId_` is not the same as the stored `lotId`
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

        // TODO could support external curator fee with CREDT
        // Steps:
        // 1. Add a curator fee percent to the CreateData struct and store locally
        // 2. Store the curator address locally here
        // 3. a. If prefunded, issue credit to them here for the entire curator fee (based on capacity)
        // 3. b. If not prefunded, issue credit to them in the onPurchase function
        // 4. In onSettle, decrease the credit if there is a refund.
    }

    // Not implemented since atomic auctions are not supported
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

    // No logic is needed for this function here, but it can be overridden
    // by a lower-level contract to provide allowlist functionality
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
    ///                 - Deploys the Baseline pool
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
    ///                 - The BAsset is not set
    ///                 - The BAsset's Baseline factory is not consistent with `BASELINE_FACTORY`
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
            // Calculate the clearing price as an 18 decimal fixed point number
            uint256 clearingPrice = (proceeds_ * (uint256(10) ** bAsset.decimals()) * 1e18)
                / (initialCirculatingSupply * (uint256(10) ** RESERVE.decimals()));

            // Calculate sqrtPriceX96 from the clearing price
            uint256 sqrtPriceX96 = FixedPointMathLib.sqrt(clearingPrice) << 96;

            // TODO need to discuss with baseline team on how to determine floor and active ticks from price.
            // TODO can this be cast to uint160?
            int24 initFloorTick = TickMath.getTickAtSqrtRatio(uint160(sqrtPriceX96));
            int24 initActiveTick = 0; // TODO calculate from clearing price

            // Initialize the Baseline pool with the calculated tick data
            BPOOL.initializePool(initFloorTick, initActiveTick);
        }

        // Calculate the reserves to deploy in each range
        // TODO per above, probably need to calculate the percent in each range based on the
        // desired initial premium instead of providing directly.
        uint256 floorReserves = (proceeds_ * percentReservesFloor) / ONE_HUNDRED_PERCENT;
        uint256 anchorReserves = proceeds_ - floorReserves;

        // Deploy the reserves to the Baseline pool
        _deployLiquidity(floorReserves, anchorReserves);
    }

    // ========== BASELINE POOL INTERACTIONS ========== //

    /// @dev    Source: https://github.com/0xBaseline/baseline-v2/blob/0eb04f6db1045b5079ed99609ec01d8bb0d2b43a/src/policies/MarketMaking.sol#L353
    /// @return liquidityPremium    The premium for the liquidity (in 18 decimals)
    function _getLiquidityPremium() internal view returns (uint256 liquidityPremium) {
        (, int24 activeTick,,,,,) = BPOOL.pool().slot0();
        liquidityPremium =
            uint256(uint24(activeTick - BPOOL.floorTick())).divWad(_TICK_PREMIUM_FACTOR);
    }

    // Copied from BaselineV2/initializeProtocol.sol
    function _deployLiquidity(
        uint256 _initialReservesF,
        uint256 _initialReservesA
    ) internal returns (uint256 bAssetsDeployed, uint256 reservesDeployed) {
        // Reproduces much of this function: https://github.com/0xBaseline/baseline-v2/blob/0eb04f6db1045b5079ed99609ec01d8bb0d2b43a/src/policies/InitializeProtocol.sol#L126
        (uint256 floorBAssetsAdded, uint256 floorReservesAdded) =
            BPOOL.addReservesTo(Range.FLOOR, _initialReservesF);
        (uint256 anchorBAssetsAdded, uint256 anchorReservesAdded) =
            BPOOL.addReservesTo(Range.ANCHOR, _initialReservesA);

        // scale the discovery liquidity based on the new anchor liquidity
        uint128 liquidityA = BPOOL.getPositionLiquidity(Range.ANCHOR);

        // Calculate the leverage factor
        uint256 totalCollateral = CREDT.totalCollateralized();
        uint256 leverageFactor =
            1e18 + totalCollateral.divWad(bAsset.totalSupply() - totalCollateral);

        // Calculate the current liquidity premium and cap it
        uint256 liquidityPremium = _getLiquidityPremium().mulWad(leverageFactor);
        liquidityPremium =
            liquidityPremium > _MAX_LIQUIDITY_PREMIUM ? _MAX_LIQUIDITY_PREMIUM : liquidityPremium;

        // Calculate the surplus liquidity
        uint128 surplusLiquidityA = uint128(uint256(liquidityA).mulWad(liquidityPremium));

        // supply new bAssets to the top of the range at a ratio based on the premium
        (uint256 discoveryBAssetsAdded, uint256 discoveryReservesAdded) =
            BPOOL.addLiquidityTo(Range.DISCOVERY, liquidityA + surplusLiquidityA);

        // verify solvency
        if (calculateTotalCapacity() < initialCirculatingSupply) revert Insolvent();

        return (
            floorBAssetsAdded + anchorBAssetsAdded + discoveryBAssetsAdded,
            floorReservesAdded + anchorReservesAdded + discoveryReservesAdded
        );
    }

    // Copied from BaselineV2/initializeProtocol.sol
    function calculateTotalCapacity() public view returns (uint256 capacity_) {
        // Sourced from: https://github.com/0xBaseline/baseline-v2/blob/0eb04f6db1045b5079ed99609ec01d8bb0d2b43a/src/policies/InitializeProtocol.sol#L193
        PositionData memory floor = BPOOL.getPositionData(Range.FLOOR);
        PositionData memory anchor = BPOOL.getPositionData(Range.ANCHOR);
        PositionData memory disc = BPOOL.getPositionData(Range.DISCOVERY);

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
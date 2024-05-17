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
    fromKeycode as fromAxisKeycode,
    toKeycode as toAxisKeycode
} from "src/modules/Keycode.sol";
import {Module as AxisModule} from "src/modules/Modules.sol";
import {DerivativeModule} from "src/modules/Derivative.sol";
import {ILinearVesting} from "src/interfaces/modules/derivatives/ILinearVesting.sol";

// Baseline dependencies
import {
    Kernel,
    Policy,
    Keycode as BaselineKeycode,
    toKeycode as toBaselineKeycode,
    Permissions as BaselinePermissions
} from "src/callbacks/liquidity/BaselineV2/lib/Kernel.sol";
import {
    Range,
    PositionData,
    Action,
    IBPOOLv1
} from "src/callbacks/liquidity/BaselineV2/lib/IBPOOL.sol";
import {ICREDTv1} from "src/callbacks/liquidity/BaselineV2/lib/ICREDT.sol";
import {LiquidityAmounts} from "lib/uniswap-v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TimeslotLib} from "src/callbacks/liquidity/BaselineV2/lib/TimeslotLib.sol";

// Other libraries
import {FixedPointMathLib} from "lib/solady/src/utils/FixedPointMathLib.sol";
import {Transfer} from "src/lib/Transfer.sol";

/// @notice     Axis auction callback to initialize a Baseline token using proceeds from an auction.
///
///
/// @dev        This contract combines Baseline's InitializeProtocol Policy and Axis' Callback functionality to build an Axis auction callback specific to Baseline V2 token launches
///             It is designed to be used with a single auction and Baseline pool
contract BaselineAxisLaunch is BaseCallback, Policy {
    using FixedPointMathLib for uint256;
    using TimeslotLib for uint256;

    // ========== ERRORS ========== //

    error Callback_AlreadyComplete();
    error Callback_MissingFunds();

    error InvalidModule();
    error Insolvent();

    // ========== DATA STRUCTURES ========== //

    // TODO consider splitting into different structs for FPS vs EMP
    struct CreateData {
        int24 initFloorTick;
        int24 initActiveTick;
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
    int24 public initFloorTick;
    int24 public initActiveTick;
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

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        Callbacks.Permissions memory permissions_,
        address baselineKernel_,
        address reserve_
    ) BaseCallback(auctionHouse_, permissions_) Policy(Kernel(baselineKernel_)) {
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
        requests[1] = BaselinePermissions(bpool, BPOOL.manageReservesFor.selector);
        requests[2] = BaselinePermissions(bpool, BPOOL.manageLiquidityFor.selector);
        requests[3] = BaselinePermissions(bpool, BPOOL.burnAllBAssetsInContract.selector);
        requests[4] = BaselinePermissions(bpool, BPOOL.mint.selector);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    // CALLBACK PERMISSIONS
    // onCreate: true
    // onCancel: true
    // onCurate: true
    // onPurchase: true
    // onBid: true
    // onSettle: true
    // receiveQuoteTokens: true
    // sendBaseTokens: true
    // Contract prefix should be: 11111111 = 0xFF

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
            // Auction must be prefunded, this can't fail because it's checked in the AH as well, but including for completeness
            if (!prefund_) revert Callback_InvalidParams();

            // We disregard the initFloorTick and initActiveTick for EMPA auctions since it will be determined by the clearing price

            // Mint the capacity of baseline tokens to the auction house
            BPOOL.mint(msg.sender, capacity_);
            initialCirculatingSupply += capacity_;
        }
        // Case 2: Fixed Price Sale Atomic Auction
        else if (fromAxisKeycode(auctionFormat) == bytes5("FPSA")) {
            // Baseline pool must be initialized now with the correct tick parameters
            // They should have been passed into the callback data
            if (cbData.initFloorTick == 0 || cbData.initActiveTick == 0) {
                revert Callback_InvalidParams();
            }

            // Check that the auction has linear vesting enabled, so that buyers cannot front-run the pool deposits
            DerivativeModule derivativeModule = DerivativeModule(
                address(IAuctionHouse(AUCTION_HOUSE).getDerivativeModuleForId(lotId))
            );
            if (
                fromAxisKeycode(keycodeFromVeecode(derivativeModule.VEECODE()))
                    != fromAxisKeycode(toAxisKeycode("LIV"))
            ) {
                revert Callback_InvalidParams();
            }

            // Grab the conclusion time of the auction
            (, uint48 lotConclusion,,,,,,) =
                IAuctionHouse(AUCTION_HOUSE).getAuctionModuleForId(lotId).lotData(lotId);

            // Grab the vesting params from the lot's Routing data
            (,,,,,,,, bytes memory derivativeParams) =
                IAuctionHouse(AUCTION_HOUSE).lotRouting(lotId);
            ILinearVesting.VestingParams memory vestingParams =
                abi.decode(derivativeParams, (ILinearVesting.VestingParams));

            // Check that the vesting starts after the conclusion of the auction
            if (vestingParams.start <= lotConclusion) {
                revert Callback_InvalidParams();
            }

            // No need to check if the floor tick is less than the active tick, as the BPOOL module will do so.

            // Initialize the Baseline pool with the provided tick data, since we know it ahead of time.
            // This also allows us to deposit liquidity into the pool on each purchase.
            // Note: Because of this, any FPS auction using this callback should require payouts to vest
            // until the auction concludes to avoid trading from affecting the tick values.
            BPOOL.initializePool(cbData.initFloorTick, cbData.initActiveTick);

            // If auction is prefunded, we need to mint the capacity of baseline tokens to the auction house
            if (prefund_) {
                BPOOL.mint(msg.sender, capacity_);
                initialCirculatingSupply += capacity_;
            }
        }
        // No other supported formats
        else {
            revert Callback_InvalidParams();
        }
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
    function _onCancel(
        uint96 lotId_,
        uint256 refund_,
        bool prefunded_,
        bytes calldata
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // Burn the refunded tokens, if prefunded
        if (prefunded_) {
            // Verify that the callback received the correct amount of bAsset tokens
            if (bAsset.balanceOf(address(this)) < refund_) revert Callback_MissingFunds();

            // Send tokens to BPOOL and then burn
            initialCirculatingSupply -= refund_;
            Transfer.transfer(bAsset, address(BPOOL), refund_, false);
            BPOOL.burnAllBAssetsInContract();
        }
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
        bool prefunded_,
        bytes calldata
    ) internal override {
        // Validate the lot ID
        if (lotId_ != lotId) revert Callback_InvalidParams();

        // If the auction is prefunded and the curator fee is non-zero
        if (prefunded_ && curatorFee_ > 0) {
            // Mint the required amount of bAsset tokens to the AuctionHouse
            BPOOL.mint(msg.sender, curatorFee_);
            initialCirculatingSupply += curatorFee_;
        }

        // TODO could support external curator fee with CREDT
        // Steps:
        // 1. Add a curator fee percent to the CreateData struct and store locally
        // 2. Store the curator address locally here
        // 3. a. If prefunded, issue credit to them here for the entire curator fee (based on capacity)
        // 3. b. If not prefunded, issue credit to them in the onPurchase function
        // 4. In onSettle, decrease the credit if there is a refund.
    }

    /// @inheritdoc     BaseCallback
    /// @dev            This function performs the following:
    ///                 -
    ///
    ///                 It has the following assumptions:
    ///                 - BaseCallback has already validated the lot ID
    ///                 - The AuctionHouse has already sent the correct amount of quote tokens (reserves)
    ///                 - The AuctionHouse expects the callback function to send the correct amount of base tokens (bAssets)
    function _onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal override {
        // Verify that the callback received at least the amount of reserves expected
        uint256 newBalance = RESERVE.balanceOf(address(this));
        if (newBalance < reserveBalance + amount_) revert Callback_MissingFunds();

        // Update the reserve balance
        reserveBalance = newBalance;

        // This contract can be extended with an allowlist for the auction
        // Call a lower-level function where this information can be used
        // We do this before token interactions to conform to CEI
        __onPurchase(lotId_, buyer_, amount_, payout_, prefunded_, callbackData_);

        // If not prefunded, the auction house will expect the payout_ to be sent
        if (!prefunded_ && payout_ > 0) {
            BPOOL.mint(msg.sender, payout_);
            initialCirculatingSupply += payout_;
        }

        // Calculate the reserves to deploy in each range
        uint256 floorReserves = (amount_ * percentReservesFloor) / ONE_HUNDRED_PERCENT;
        uint256 anchorReserves = amount_ - floorReserves;

        // Deploy the reserves to the Baseline pool
        (, uint256 reservesDeployed) = _deployLiquidity(floorReserves, anchorReserves);

        // Decrease the reserve balance by the amount of reserves deployed (since it may be different to the `floorReserves` and `anchorReserves`)
        reserveBalance -= reservesDeployed;

        // TODO what happens to the reserves left over?
    }

    // Override with allowlist functionality
    function __onPurchase(
        uint96 lotId_,
        address buyer_,
        uint256 amount_,
        uint256 payout_,
        bool prefunded_,
        bytes calldata callbackData_
    ) internal virtual {}

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

        // Validate that the auction format is EMPA (only supported batch auction)
        if (fromAxisKeycode(auctionFormat) != bytes5("EMPA")) revert Callback_InvalidParams();

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

        // Calculate the clearing price in quote tokens per base token
        uint256 clearingPrice =
            (proceeds_ * (uint256(10) ** BPOOL.decimals())) / initialCirculatingSupply;
        // TODO discuss with baseline team
        initFloorTick = 0; // TODO calculate from clearing price
        initActiveTick = 0; // TODO calculate from clearing price

        // Burn any refunded bAsset tokens that were sent from the auction house
        Transfer.transfer(bAsset, address(BPOOL), refund_, false);
        BPOOL.burnAllBAssetsInContract();

        // Initialize the Baseline pool with the calculated tick data
        BPOOL.initializePool(initFloorTick, initActiveTick);

        // Calculate the reserves to deploy in each range
        uint256 floorReserves = (proceeds_ * percentReservesFloor) / ONE_HUNDRED_PERCENT;
        uint256 anchorReserves = proceeds_ - floorReserves;

        // Deploy the reserves to the Baseline pool
        _deployLiquidity(floorReserves, anchorReserves);

        // TODO what happens to the reserves left over?
    }

    // ========== BASELINE POOL INTERACTIONS ========== //

    function _deployLiquidity(
        uint256 _initialReservesF,
        uint256 _initialReservesA
    ) internal returns (uint256 bAssetsDeployed, uint256 reservesDeployed) {
        // TODO shift to addReservesTo: https://github.com/0xBaseline/baseline-v2/blob/rmliq/src/modules/BPOOL.v1.sol#138
        (uint256 floorBAssetsAdded, uint256 floorReservesAdded) =
            BPOOL.manageReservesFor(Range.FLOOR, Action.ADD, _initialReservesF);
        (uint256 anchorBAssetsAdded, uint256 anchorReservesAdded) =
            BPOOL.manageReservesFor(Range.ANCHOR, Action.ADD, _initialReservesA);

        // scale the discovery liquidity based on the new anchor liquidity
        uint128 liquidityA = BPOOL.getPositionLiquidity(Range.ANCHOR);

        (, int24 activeTick,,,,,) = BPOOL.pool().slot0();
        uint256 liquidityPremium = uint256(uint24(activeTick - BPOOL.floorTick())).divWad(4812); // initial liquidity premium
        // TODO document magic number

        // TODO document formula
        uint256 totalCollateral = CREDT.totalCollateralized();
        uint256 leverageFactor = 1e18 + (totalCollateral / (bAsset.totalSupply() - totalCollateral));
        // TODO check that scale is correct

        // TODO document formula
        uint128 extraLiquidityA =
            uint128(uint256(liquidityA).mulWad(liquidityPremium).mulWad(leverageFactor));

        // supply new bAssets to the top of the range at a ratio based on the premium
        // TODO shift to addLiquidityTo: https://github.com/0xBaseline/baseline-v2/blob/rmliq/src/modules/BPOOL.v1.sol#163
        (uint256 discoveryBAssetsAdded, uint256 discoveryReservesAdded) =
            BPOOL.manageLiquidityFor(Range.DISCOVERY, Action.ADD, liquidityA + extraLiquidityA);

        // verify solvency
        if (calculateTotalCapacity() < initialCirculatingSupply) revert Insolvent();

        return (
            floorBAssetsAdded + anchorBAssetsAdded + discoveryBAssetsAdded,
            floorReservesAdded + anchorReservesAdded + discoveryReservesAdded
        );
    }

    function calculateTotalCapacity() public view returns (uint256 capacity_) {
        PositionData memory floor = BPOOL.getPositionData(Range.FLOOR);
        PositionData memory anchor = BPOOL.getPositionData(Range.ANCHOR);
        PositionData memory disc = BPOOL.getPositionData(Range.DISCOVERY);

        // TODO document formula

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
}

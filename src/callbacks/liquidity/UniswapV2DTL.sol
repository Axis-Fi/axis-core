// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";

// Uniswap
import {IUniswapV2Factory} from "src/lib/uniswap-v2/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "src/lib/uniswap-v2/IUniswapV2Router02.sol";

// Callbacks
import {BaseDirectToLiquidity} from "src/callbacks/liquidity/BaseDTL.sol";

contract UniswapV2DirectToLiquidity is BaseDirectToLiquidity {
    // ========== STRUCTS ========== //

    /// @notice     Parameters for the onClaimProceeds callback
    /// @dev        This will be encoded in the `callbackData_` parameter
    ///
    /// @param      quoteTokenAmountMin     The minimum amount of quote tokens to add as liquidity
    /// @param      baseTokenAmountMin      The minimum amount of base tokens to add as liquidity
    struct OnClaimProceedsParams {
        uint256 quoteTokenAmountMin;
        uint256 baseTokenAmountMin;
    }

    // ========== STATE VARIABLES ========== //

    /// @notice     The Uniswap V2 factory
    /// @dev        This contract is used to create Uniswap V2 pools
    IUniswapV2Factory public uniV2Factory;

    /// @notice     The Uniswap V2 router
    /// @dev        This contract is used to add liquidity to Uniswap V2 pools
    IUniswapV2Router02 public uniV2Router;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address seller_,
        address uniswapV2Factory_,
        address uniswapV2Router_
    ) BaseDirectToLiquidity(auctionHouse_, seller_) {
        if (uniswapV2Factory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        uniV2Factory = IUniswapV2Factory(uniswapV2Factory_);

        if (uniswapV2Router_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        uniV2Router = IUniswapV2Router02(uniswapV2Router_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Validates the parameters
    ///
    ///             This function reverts if:
    ///             - The pool for the token combination already exists
    function __onCreate(
        uint96,
        address,
        address baseToken_,
        address quoteToken_,
        uint96,
        bool,
        bytes calldata
    ) internal virtual override {
        // Check that the pool does not exist
        if (uniV2Factory.getPair(baseToken_, quoteToken_) != address(0)) {
            revert Callback_Params_PoolExists();
        }
    }

    /// @inheritdoc BaseDirectToLiquidity
    /// @dev        This function implements the following:
    ///             - Creates the pool if necessary
    ///             - Deposits the tokens into the pool
    function _mintAndDeposit(
        uint96 lotId_,
        uint256 quoteTokenAmount_,
        uint256 baseTokenAmount_,
        bytes memory callbackData_
    ) internal virtual override returns (ERC20 poolToken) {
        // Decode the callback data
        OnClaimProceedsParams memory params = abi.decode(callbackData_, (OnClaimProceedsParams));

        DTLConfiguration memory config = lotConfiguration[lotId_];

        // Create and initialize the pool if necessary
        // Token orientation is irrelevant
        address pairAddress = uniV2Factory.getPair(config.baseToken, config.quoteToken);
        if (pairAddress == address(0)) {
            pairAddress = uniV2Factory.createPair(config.baseToken, config.quoteToken);
        }

        // Approve the router to spend the tokens
        ERC20(config.quoteToken).approve(address(uniV2Router), quoteTokenAmount_);
        ERC20(config.baseToken).approve(address(uniV2Router), baseTokenAmount_);

        // Deposit into the pool
        uniV2Router.addLiquidity(
            config.quoteToken,
            config.baseToken,
            quoteTokenAmount_,
            baseTokenAmount_,
            params.quoteTokenAmountMin,
            params.baseTokenAmountMin,
            address(this),
            block.timestamp
        );

        // Remove any dangling approvals
        // This is necessary, since the router may not spend all available tokens
        ERC20(config.quoteToken).approve(address(uniV2Router), 0);
        ERC20(config.baseToken).approve(address(uniV2Router), 0);

        return ERC20(pairAddress);
    }
}

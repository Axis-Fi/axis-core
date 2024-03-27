// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";

// Uniswap
import {IUniswapV2Factory} from "uniswap-v2-core/interfaces/IUniswapV2Factory.sol";

// Callbacks
import {BaseUniswapDirectToLiquidity} from "src/callbacks/liquidity/BaseUniswapDTL.sol";

contract UniswapV2DirectToLiquidity is BaseUniswapDirectToLiquidity {

    // ========== STATE VARIABLES ========== //

    IUniswapV2Factory public uniV2Factory;

    // ========== CONSTRUCTOR ========== //

    constructor(
        address auctionHouse_,
        address seller_,
        address uniswapV2Factory_,
        address uniswapV2Router_
    ) BaseUniswapDirectToLiquidity(auctionHouse_, seller_) {
        if (uniswapV2Factory_ == address(0)) {
            revert Callback_Params_InvalidAddress();
        }
        uniV2Factory = IUniswapV2Factory(uniswapV2Factory_);
    }

    // ========== CALLBACK FUNCTIONS ========== //

    /// @inheritdoc BaseUniswapDirectToLiquidity
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

    /// @inheritdoc BaseUniswapDirectToLiquidity
    function _mintAndDeposit(
        uint96 lotId_,
        uint256 quoteTokenAmount_,
        uint256 baseTokenAmount_
    ) internal virtual override returns (ERC20 poolToken) {
        DTLConfiguration memory config = lotConfiguration[lotId_];

        // Determine the ordering of tokens
        bool quoteTokenIsToken0 = config.quoteToken < config.baseToken;

        // Create and initialize the pool if necessary
        // Token orientation is irrelevant
        address pairAddress = uniV2Factory.getPair(config.baseToken, config.quoteToken);
        if (pairAddress == address(0)) {
            pairAddress = uniV2Factory.createPair(config.baseToken, config.quoteToken);
        }

        // Deposit into the pool
        // router.addLiquidity

        // TODO Handle slippage - encode in callback data?
    }
}

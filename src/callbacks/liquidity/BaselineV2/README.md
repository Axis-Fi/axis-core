# Baseline-Axis Callbacks

This directory contains a callbacks contract (with allowlist variants)
that launches a Baseline market upon settlement of an Axis auction.

## Supported Auction Formats

This callbacks contract currently only supported the Fixed Price Batch auction format.

## Lifecycle

1. Deploy Baseline stack
    - The BPOOL module will create a Uniswap V3 pool in the constructor.
    As a result, it requires the initial tick of the pool to be
    specified as a constructor argument.
    The price can be calculated using the following:

    ```solidity
        uint256 auctionPrice = 2e18; // Example price
        uint160 sqrtPriceX96 = SqrtPriceMath.getSqrtPriceX96(
            address(quoteToken), address(BPOOL), auctionPrice, 10 ** baseTokenDecimals
        );
        int24 activeTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    ```

    - Deploy the Baseline `Kernel`, `BPOOL` module and other policies (except for `BaselineInit`)
2. Deploy the Baseline-Axis callback
    - The `BatchAuctionHouse`, Baseline `Kernel`, quote token (aka reserve) and owner need to be specified as constructor arguments. See the `baselineAllocatedAllowlist-sample.json` file for an example of how to configure this.
    - The salt for the callback will need to be generated. See the [salts README](/script/salts/README.md) for instructions.
    - Run the deployment script. See the [deployment README](/script/deploy/README.md#running-the-deployment) for instructions.
    - Each callbacks contract is single-use, specific to the auction and Baseline stack.
3. Deploy the Axis auction, specifying the callbacks contract and parameters.
    - See [TestData.s.sol:createAuction](/script/ops/test/FixedPriceBatch-Baseline/TestData.s.sol) for an example of this.
    - Note that curator fees are not supported when using the Baseline-Axis callback.
    - `onCreate()` will be called on the callbacks contract. This results in:
        - The tick ranges on the Baseline `BPOOL` being configured
        - The auction capacity (in terms of `BPOOL` tokens) being minted and transferred to the `BatchAuctionHouse`.
4. When a bid is submitted, if the configured callbacks contract has allowlist functionality, it will determine if the bidder is allowed to bid.
5. On settlement of the auction, the following will happen:
    - Any refunded base tokens (`BPOOL` tokens) are burnt
    - The configured percentage of proceeds (quote/reserve tokens) are deposited into the floor range of the Baseline pool.
    - The remaining proceeds are deposited into the anchor range of the Baseline pool.
    - Proportional liquidity (currently 11/10 of the anchor range liquidity) is deployed as `BPOOL` tokens in the discovery range.
    - The solvency of the Baseline pool is verified.

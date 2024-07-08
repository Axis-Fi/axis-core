# FixedPriceBatch - Uniswap DTL Testing

## How to Test

1. Create a virtual testnet on Tenderly
2. Store the environment variables in an environment file
3. Deploy the Axis stack
4. Create the auction
    - You will need to provide the quote token, base token

## To Settle an Auction

Assumes you are using a Tenderly Virtual Testnet

1. Warp to the timestamp after the auction conclusion using the warp script
2. Run the settle auction script

#!/bin/bash

# Load environment variables
source .env

echo "RPC: $RPC_URL"
echo "Deployer: $DEPLOYER_ADDRESS"
echo "Seller: $1"
echo "Buyer: $2"

# Create auction
forge script ./script/ops/test/TestData.s.sol:TestData --sig "deployTestTokens(address,address)()" $1 $2 \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
--broadcast

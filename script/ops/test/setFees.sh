#!/bin/bash

# Load environment variables
source .env

# Create auction
forge script ./script/ops/test/TestData.s.sol:TestData --sig "setFees(string,uint48,uint48,uint48)()" $1 $2 $3 $4 \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
--broadcast
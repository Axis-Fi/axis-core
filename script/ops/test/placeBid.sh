#!/bin/bash

# Load environment variables
source .env

# Create auction
forge script ./script/ops/test/TestData.s.sol:TestData --sig "placeBid(uint96,uint256,uint256)()" $1 $2 $3 \
--rpc-url $RPC_URL --private-key $BIDDER_PRIVATE_KEY --froms $BIDDER_ADDRESS --slow -vvv \
--broadcast
#!/bin/bash

# Load environment variables
source .env

# Cancel auction
forge script ./script/ops/test/TestData.s.sol:TestData --sig "cancelAuction(uint96)()" $1 \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
--broadcast
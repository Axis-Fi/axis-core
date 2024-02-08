#!/bin/bash

# Load environment variables
source .env

# Deploy using script
forge script ./src/scripts/deploy/Deploy.s.sol:Deploy --sig "deploy(string)()" $CHAIN \
--rpc-url $RPC_URL --private-key $DEPLOYER_PRIVATE_KEY --froms $DEPLOYER_ADDRESS --slow -vvv \
# --broadcast --verify --verifier-url $ETHERSCAN_API --etherscan-api-key $ETHERSCAN_KEY # uncomment to broadcast to the network and verify
#!/bin/bash

# Usage:
# ./createAuction.sh <auctionType>
#
# Environment variables:
# CHAIN:              Chain name to deploy to. Corresponds to names in "./script/env.json".
# RPC_URL:            URL for the RPC node. Should be specified in .env.

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
AUCTION_TYPE=$1

# Check if Auction type is set
if [ -z "$AUCTION_TYPE" ]
then
  echo "No auction type specified. Provide a valid auction type."
  exit 1
fi

# Check if Auction type is valid
if [ "$AUCTION_TYPE" != "EMP" ] && [ "$AUCTION_TYPE" != "FPB" ]
then
  echo "Invalid auction type. Provide a valid auction type."
  exit 1
fi

# Set the function to call based on the auction type
if [ "$AUCTION_TYPE" == "EMP" ]
then
  CALLDATA=$(cast calldata "createAuction(uint256,uint256,address)" $2 $3 $4)
elif [ "$AUCTION_TYPE" == "FPB" ]
then
  CALLDATA=$(cast calldata "createFPBAuction()")
fi

# Create auction
forge script ./script/ops/test/TestData.s.sol:TestData --sig $CALLDATA \
--rpc-url $RPC_URL --private-key $BIDDER_PRIVATE_KEY --froms $BIDDER_ADDRESS --slow -vvv \
--broadcast
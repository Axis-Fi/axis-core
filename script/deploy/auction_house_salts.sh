#!/bin/bash

# Usage:
# ./auction_house_salts.sh <atomic | batch> <prefix> <SALT_KEY>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
MODE=$1
PREFIX=$2
SALT_KEY=$3

# Check that the mode is "atomic" or "batch"
if [ "$MODE" != "atomic" ] && [ "$MODE" != "batch" ]
then
  echo "Invalid mode specified. Provide 'atomic' or 'batch' after the command as argument 1."
  exit 1
fi

# Check that the prefix is specified
if [ -z "$PREFIX" ]
then
  echo "No search prefix specified. Provide the prefix after the command as argument 1."
  exit 1
fi

# Check that the salt key is specified
if [ -z "$SALT_KEY" ]
then
  echo "No salt key specified. Provide the salt key after the command as argument 3."
  exit 1
fi

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"

# Generate bytecode
forge script ./script/deploy/AuctionHouseSalts.s.sol:AuctionHouseSalts --sig "generate(string)()" $CHAIN

# Generate salts
# If the mode is atomic
if [ "$MODE" == "atomic" ]
then
  echo ""
  echo "AtomicAuctionHouse:"
  echo "    Using PREFIX: $PREFIX"
  ./script/deploy/salts.sh ./bytecode/AtomicAuctionHouse.bin $PREFIX $SALT_KEY
else # If the mode is batch
  echo ""
  echo "BatchAuctionHouse:"
  echo "    Using PREFIX: $PREFIX"
  ./script/deploy/salts.sh ./bytecode/BatchAuctionHouse.bin $PREFIX $SALT_KEY
fi

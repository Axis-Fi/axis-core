#!/bin/bash

# Usage:
# ./auction_house_salts.sh <atomic | batch> <prefix>
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

# Check that the mode is "atomic" or "batch"
if [ "$MODE" != "atomic" ] && [ "$MODE" != "batch" ]
then
  echo "Invalid mode specified. Provide 'atomic' or 'batch' after the command as argument 1."
  exit 1
fi

# Set flag for atomic or batch auction
ATOMIC=$( if [ "$MODE" == "atomic" ]; then echo "true"; else echo "false"; fi )

# Check that the prefix is specified
if [ -z "$PREFIX" ]
then
  echo "No search prefix specified. Provide the prefix after the command as argument 1."
  exit 1
fi

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"

# If the chain contains "blast", use the Blast-specific contracts to generate bytecode
if [[ $CHAIN == *"blast"* ]]
then
  echo "Using Blast-specific contracts"
  forge script ./script/salts/auctionHouse/AuctionHouseSaltsBlast.s.sol:AuctionHouseSaltsBlast --sig "generate(string,string,bool)()" $CHAIN $PREFIX $ATOMIC

    # Set the bytecode file
    if [ $ATOMIC ]
    then
        BYTECODE_FILE="BlastAtomicAuctionHouse"
    else
        BYTECODE_FILE="BlastBatchAuctionHouse"
    fi
else
  echo "Using standard contracts"
  forge script ./script/salts/auctionHouse/AuctionHouseSalts.s.sol:AuctionHouseSalts --sig "generate(string,string,bool)()" $CHAIN $PREFIX $ATOMIC

    # Set the bytecode file
    if [ $ATOMIC ]
    then
        BYTECODE_FILE="AtomicAuctionHouse"
    else
        BYTECODE_FILE="BatchAuctionHouse"
    fi
fi

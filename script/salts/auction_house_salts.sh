#!/bin/bash

# Usage:
# ./auction_house_salts.sh --type <atomic | batch> --prefix <prefix> --envFile <.env>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Iterate through named arguments
# Source: https://unix.stackexchange.com/a/388038
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    v="${1/--/}"
    declare $v="$2"
  fi

  shift
done

# Get the name of the .env file or use the default
ENV_FILE=${envFile:-".env"}
echo "Sourcing environment variables from $ENV_FILE"

# Load environment file
set -a  # Automatically export all variables
source $ENV_FILE
set +a  # Disable automatic export

# Check that the CHAIN environment variable is set
if [ -z "$CHAIN" ]
then
  echo "CHAIN environment variable is not set. Please set it in the .env file or provide it as an environment variable."
  exit 1
fi

# Check that the mode is "atomic" or "batch"
if [ "$type" != "atomic" ] && [ "$type" != "batch" ]
then
  echo "Invalid auction type specified. Provide 'atomic' or 'batch' after the --type flag."
  exit 1
fi

# Set flag for atomic or batch auction
ATOMIC=$( if [ "$type" == "atomic" ]; then echo "true"; else echo "false"; fi )

# Check that the prefix is specified
if [ -z "$prefix" ]
then
  echo "No search prefix specified. Provide the prefix after the --prefix flag."
  exit 1
fi

echo "Using chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"

# If the chain contains "blast", use the Blast-specific contracts to generate bytecode
if [[ $CHAIN == *"blast"* ]]
then
  echo "Using Blast-specific contracts"
  forge script ./script/salts/AuctionHouseSaltsBlast.s.sol:AuctionHouseSaltsBlast --sig "generate(string,string,bool)()" $CHAIN $prefix $ATOMIC

    # Set the bytecode file
    if [ $ATOMIC ]
    then
        BYTECODE_FILE="BlastAtomicAuctionHouse"
    else
        BYTECODE_FILE="BlastBatchAuctionHouse"
    fi
else
  echo "Using standard contracts"
  forge script ./script/salts/AuctionHouseSalts.s.sol:AuctionHouseSalts --sig "generate(string,string,bool)()" $CHAIN $prefix $ATOMIC

    # Set the bytecode file
    if [ $ATOMIC ]
    then
        BYTECODE_FILE="AtomicAuctionHouse"
    else
        BYTECODE_FILE="BatchAuctionHouse"
    fi
fi

#!/bin/bash

# Usage:
# ./auction_house_salts.sh --type <atomic | batch> --prefix <prefix>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Iterate through named arguments
# Source: https://unix.stackexchange.com/a/388038
while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        v="${1/--/}"
        declare $v="$2"
   fi

  shift
done

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

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"

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

#!/bin/bash

# Usage:
# ./auction_house_salts_blast.sh <ATOMIC_PREFIX> <BATCH_PREFIX>
#
# Expects the following environment variables:
# CHAIN: The chain to deploy to, based on values from the ./script/env.json file.

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
ATOMIC_PREFIX=${1:-"0x"}
BATCH_PREFIX=${2:-"0x"}

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"

# Generate bytecode
forge script ./script/deploy/AuctionHouseSaltsBlast.s.sol:AuctionHouseSaltsBlast --sig "generate(string)()" $CHAIN

# Generate salts
echo ""
echo "AtomicAuctionHouse:"
echo "    Using ATOMIC_PREFIX: $ATOMIC_PREFIX"
./script/salts.sh ./bytecode/BlastAtomicAuctionHouse.bin $ATOMIC_PREFIX

echo ""
echo "BatchAuctionHouse:"
echo "    Using BATCH_PREFIX: $BATCH_PREFIX"
./script/salts.sh ./bytecode/BlastBatchAuctionHouse.bin $BATCH_PREFIX

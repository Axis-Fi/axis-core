#!/bin/bash

# Usage:
# ./auction_house_salts.sh <ATOMIC_PREFIX> <BATCH_PREFIX>

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Get command-line arguments
ATOMIC_PREFIX=${1:-"0x"}
BATCH_PREFIX=${2:-"0x"}

# Generate bytecode
forge script ./script/deploy/AuctionHouseSalts.s.sol:AuctionHouseSalts --sig "generate(string)()" $CHAIN

# Generate salts
echo ""
echo "AtomicAuctionHouse:"
echo "    Using ATOMIC_PREFIX: $ATOMIC_PREFIX"
./script/salts.sh ./bytecode/AtomicAuctionHouse.bin $ATOMIC_PREFIX

echo ""
echo "BatchAuctionHouse:"
echo "    Using BATCH_PREFIX: $BATCH_PREFIX"
./script/salts.sh ./bytecode/BatchAuctionHouse.bin $BATCH_PREFIX

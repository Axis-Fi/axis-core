#!/bin/bash

# Usage:
# ./salts.sh <deploy-file> <broadcast=false> <verify=false>

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Deploy using script
forge script ./script/deploy/AuctionHouseSalts.s.sol:AuctionHouseSalts --sig "generate(string)()" $CHAIN

#!/bin/bash

# Usage:
# ./test_salts.sh

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"

# Generate bytecode
forge script ./script/deploy/TestSalts.s.sol:TestSalts --sig "generate(string)()" $CHAIN

# Generate salts

echo ""
echo ""
echo "AuctionHouseTest:"

echo ""
echo "MockCallback98:"
./script/deploy/salts.sh ./bytecode/MockCallback98.bin "98"

echo ""
echo "MockCallbackFF:"
./script/deploy/salts.sh ./bytecode/MockCallbackFF.bin "FF"

echo ""
echo "MockCallbackFD:"
./script/deploy/salts.sh ./bytecode/MockCallbackFD.bin "FD"

echo ""
echo "MockCallbackFE:"
./script/deploy/salts.sh ./bytecode/MockCallbackFE.bin "FE"

echo ""
echo "MockCallbackFC:"
./script/deploy/salts.sh ./bytecode/MockCallbackFC.bin "FC"

echo ""
echo ""
echo "SendPayment:"

echo ""
echo "MockCallback00:"
./script/deploy/salts.sh ./bytecode/MockCallback00.bin "00"

echo ""
echo "MockCallback02:"
./script/deploy/salts.sh ./bytecode/MockCallback02.bin "02"

echo ""
echo ""
echo "CappedMerkleAllowlist:"

echo ""
echo "CappedMerkleAllowlistBatch88:"
./script/deploy/salts.sh ./bytecode/CappedMerkleAllowlistBatch88.bin "88"

echo ""
echo "CappedMerkleAllowlistAtomic90:"
./script/deploy/salts.sh ./bytecode/CappedMerkleAllowlistAtomic90.bin "90"

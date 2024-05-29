#!/bin/bash

# Usage:
# ./test_salts.sh <salt key>

# Get command-line arguments
SALT_KEY=$1 # Which key to clear the salts for

# Load environment variables, but respect overrides
curenv=$(declare -p -x)
source .env
eval "$curenv"

# Check if SALT_KEY is specified
if [ -z "$SALT_KEY" ]
then
  echo "No salt key specified. Provide the salt key after the command."
  exit 1
fi

echo "Using RPC at URL: $RPC_URL"
echo "Using chain: $CHAIN"
echo "Salt key: $SALT_KEY"

salt_file="./script/salts/salts.json"
salt_tmp_file="./script/salts/salts.json.tmp"

# Clear the salts for the specified salt key
if [ -f $salt_file ]; then
    echo "Clearing old values for salt key: $SALT_KEY"
    jq "del(.\"Test_$SALT_KEY\")" $salt_file > $salt_tmp_file && mv $salt_tmp_file $salt_file
fi

# Generate bytecode
forge script ./script/salts/test/TestSalts.s.sol:TestSalts --sig "generate(string,string)()" $CHAIN $SALT_KEY

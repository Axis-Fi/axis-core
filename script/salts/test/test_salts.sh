#!/bin/bash

# Usage:
# ./test_salts.sh --saltKey <salt key> --envFile <.env>

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

# Check if saltKey is specified
if [ -z "$saltKey" ]
then
  echo "No salt key specified. Provide the salt key after the --saltKey flag."
  exit 1
fi

echo "Using chain: $CHAIN"
echo "Using RPC at URL: $RPC_URL"
echo "Salt key: $saltKey"

salt_file="./script/salts/salts.json"
salt_tmp_file="./script/salts/salts.json.tmp"

# Clear the salts for the specified salt key
if [ -f $salt_file ]; then
    echo "Clearing old values for salt key: $saltKey"
    jq "del(.\"Test_$saltKey\")" $salt_file > $salt_tmp_file && mv $salt_tmp_file $salt_file
fi

# Generate bytecode
forge script ./script/salts/test/TestSalts.s.sol:TestSalts --sig "generate(string,string)()" $CHAIN $saltKey

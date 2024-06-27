#!/bin/bash

# Usage:
# ./warp.sh --timestamp <timestamp> --envFile <.env>

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

# Check that the ADMIN_RPC_URL is defined
if [ -z "$ADMIN_RPC_URL" ]
then
  echo "No RPC URL specified. Set the ADMIN_RPC_URL environment variable."
  exit 1
fi

# Check that the timestamp is defined and is an integer
if [[ ! "$timestamp" =~ ^[0-9]+$ ]]
then
  echo "Invalid timestamp specified. Provide an integer after the --timestamp flag."
  exit 1
fi

echo "Using RPC at URL: $ADMIN_RPC_URL"

# Call
cast rpc evm_setNextBlockTimestamp "[\"$timestamp\"]" --raw --rpc-url $ADMIN_RPC_URL
echo "Warped to timestamp: $timestamp"

#!/bin/bash

# Usage:
# ./write_deployment.sh <key> <value>
# Updates the env.json file with the key-value pair

# Get command-line arguments
KEY=$1
VALUE=$2

# Check if KEY is set
if [ -z "$KEY" ]
then
  echo "No key specified. Provide the key after the command."
  exit 1
fi

# Check if VALUE is set
if [ -z "$VALUE" ]
then
  echo "No value specified. Provide the value after the key."
  exit 1
fi

# Write the key-value pair to the env.json file
echo "Writing key-value pair to env.json"
jq -S --arg contract $KEY --arg address $VALUE 'getpath($contract / ".") = $address' script/env.json > script/env.json.tmp
mv script/env.json.tmp script/env.json

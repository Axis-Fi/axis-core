#!/bin/bash

# Usage:
# ./write_salt.sh <bytecode file> <prefix> <salt key> <bytecode hash>

# Get command-line arguments
BYTECODE_FILE=$1 # Which bytecode to use
PREFIX=$2 # Which prefix to search for
SALT_KEY=$3 # What key to save the generated salt as
BYTECODE_HASH=$4 # Hash of the bytecode to the contract

# Check if BYTECODE_FILE is set
if [ -z "$BYTECODE_FILE" ]
then
  echo "No bytecode file specified. Provide the relative path after the command."
  exit 1
fi

# Check if BYTECODE_FILE exists
if [ ! -f "$BYTECODE_FILE" ]
then
  echo "Bytecode file ($BYTECODE_FILE) not found. Provide the correct relative path after the command."
  exit 1
fi

# Check if PREFIX is set
if [ -z "$PREFIX" ]
then
  echo "No prefix specified. Provide the prefix after the bytecode file."
  exit 1
fi

# Check if SALT_KEY is set
if [ -z "$SALT_KEY" ]
then
  echo "No salt key specified. Provide the salt key after the prefix."
  exit 1
fi

# Check if BYTECODE_HASH is set
if [ -z "$BYTECODE_HASH" ]
then
  echo "No args hash specified. Provide the args hash after the salt key."
  exit 1
fi

# Generate salt using cast create2
output=$(cast create2 -s $2 -i $(cat $1))

# Get the first salt (as cast will often return the same salt multiple times)
salt=$(echo "$output" | grep 'Salt: ' | head -n 1 | awk -F' ' '{print $2}')

# Create the salts file if it does not exist or is empty
salt_file="./script/salts/salts.json"
salt_tmp_file="./script/salts/salts.json.tmp"
if [ ! -f $salt_file ] || [ ! -s $salt_file ]; then
  echo "{}" > $salt_file
fi

# Set the salt in the salts file (and sort)
# jq will replace existing salts for the same key and args hash, or add new entries
# It will write in the format of:
# {
#   "<SALT_KEY>": {
#     "<BYTECODE_HASH>": "<SALT>"
#   }
# }
jq -S --arg contract "$SALT_KEY" --arg hash "$BYTECODE_HASH" --arg salt "$salt" '.[$contract] += { $hash: $salt }' $salt_file > $salt_tmp_file && mv $salt_tmp_file $salt_file
echo "Wrote salt for key $SALT_KEY to $salt_file"

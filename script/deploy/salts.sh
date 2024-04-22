#!/bin/bash

# Usage:
# ./salts.sh <bytecode file> <prefix>
# The only output of the script will be the salt

# Get command-line arguments
BYTECODE_FILE=$1
PREFIX=$2

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

# Generate salt using cast create2
output=$(cast create2 -s $2 -i $(cat $1))

# Get the first salt (as cast will often return the same salt multiple times)
salt=$(echo "$output" | grep 'Salt: ' | head -n 1 | awk -F' ' '{print $2}')

# Get the filename without extension
salt_key=$(basename "$BYTECODE_FILE" .bin)

# Create the salts file if it does not exist or is empty
salt_file="./script/salts.json"
if [ ! -f $salt_file ] || [ ! -s $salt_file ]; then
  echo "{}" > $salt_file
fi

# Set the salt in the salts file (and sort)
jq -S --arg key "$salt_key" --arg value "$salt" '.[$key]=$value' $salt_file > ./script/salts.json.tmp && mv ./script/salts.json.tmp $salt_file
echo "Wrote salt for key $salt_key to $salt_file"

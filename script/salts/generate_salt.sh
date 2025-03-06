#!/bin/bash

# Usage:
# ./generate_salt.sh --bytecode <bytecode file> --prefix <prefix> --bytecodeHash <bytecode hash> [--deployer <deployer>]

# Exit on error
set -e

# Iterate through named arguments
# Source: https://unix.stackexchange.com/a/388038
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    v="${1/--/}"
    declare $v="$2"
  fi

  shift
done

# Check if bytecodeFile is set
if [ -z "$bytecodeFile" ]
then
  echo "No bytecode file specified. Provide the relative path after the command."
  exit 1
fi

# Check if bytecodeFile exists
if [ ! -f "$bytecodeFile" ]
then
  echo "Bytecode file ($bytecodeFile) not found. Provide the correct relative path after the command."
  exit 1
fi

# Check if prefix is set
if [ -z "$prefix" ]
then
  echo "No prefix specified. Provide the prefix after the bytecode file."
  exit 1
fi

# Check if bytecodeHash is set
if [ -z "$bytecodeHash" ]
then
  echo "No args hash specified. Provide the args hash after the salt key."
  exit 1
fi

DEPLOYER_FLAG=""
if [ ! -z "$deployer" ]
then
  DEPLOYER_FLAG="--deployer $deployer"
fi

# Generate salt using cast create2
output=$(cast create2 --case-sensitive --starts-with $prefix --init-code $(cat $bytecodeFile) $DEPLOYER_FLAG)

# Get the first salt (as cast will often return the same salt multiple times)
salt=$(echo "$output" | grep 'Salt: ' | head -n 1 | awk -F' ' '{print $2}')

echo "$salt"

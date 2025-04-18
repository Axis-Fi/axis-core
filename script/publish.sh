#!/bin/bash

# Exit on error
set -e

# This script is used to release a new version of the package. It will:
#  - Validate that the working directory is clean
#  - Validate the version number argument
#  - Update the version number in the package.json file (which also commits and tags in git)
#  - Push a new version to soldeer

# Check if the working directory is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "Working directory not clean. Please commit all changes before releasing."
  exit 1
fi

# Check if the version number argument is provided
if [ -z "$1" ]; then
  echo "Please provide the version number as an argument."
  exit 1
fi

# Update the version number in the package.json file
npm version $1

# Push the new version to soldeer
forge soldeer push axis-core~v$1

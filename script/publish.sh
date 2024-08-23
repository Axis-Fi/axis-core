#!/bin/bash

# Only run this postinstall script if we're developing it.
# (Don't run if we're importing this package as an npm dependency
# inside a different repo)
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Skipping install script because this is not inside a Git work tree."
  exit 0
fi

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

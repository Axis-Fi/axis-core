#!/bin/bash

# Only run this postinstall script if we're developing it.
# (Don't run if we're importing this package as an npm dependency
# inside a different repo)
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "Skipping install script because this is not inside a Git work tree."
  exit 0
fi

# echo ""
# echo "*** Setting up submodules"
# git submodule init
# git submodule update
# echo "    Done"

echo ""
echo "*** Installing forge dependencies"
forge install
echo "    Done"

echo ""
echo "*** Installing soldeer dependencies"
rm -rf dependencies/* && forge soldeer update
echo "    Done"

# echo ""
# echo "*** Restoring submodule commits"
# echo "    Done"

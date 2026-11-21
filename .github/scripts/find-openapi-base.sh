#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Finds the OpenAPI document in the pull request's base, so the breaking check has something to
# compare against. Fails when the pull request's commit has no document at the path, since a wrong
# path would otherwise check nothing; passes with found=false when only the base lacks it, as when
# the pull request adds it. Runs from the repository's root, in a clone that holds the base commit,
# and writes found= to GITHUB_OUTPUT.
#
# Environment:
# - BASE_SHA: the pull request's base commit.
# - OPENAPI_PATH: the document's path from the repository's root.

set -euo pipefail

if [ ! -f "$OPENAPI_PATH" ]; then
  echo "::error::openapi_breakage_check_path names $OPENAPI_PATH, which this commit doesn't have"
  exit 1
fi

found=true
if ! git cat-file -e "$BASE_SHA:$OPENAPI_PATH" 2> /dev/null; then
  found=false
  echo "::notice::The base commit has no $OPENAPI_PATH, so there's nothing to compare it with yet"
fi
echo "found=$found" >> "$GITHUB_OUTPUT"

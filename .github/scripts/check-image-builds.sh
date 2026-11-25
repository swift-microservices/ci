#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Fails unless every architecture's image built and passed its checks. The job that runs it runs
# whatever the builds' result, since a skipped job would pass a required check.
#
# Environment:
# - BUILD_RESULT: the build matrix's result.

set -euo pipefail

if [ "$BUILD_RESULT" != success ]; then
  echo "::error::An architecture's image failed to build or pass its checks (result: $BUILD_RESULT)"
  exit 1
fi
echo "Every architecture's image built and passed its checks"

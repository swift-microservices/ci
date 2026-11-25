#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Sets the variables prepare-tests.sh wrote for the tests' steps.
#
# Environment:
# - ENVIRONMENT: the variables, in GITHUB_ENV's format; empty sets none.
# - GITHUB_ENV: set by GitHub Actions.

set -euo pipefail

if [ -n "$ENVIRONMENT" ]; then
  printf '%s\n' "$ENVIRONMENT" >> "$GITHUB_ENV"
fi

#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Fails when a job a pipeline ran failed or was cancelled; a skipped job passes. The job that runs
# it runs whatever the others' results, so a ruleset requires this one check whatever the matrix.
#
# Environment:
# - RESULTS: the jobs' results, toJSON(needs).

set -euo pipefail

jq -r 'to_entries[] | "\(.key): \(.value.result)"' <<<"$RESULTS"
failed=$(jq -r '[to_entries[] | select(.value.result == "failure" or .value.result == "cancelled") | .key] | join(", ")' \
  <<<"$RESULTS")
if [ -n "$failed" ]; then
  echo "::error::Not every job passed: $failed"
  exit 1
fi

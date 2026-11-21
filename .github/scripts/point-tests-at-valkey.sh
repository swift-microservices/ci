#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Points the tests at the Valkey service tests.yml starts, through GITHUB_ENV.

set -euo pipefail

{
  echo 'VALKEY_HOST=valkey'
  echo 'VALKEY_PORT=6379'
} >> "$GITHUB_ENV"

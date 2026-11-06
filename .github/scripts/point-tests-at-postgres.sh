#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Points the tests at the Postgres service tests.yml starts, through GITHUB_ENV.

set -euo pipefail

{
  echo 'POSTGRES_HOST=postgres'
  echo 'POSTGRES_PORT=5432'
  echo 'POSTGRES_USER=postgres'
  echo 'POSTGRES_PASSWORD=postgres'
  echo 'POSTGRES_DB=postgres'
} >> "$GITHUB_ENV"

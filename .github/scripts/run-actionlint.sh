#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Installs a checksum-verified actionlint and checks every workflow, and the shell in their run: steps.
# Runs from this repository's root.

set -euo pipefail

actionlint_version=1.7.12
actionlint_sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
archive="$RUNNER_TEMP/actionlint.tar.gz"

curl --fail --silent --show-error --location \
  "https://github.com/rhysd/actionlint/releases/download/v${actionlint_version}/actionlint_${actionlint_version}_linux_amd64.tar.gz" \
  --output "$archive"
echo "$actionlint_sha256  $archive" | sha256sum --check
tar -xzf "$archive" -C "$RUNNER_TEMP" actionlint

# actionlint 1.7.12 doesn't know the $/ self-reference the pipelines use to call this repository's
# workflows and scripts action at their own commit.
"$RUNNER_TEMP/actionlint" -color \
  -ignore 'reusable workflow call "\$/' \
  -ignore 'specifying action "\$/'

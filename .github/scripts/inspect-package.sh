#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Reads what a pipeline would otherwise take as inputs, so they can't drift from the package: its
# toolchain, the major.minor of Package.swift's swift-tools-version, and whether it declares
# buf.yaml at its root, which turns on the Protobuf check. Runs from the package's root and writes
# swift_version= and buf_config= to GITHUB_OUTPUT.

set -euo pipefail

swift_version=$(sed -nE '1s|^// *swift-tools-version: *([0-9]+\.[0-9]+).*|\1|p' Package.swift)
if [ -z "$swift_version" ]; then
  echo '::error::Package.swift must start with a swift-tools-version comment, such as // swift-tools-version: 6.3'
  exit 1
fi

buf_config=false
if [ -f buf.yaml ]; then
  buf_config=true
fi

echo "Swift $swift_version; buf.yaml: $buf_config"
{
  echo "swift_version=$swift_version"
  echo "buf_config=$buf_config"
} >> "$GITHUB_OUTPUT"

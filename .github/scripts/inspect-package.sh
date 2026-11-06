#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Reads what a pipeline would otherwise take as inputs, so they can't drift from the package:
# its toolchain, the major.minor of Package.swift's swift-tools-version, and whether it has private
# dependencies, which a passed PACKAGES_TOKEN means. Runs from the package's root and writes
# swift_version= and private_dependencies= to GITHUB_OUTPUT.
#
# Environment:
# - PACKAGES_TOKEN: the token the caller passed; empty without private dependencies.

set -euo pipefail

swift_version=$(sed -nE '1s|^// *swift-tools-version: *([0-9]+\.[0-9]+).*|\1|p' Package.swift)
if [ -z "$swift_version" ]; then
  echo '::error::Package.swift must start with a swift-tools-version comment, such as // swift-tools-version: 6.3'
  exit 1
fi

private_dependencies=false
if [ -n "${PACKAGES_TOKEN:-}" ]; then
  private_dependencies=true
fi

echo "Swift $swift_version; private dependencies: $private_dependencies"
{
  echo "swift_version=$swift_version"
  echo "private_dependencies=$private_dependencies"
} >> "$GITHUB_OUTPUT"

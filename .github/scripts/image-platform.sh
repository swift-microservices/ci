#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Writes the image platform of a host architecture as the step's `platform` output, refusing any
# name tests.yml doesn't also take.
#
# Environment:
# - HOST_ARCH: x86_64 or aarch64, from linux_host_archs.
# - GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

case "$HOST_ARCH" in
  aarch64) platform=linux/arm64 ;;
  x86_64) platform=linux/amd64 ;;
  *) echo "::error::linux_host_archs takes x86_64 or aarch64, not '$HOST_ARCH'"; exit 1 ;;
esac
echo "platform=$platform" >> "$GITHUB_OUTPUT"
echo "$HOST_ARCH builds $platform"

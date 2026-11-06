#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Gives SwiftPM the token that reads the private repositories a package depends on.
#
# Environment:
# - PACKAGES_TOKEN: the token; empty when the package has only public dependencies.

set -euo pipefail

if [ -z "$PACKAGES_TOKEN" ]; then
  echo 'No PACKAGES_TOKEN: the package has only public dependencies'
  exit 0
fi
printf 'machine github.com login x-access-token password %s\n' "$PACKAGES_TOKEN" > "$HOME/.netrc"
chmod 600 "$HOME/.netrc"

#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Writes the container package to clean up and its owner as the step's `package_name` and `owner`
# outputs: the package_name input, or, when it's empty, the repository's name, the package
# image_repository's default publishes to, and the repository's owner, both lowercased as GHCR names
# them. A given name with a capital fails, since no package on GHCR has one.
#
# Environment:
# - PACKAGE_NAME: the package_name input, empty for the default.
# - GITHUB_REPOSITORY, GITHUB_REPOSITORY_OWNER, GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

repository_name="${GITHUB_REPOSITORY#*/}"
package="${PACKAGE_NAME:-${repository_name,,}}"
if [ "$package" != "${package,,}" ]; then
  echo "::error::package_name must be lowercase, as a container package's name is: use '${package,,}', or leave it empty for ${repository_name,,}"
  exit 1
fi
owner="${GITHUB_REPOSITORY_OWNER,,}"
echo "package_name=$package" >> "$GITHUB_OUTPUT"
echo "owner=$owner" >> "$GITHUB_OUTPUT"
echo "Cleaning up ghcr.io/$owner/$package"

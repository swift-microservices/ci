#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Writes the image repository as the step's `image_repository` output: the image_repository input,
# or, when it's empty, ghcr.io/<owner>/<repository> lowercased, so the package's name is the
# repository's. An image reference is lowercase while a GitHub owner or repository may not be, so a
# given name with a capital fails here, before anything is built, rather than at the push.
#
# Environment:
# - IMAGE_REPOSITORY: the image_repository input, empty for the default.
# - GITHUB_REPOSITORY, GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

repository="${IMAGE_REPOSITORY:-ghcr.io/${GITHUB_REPOSITORY,,}}"
if [ "$repository" != "${repository,,}" ]; then
  echo "::error::image_repository must be lowercase, as an image reference is: use '${repository,,}', or leave it empty for ghcr.io/${GITHUB_REPOSITORY,,}"
  exit 1
fi
echo "image_repository=$repository" >> "$GITHUB_OUTPUT"
echo "The image is $repository"

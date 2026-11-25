#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Writes whether this commit's image is already published as the step's `published` output,
# true or false, so a re-run never replaces the image staging ran.
#
# Environment:
# - IMAGE_REPOSITORY: where the image is published.
# - GITHUB_SHA, GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

commit_tag="$IMAGE_REPOSITORY:$GITHUB_SHA"
if docker buildx imagetools inspect "$commit_tag" > /dev/null 2>&1; then
  echo "published=true" >> "$GITHUB_OUTPUT"
  echo "$commit_tag is already published"
else
  echo "published=false" >> "$GITHUB_OUTPUT"
fi

#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Writes the image the checks run on as the step's `image` output: the local build on a pull
# request, or, when publishing, the pushed image by digest, pulled so the checks see exactly what
# the commit's tag will name.
#
# Environment:
# - PUBLISH: true when the build pushed the image by digest.
# - LOCAL_IMAGE: the locally loaded image of a build that didn't push.
# - IMAGE_REPOSITORY: where a pushed image is.
# - DIGEST: the pushed image's digest, sha256:<hex>.
# - GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

if [ "$PUBLISH" != true ]; then
  echo "image=$LOCAL_IMAGE" >> "$GITHUB_OUTPUT"
  exit 0
fi
case "$DIGEST" in
  sha256:*) ;;
  *) echo "::error::The push returned no digest ('$DIGEST')"; exit 1 ;;
esac
image="$IMAGE_REPOSITORY@$DIGEST"
docker pull --quiet "$image"
echo "image=$image" >> "$GITHUB_OUTPUT"
echo "Checking $image"

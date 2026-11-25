#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Records an architecture's pushed and checked image as an empty file named for its digest, which
# the image job collects from every architecture to publish the commit's tag.
#
# Environment:
# - DIGEST: the pushed image's digest, sha256:<hex>.
# - DIGESTS_DIRECTORY: where the file is written.

set -euo pipefail

case "$DIGEST" in
  sha256:*) ;;
  *) echo "::error::The push returned no digest ('$DIGEST')"; exit 1 ;;
esac
mkdir -p "$DIGESTS_DIRECTORY"
touch "$DIGESTS_DIRECTORY/${DIGEST#sha256:}"
echo "Pushed $DIGEST"

#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Writes where an image lives: `image_repository`, the repository without a tag or digest,
# `registry`, its registry's host, and `digest`, when the reference names one, to GITHUB_OUTPUT.
# An empty reference is ghcr.io/<owner>/<repository>, lowercased, so the package has the
# repository's name. An image reference is lowercase while a GitHub owner or repository may not be,
# so a given one with a capital fails here, before anything is built. GITHUB_TOKEN logs in to
# ghcr.io only, so logging in anywhere else needs the registry's own credentials.
#
# Environment:
# - IMAGE_REPOSITORY: an image repository, or an image reference with a tag or digest; empty for
#   the default.
# - LOGIN: true when the job logs in to the registry.
# - REGISTRY_CREDENTIALS: true when the caller passed REGISTRY_USERNAME and REGISTRY_PASSWORD.
# - GITHUB_REPOSITORY, GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

reference="${IMAGE_REPOSITORY:-ghcr.io/${GITHUB_REPOSITORY,,}}"
repository=${reference%@*}
digest=""
if [ "$repository" != "$reference" ]; then
  digest=${reference##*@}
fi
# A tag follows the last colon after the last slash; a colon before it is a registry's port.
last_component=${repository##*/}
if [[ $last_component == *:* ]]; then
  repository=${repository%:*}
fi
if [ "$repository" != "${repository,,}" ]; then
  echo "::error::An image repository is lowercase: use '${repository,,}', or leave it empty for ghcr.io/${GITHUB_REPOSITORY,,}"
  exit 1
fi

# A first component that names a host is the registry; anything else is on Docker Hub.
first_component=${repository%%/*}
registry=docker.io
if [ "$first_component" != "$repository" ] && [[ $first_component == *.* || $first_component == *:* || $first_component == localhost ]]; then
  registry=$first_component
fi
if [ "${LOGIN:-false}" = true ] && [ "$registry" != ghcr.io ] && [ "${REGISTRY_CREDENTIALS:-false}" != true ]; then
  echo "::error::Logging in to $registry needs the REGISTRY_USERNAME and REGISTRY_PASSWORD secrets; GITHUB_TOKEN logs in to ghcr.io only"
  exit 1
fi

{
  echo "image_repository=$repository"
  echo "registry=$registry"
  echo "digest=$digest"
} >> "$GITHUB_OUTPUT"
echo "The image repository is $repository on $registry"

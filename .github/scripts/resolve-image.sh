#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Resolves a commit to its image by digest, refusing production for a commit staging never ran.
# Writes commit= and image= to GITHUB_OUTPUT.
#
# Environment:
# - GH_TOKEN: reads the repository's commits and runs.
# - COMMIT: the commit to deploy.
# - TARGET_ENVIRONMENT: staging or production.
# - IMAGE_REPOSITORY: where build-image.yml published the image.

set -euo pipefail

case "$TARGET_ENVIRONMENT" in
  staging|production) ;;
  *) echo "::error::Unknown environment '$TARGET_ENVIRONMENT'"; exit 1 ;;
esac
sha=$(gh api "repos/$GITHUB_REPOSITORY/commits/$COMMIT" --jq .sha)

# Production runs only a commit whose push to main deployed it to staging.
if [ "$TARGET_ENVIRONMENT" = production ]; then
  staged=false
  running=false
  while read -r run status; do
    if [ "$status" != completed ]; then
      running=true
    fi
    if [ -n "$(gh api --paginate "repos/$GITHUB_REPOSITORY/actions/runs/$run/jobs" \
      --jq '.jobs[] | select((.name | endswith("Deploy staging")) and .conclusion == "success") | .id')" ]; then
      staged=true
    fi
  done < <(gh api "repos/$GITHUB_REPOSITORY/actions/runs?head_sha=$sha&event=push" \
    --jq '.workflow_runs[] | "\(.id) \(.status)"')
  if [ "$staged" != true ] && [ "$running" = true ]; then
    echo "::error::${sha::7} is still on its way to staging; deploy it once that run finishes"
    exit 1
  fi
  if [ "$staged" != true ]; then
    echo "::error::${sha::7} has no successful staging deployment"
    exit 1
  fi
fi

# The commit tag names the image in Dokploy; the digest pins what Docker pulls.
if ! manifest=$(docker buildx imagetools inspect "$IMAGE_REPOSITORY:$sha" --format '{{json .Manifest}}'); then
  echo "::error::$IMAGE_REPOSITORY has no image for ${sha::7}"
  exit 1
fi
digest=$(jq -r .digest <<<"$manifest")
case "$digest" in sha256:*) ;; *) exit 1 ;; esac
echo "commit=$sha" >> "$GITHUB_OUTPUT"
echo "image=$IMAGE_REPOSITORY:$sha@$digest" >> "$GITHUB_OUTPUT"
echo "Deploying ${sha::7} ($IMAGE_REPOSITORY@$digest) to $TARGET_ENVIRONMENT"

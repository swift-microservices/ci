#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Chooses the image a deployment runs and records the deployment on GitHub, in progress. The image
# is the one given, or, with PROMOTE_FROM, the one that environment's newest successful deployment
# of the commit ran, so an environment runs only what another one ran. Each deployment keeps its
# image, so promoting and rolling back redeploy an image without reading the registry. Writes
# commit=, image= and deployment_id= to GITHUB_OUTPUT.
#
# Environment:
# - GH_TOKEN: reads commits and deployments, and writes deployments.
# - TARGET_ENVIRONMENT: the environment deployed to.
# - IMAGE: the image to deploy, by digest; empty with PROMOTE_FROM.
# - PROMOTE_FROM: the environment whose deployment to repeat; empty with IMAGE.
# - COMMIT: the commit deployed; empty means the run's, or, with PROMOTE_FROM, the newest that
#   environment ran.
# - ENVIRONMENT_URL: where the environment serves, for the deployment's record; may be empty.
# - RUN_URL: this run, for the deployment's record.
# - GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

if [ -n "$IMAGE" ] && [ -n "$PROMOTE_FROM" ]; then
  echo '::error::Pass image or promote_from, not both'
  exit 1
fi
if [ -z "$IMAGE" ] && [ -z "$PROMOTE_FROM" ]; then
  echo '::error::Pass image, the image to deploy, or promote_from, the environment whose image to deploy'
  exit 1
fi

sha=""
if [ -n "$COMMIT" ]; then
  sha=$(gh api "repos/$GITHUB_REPOSITORY/commits/$COMMIT" --jq .sha)
fi

if [ -n "$PROMOTE_FROM" ]; then
  # A deployment GitHub marked inactive succeeded and was superseded later.
  pending=false
  query=(--method GET "repos/$GITHUB_REPOSITORY/deployments" -f environment="$PROMOTE_FROM" -f per_page=100)
  if [ -n "$sha" ]; then
    query+=(-f sha="$sha")
  fi
  while read -r id deployment_sha deployment_image; do
    state=$(gh api "repos/$GITHUB_REPOSITORY/deployments/$id/statuses?per_page=1" --jq '.[0].state // ""')
    case "$state" in
      success|inactive)
        sha=$deployment_sha
        IMAGE=$deployment_image
        break
        ;;
      queued|pending|in_progress) pending=true ;;
    esac
  done < <(gh api "${query[@]}" \
    --jq '.[] | select((.payload | type) == "object" and (.payload.image // "") != "") | "\(.id) \(.sha) \(.payload.image)"')
  if [ -z "$IMAGE" ] && [ -n "$sha" ] && [ "$pending" = true ]; then
    echo "::error::${sha::7} is still deploying to $PROMOTE_FROM; promote it once that finishes"
    exit 1
  fi
  if [ -z "$IMAGE" ] && [ -n "$sha" ]; then
    echo "::error::${sha::7} has no successful deployment to $PROMOTE_FROM"
    exit 1
  fi
  if [ -z "$IMAGE" ]; then
    echo "::error::$PROMOTE_FROM has no successful deployment to promote"
    exit 1
  fi
  echo "Promoting ${sha::7} from $PROMOTE_FROM"
fi

sha=${sha:-$GITHUB_SHA}
# A platform pulls by digest, so the image deployed is the image checked, whatever its tag says.
if [[ $IMAGE != *@sha256:* ]]; then
  echo "::error::The image must name its digest, as <repository>[:<tag>]@sha256:<hex>, not '$IMAGE'"
  exit 1
fi

# The deployment checks nothing of its own: the pipeline that built the image held the commit to
# its checks, so no commit status is required.
deployment_id=$(jq -n --arg ref "$sha" --arg environment "$TARGET_ENVIRONMENT" --arg image "$IMAGE" \
  --arg description "${sha::7}" \
  '{ref: $ref, environment: $environment, payload: {image: $image}, description: $description,
    auto_merge: false, required_contexts: []}' \
  | gh api "repos/$GITHUB_REPOSITORY/deployments" --input - --jq .id)
gh api "repos/$GITHUB_REPOSITORY/deployments/$deployment_id/statuses" --silent \
  -f state=in_progress -f log_url="$RUN_URL" -f environment_url="$ENVIRONMENT_URL" \
  -f description="Deploying ${sha::7}"

{
  echo "commit=$sha"
  echo "image=$IMAGE"
  echo "deployment_id=$deployment_id"
} >> "$GITHUB_OUTPUT"
echo "Deploying ${sha::7} ($IMAGE) to $TARGET_ENVIRONMENT"

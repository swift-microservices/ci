#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Records how a deployment start-deployment.sh began ended: success, which GitHub shows as the
# environment's active deployment, failure, or error when the run was cancelled.
#
# Environment:
# - GH_TOKEN: writes deployments.
# - DEPLOYMENT_ID: the deployment start-deployment.sh recorded.
# - JOB_STATUS: the job's status, success, failure or cancelled.
# - COMMIT: the commit deployed.
# - ENVIRONMENT_URL: where the environment serves; may be empty.
# - RUN_URL: this run.
# - GITHUB_REPOSITORY: set by GitHub Actions.

set -euo pipefail

case "$JOB_STATUS" in
  success) state=success description="Deployed ${COMMIT::7}" ;;
  failure) state=failure description="Failed to deploy ${COMMIT::7}" ;;
  *) state=error description="Stopped deploying ${COMMIT::7}" ;;
esac
gh api "repos/$GITHUB_REPOSITORY/deployments/$DEPLOYMENT_ID/statuses" --silent \
  -f state="$state" -f log_url="$RUN_URL" -f environment_url="$ENVIRONMENT_URL" \
  -f description="$description"
echo "$description"

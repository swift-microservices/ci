#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Deploys an image to each Dokploy application in order and waits for each to finish.
#
# Environment:
# - DOKPLOY_URL, DOKPLOY_TOKEN: the Dokploy instance and an API key that can read, update and deploy.
# - APPLICATION_IDS: the applications, in deploy order (JSON list).
# - IMAGE: the image by tag and digest.
# - COMMIT: the deployed commit.
# - RUN_URL: this run, for the deployment's description.

set -euo pipefail

api="${DOKPLOY_URL%/}/api"
# Calls one procedure of Dokploy's API; a body makes it a POST.
dokploy() {
  local procedure=$1 body=${2:-}
  if [ -n "$body" ]; then
    curl --fail-with-body --silent --show-error --connect-timeout 15 --max-time 120 \
      --header "x-api-key: $DOKPLOY_TOKEN" --header 'Content-Type: application/json' \
      --data "$body" "$api/$procedure"
  else
    curl --fail-with-body --silent --show-error --connect-timeout 15 --max-time 30 \
      --retry 3 --retry-all-errors --header "x-api-key: $DOKPLOY_TOKEN" "$api/$procedure"
  fi
}
newest_deployment() {
  dokploy "deployment.allByType?id=$1&type=application" | jq -c '.[0] // {}'
}

# Every ID must name an application before any of them changes.
if ! jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' \
  <<<"$APPLICATION_IDS" > /dev/null 2>&1; then
  echo '::error::application_ids must be a non-empty JSON list of application IDs'
  exit 1
fi
ids=()
while read -r id; do
  ids+=("$id")
done < <(jq -r '.[]' <<<"$APPLICATION_IDS")
names=()
for id in "${ids[@]}"; do
  name=$(dokploy "application.one?applicationId=$id" 2>/dev/null | jq -r '.name // empty' 2>/dev/null) || true
  if [ -z "$name" ]; then
    echo "::error::Dokploy has no application $id that this token can read"
    exit 1
  fi
  names+=("$name")
done

# One application at a time; a failure leaves the rest on their current image.
for i in "${!ids[@]}"; do
  id=${ids[i]}
  name=${names[i]}
  echo "::group::$name"
  previous=$(newest_deployment "$id" | jq -r '.deploymentId // ""')

  result=$(dokploy application.update "$(jq -nc --arg id "$id" --arg image "$IMAGE" \
    '{applicationId: $id, dockerImage: $image}')") || result="${result:-request failed}"
  if [ "$result" != true ]; then
    echo "::error::Dokploy did not set the image of $name: $result"
    exit 1
  fi

  # Dokploy queues each application's deployments, so asking twice is harmless.
  request=$(jq -nc --arg id "$id" --arg title "${COMMIT::7}" --arg description "$COMMIT $RUN_URL" \
    '{applicationId: $id, title: $title, description: $description}')
  for attempt in 1 2 3 4 5; do
    code=$(curl --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 15 --max-time 120 \
      --header "x-api-key: $DOKPLOY_TOKEN" --header 'Content-Type: application/json' \
      --data "$request" "$api/application.deploy") || code="no response"
    case "$code" in
      200) break ;;
      429|5??|"no response") ;;
      *) echo "::error::Dokploy refused to deploy $name (HTTP $code)"; exit 1 ;;
    esac
    if [ "$attempt" -eq 5 ]; then
      echo "::error::Dokploy did not accept the deployment of $name after 5 attempts ($code)"
      exit 1
    fi
    echo "Attempt $attempt to deploy $name got $code; retrying"
    sleep $((attempt * 15))
  done

  # Wait for a deployment newer than the one before the request to finish.
  deadline=$((SECONDS + 900))
  status=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    sleep 5
    deployment=$(newest_deployment "$id" 2>/dev/null) || continue
    if [ "$(jq -r '.deploymentId // ""' <<<"$deployment")" = "$previous" ]; then
      continue
    fi
    status=$(jq -r '.status // ""' <<<"$deployment")
    case "$status" in
      "done") break ;;
      error|cancelled)
        echo "::error::Dokploy's deployment of $name ended $status; its log is in Dokploy"
        exit 1
        ;;
    esac
  done
  if [ "$status" != "done" ]; then
    echo "::error::Dokploy's deployment of $name did not finish within 15 minutes"
    exit 1
  fi
  echo "$name runs $IMAGE"
  echo "::endgroup::"
done

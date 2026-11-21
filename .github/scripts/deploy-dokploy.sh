#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Deploys an image to each Dokploy application in order and waits for each to finish and for a
# container of the image to run, healthy when it has a health check, before the next. An application
# that runs to completion, such as a migration, instead waits for its new container of the image to
# exit, and only exit code 0 moves on.
#
# Environment:
# - DOKPLOY_URL, DOKPLOY_TOKEN: the Dokploy instance and an API key that can read, update and deploy.
# - APPLICATION_IDS: the applications, in deploy order (JSON list).
# - RUN_TO_COMPLETION_APPLICATION_IDS: those of them whose command exits (JSON list).
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
if ! jq -e --argjson all "$APPLICATION_IDS" \
  'type == "array" and all(.[]; type == "string" and IN($all[]))' \
  <<<"$RUN_TO_COMPLETION_APPLICATION_IDS" > /dev/null 2>&1; then
  echo '::error::run_to_completion_application_ids must be a JSON list of IDs that application_ids lists'
  exit 1
fi
ids=()
while read -r id; do
  ids+=("$id")
done < <(jq -r '.[]' <<<"$APPLICATION_IDS")
names=()
app_names=()
server_ids=()
completes=()
for id in "${ids[@]}"; do
  application=$(dokploy "application.one?applicationId=$id" 2>/dev/null) || application='{}'
  name=$(jq -r '.name // empty' <<<"$application" 2>/dev/null) || true
  app_name=$(jq -r '.appName // empty' <<<"$application" 2>/dev/null) || true
  if [ -z "$name" ] || [ -z "$app_name" ]; then
    echo "::error::Dokploy has no application $id that this token can read"
    exit 1
  fi
  names+=("$name")
  app_names+=("$app_name")
  server_ids+=("$(jq -r '.serverId // empty' <<<"$application")")
  completes+=("$(jq -r --arg id "$id" 'any(.[]; . == $id)' <<<"$RUN_TO_COMPLETION_APPLICATION_IDS")")
done

digest=${IMAGE##*@}
# Prints the best state of the application's containers that run the deployed image: healthy, or
# running for one without a health check, else what Docker reports, or nothing when none runs yet.
container_state() {
  local app_name=$1 server_id=$2 containers container_id config state best=""
  containers=$(dokploy "docker.getContainersByAppNameMatch?appName=$app_name${server_id:+&serverId=$server_id}") || return 0
  while read -r container_id; do
    config=$(dokploy "docker.getConfig?containerId=$container_id${server_id:+&serverId=$server_id}") || continue
    state=$(jq -r --arg digest "$digest" \
      'select((.Config.Image // "") | endswith("@" + $digest))
        | if .State.Running then (.State.Health.Status // "running") else (.State.Status // "stopped") end' \
      <<<"$config")
    case "$state" in
      healthy|running) echo "$state"; return 0 ;;
      "") ;;
      *) best=$state ;;
    esac
  done < <(jq -r '.[]? | select(.state == "running") | .containerId' <<<"$containers")
  echo "$best"
}

# Prints the IDs of the application's containers in any state, so a wait can skip those that ran
# before the deployment, which may include one of the same image.
container_ids() {
  local app_name=$1 server_id=$2 containers
  containers=$(dokploy "docker.getContainersByAppNameMatch?appName=$app_name${server_id:+&serverId=$server_id}") || return 1
  jq -r '.[]?.containerId' <<<"$containers"
}

# Prints the state of the newest container of the deployed image that $3 doesn't list:
# "exited <code>" once it has exited, else what Docker reports, or nothing when none exists yet.
completion_state() {
  local app_name=$1 server_id=$2 earlier=$3 containers container_id config entry newest=""
  containers=$(dokploy "docker.getContainersByAppNameMatch?appName=$app_name${server_id:+&serverId=$server_id}") || return 0
  while read -r container_id; do
    if grep -qxF -e "$container_id" <<<"$earlier"; then
      continue
    fi
    config=$(dokploy "docker.getConfig?containerId=$container_id${server_id:+&serverId=$server_id}") || continue
    # Created is RFC 3339 with up to nine fractional digits; padding them makes it sort as text.
    entry=$(jq -r --arg digest "$digest" \
      'select((.Config.Image // "") | endswith("@" + $digest))
        | (.Created | capture("^(?<s>[0-9T:-]+)(\\.(?<f>[0-9]+))?")
            | .s + "." + ((.f // "") + "000000000")[:9]) as $created
        | (.State.Status // "unknown") as $status
        | "\($created) \(if $status == "exited" then "exited \(.State.ExitCode)" else $status end)"' \
      <<<"$config" 2>/dev/null) || continue
    if [ -n "$entry" ] && { [ -z "$newest" ] || [[ "$entry" > "$newest" ]]; }; then
      newest=$entry
    fi
  done < <(jq -r '.[]?.containerId' <<<"$containers")
  echo "${newest#* }"
}

# One application at a time; a failure leaves the rest on their current image.
for i in "${!ids[@]}"; do
  id=${ids[i]}
  name=${names[i]}
  echo "::group::$name"
  previous=$(newest_deployment "$id" | jq -r '.deploymentId // ""')
  if [ "${completes[i]}" = true ]; then
    if ! earlier=$(container_ids "${app_names[i]}" "${server_ids[i]}"); then
      echo "::error::Dokploy did not list the containers of $name"
      exit 1
    fi
  fi

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

  # A finished deployment has only handed the image to Docker. An application that runs to
  # completion holds the next one back until its new container of the image exits, and fails the
  # run unless it exits 0, so migrations are applied before anything that needs them starts.
  if [ "${completes[i]}" = true ]; then
    deadline=$((SECONDS + 600))
    state=""
    while [ "$SECONDS" -lt "$deadline" ]; do
      state=$(completion_state "${app_names[i]}" "${server_ids[i]}" "$earlier")
      case "$state" in
        exited*|dead) break ;;
      esac
      sleep 5
    done
    case "$state" in
      "exited 0") echo "$name ran $IMAGE to completion" ;;
      exited*)
        echo "::error::$name's container of the image exited with code ${state#exited }; its log is in Dokploy"
        exit 1
        ;;
      dead)
        echo "::error::$name's container of the image is dead; Docker could not stop or remove it"
        exit 1
        ;;
      *)
        echo "::error::No container of $name ran the image to completion within 10 minutes (last state: ${state:-none})"
        exit 1
        ;;
    esac
    echo "::endgroup::"
    continue
  fi

  # Any other application waits until a container of this image runs, and passes its health check
  # when it has one, so an application listed earlier is serving before the rest start.
  deadline=$((SECONDS + 600))
  state=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    state=$(container_state "${app_names[i]}" "${server_ids[i]}")
    case "$state" in
      healthy|running) break ;;
    esac
    sleep 5
  done
  case "$state" in
    healthy|running) echo "$name is $state" ;;
    *)
      echo "::error::No container of $name ran the image healthy within 10 minutes (last state: ${state:-none})"
      exit 1
      ;;
  esac
  echo "$name runs $IMAGE"
  echo "::endgroup::"
done

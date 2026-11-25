#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Turns swiftlang's toolchain matrix into the tests' matrix and environment. Writes `include`, a
# JSON list of {name, runner, image, flags}, one per Linux toolchain, and `environment`, the
# variables the tests read, in GITHUB_ENV's format, to GITHUB_OUTPUT.
#
# Environment:
# - MATRIX_YAML: toolchain_matrix.yml's matrix_yaml output, generated with linux_use_docker.
# - SWIFT_FLAGS, SWIFT_NIGHTLY_FLAGS: appended to the command on a release or nightly toolchain.
# - LINUX_ENV_VARS: the tests' own variables (JSON object).
# - POSTGRES_IMAGE, VALKEY_IMAGE: non-empty when that service runs beside the tests.
# - GITHUB_OUTPUT: set by GitHub Actions.

set -euo pipefail

include=$(yq -o=json -I=0 '[.config[] | select(.platform == "Linux") | {
    "name": .name,
    "runner": .runner,
    "image": (.swift_build.container.image // ""),
    "nightly": ((.swift_build.swift_version // "") | test("^nightly"))
  }]' <<<"$MATRIX_YAML")
include=$(jq -c --arg release "$SWIFT_FLAGS" --arg nightly "$SWIFT_NIGHTLY_FLAGS" \
  'map({name, runner, image, flags: (if .nightly then $nightly else $release end)})' <<<"$include")
if [ "$(jq length <<<"$include")" -eq 0 ]; then
  echo "::error::No Linux toolchain is left to test on: linux_swift_versions names none at or above the package's swift-tools-version"
  exit 1
fi
if jq -e 'any(.[]; .image == "")' <<<"$include" > /dev/null; then
  echo '::error::The toolchain matrix has a Linux entry without a container image'
  exit 1
fi
jq -r '.[] | "\(.name): \(.image) on \(.runner | join(","))"' <<<"$include"

if ! jq -e 'type == "object"' <<<"$LINUX_ENV_VARS" > /dev/null 2>&1; then
  echo "::error::linux_env_vars must be a JSON object, such as '{\"LOG_LEVEL\": \"debug\"}'"
  exit 1
fi
variables=$(jq -c 'with_entries(.value |= tostring)' <<<"$LINUX_ENV_VARS")
if [ -n "$POSTGRES_IMAGE" ]; then
  variables=$(jq -c '. + {POSTGRES_HOST: "postgres", POSTGRES_PORT: "5432", POSTGRES_USER: "postgres",
    POSTGRES_PASSWORD: "postgres", POSTGRES_DB: "postgres"}' <<<"$variables")
fi
if [ -n "$VALKEY_IMAGE" ]; then
  variables=$(jq -c '. + {VALKEY_HOST: "valkey", VALKEY_PORT: "6379"}' <<<"$variables")
fi

environment=""
delimiter="EOF_$(openssl rand -hex 16)"
while IFS= read -r name; do
  if ! [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "::error::linux_env_vars has '$name', which isn't a variable name"
    exit 1
  fi
  value=$(jq -r --arg name "$name" '.[$name]' <<<"$variables")
  environment+="$name<<$delimiter"$'\n'"$value"$'\n'"$delimiter"$'\n'
  echo "The tests read $name"
done < <(jq -r 'keys[]' <<<"$variables")

output_delimiter="EOF_$(openssl rand -hex 16)"
{
  echo "include=$include"
  echo "environment<<$output_delimiter"
  printf '%s' "$environment"
  echo "$output_delimiter"
} >> "$GITHUB_OUTPUT"

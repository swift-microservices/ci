#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Fails when the image runs as root, or when the executable it starts misses a runtime library.
# The executable is the first word of the image's entrypoint, or of its command when it has no
# entrypoint, found from its working directory or its PATH. A static executable links nothing to
# miss. An image without ldd, such as a distroless one, or whose entrypoint isn't an executable,
# such as a script, has its libraries left unchecked, with a warning.
#
# Environment:
# - CI_IMAGE: the image built for this commit.

set -euo pipefail

config=$(docker image inspect --format '{{json .Config}}' "$CI_IMAGE")
user=$(jq -r '.User // ""' <<<"$config")
case "$user" in
  ""|root|root:*|0|0:*) echo '::error::The image must run as an unprivileged user (USER)'; exit 1 ;;
esac
echo "The image runs as $user"

entry=$(jq -r '((.Entrypoint // []) + (.Cmd // []))[0] // ""' <<<"$config")
if [ -z "$entry" ]; then
  echo '::error::The image has no entrypoint or command to check'
  exit 1
fi

container=$(docker create "$CI_IMAGE")
copy=$(mktemp -d)
trap 'docker rm --force "$container" > /dev/null; rm -rf "$copy"' EXIT
# Copies a file out of the image, following links, and fails quietly when it isn't there.
copy_out() {
  docker cp --follow-link "$container:$1" "$copy/executable" > /dev/null 2>&1
}

path=""
case "$entry" in
  /*) copy_out "$entry" && path=$entry ;;
  */*)
    working_directory=$(jq -r '.WorkingDir // ""' <<<"$config")
    candidate="${working_directory%/}/${entry#./}"
    copy_out "$candidate" && path=$candidate
    ;;
  *)
    search_path=$(jq -r '[(.Env // [])[] | select(startswith("PATH=")) | ltrimstr("PATH=")][0]
      // "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' <<<"$config")
    IFS=: read -r -a directories <<<"$search_path"
    for directory in "${directories[@]}"; do
      if copy_out "${directory%/}/$entry"; then
        path="${directory%/}/$entry"
        break
      fi
    done
    ;;
esac
if [ -z "$path" ]; then
  echo "::error::The image starts $entry, which it doesn't contain"
  exit 1
fi

if [ "$(od -An -tx1 -N4 "$copy/executable" | tr -d ' \n')" != 7f454c46 ]; then
  echo "::warning::The image starts $path, which isn't an executable, so its runtime libraries aren't checked"
  exit 0
fi
if ! readelf --dynamic "$copy/executable" | grep -q '(NEEDED)'; then
  echo "$path is statically linked"
  exit 0
fi

status=0
linkage=$(docker run --rm --entrypoint ldd "$CI_IMAGE" "$path" 2>&1) || status=$?
printf '%s\n' "$linkage"
if [ "$status" -eq 127 ] || [[ $linkage == *'executable file not found'* ]]; then
  echo "::warning::The image has no ldd, so the runtime libraries of $path aren't checked"
  exit 0
fi
if [ "$status" -ne 0 ]; then
  echo "::error::ldd couldn't read $path"
  exit 1
fi
if [[ $linkage == *'not found'* ]]; then
  echo "::error::$path misses a runtime library the image doesn't contain"
  exit 1
fi
echo "$path finds every runtime library it links"

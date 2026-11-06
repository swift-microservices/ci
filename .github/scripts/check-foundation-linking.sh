#!/bin/bash
## Copyright (c) 2026 Zaid Rahhawi
## SPDX-License-Identifier: MIT
## See LICENSE for license information.

# Fails when a library product, or a named executable product, links Foundation's full library or ICU.
# Runs from the package's root, in a container with the Swift toolchain.
#
# Environment:
# - EXCLUDED_PRODUCTS: products that still link Foundation through a dependency, not checked (space-separated).
# - EXECUTABLE_PRODUCTS: executable products to check besides the library products (space-separated).

set -euo pipefail

if ! command -v jq > /dev/null; then
  apt-get -q update && apt-get -q install -y --no-install-recommends jq
fi

found=false
check_binary() {
  local linkage
  linkage=$(ldd "$1")
  printf '%s\n' "$linkage"
  for library in libFoundation.so libFoundationInternationalization.so lib_FoundationICU.so; do
    if grep -qF "$library" <<<"$linkage"; then
      echo "::error::$2 links $library; import FoundationEssentials instead, or exclude the product"
      found=true
    fi
  done
}

package_path=$(pwd)
# A path dependency's identity is its directory's name, lowercased.
package_identity=$(basename "$package_path" | tr '[:upper:]' '[:lower:]')
tools_version=$(swift package tools-version)
all_products=$(swift package describe --type json | jq -r '.products[] | select(.type | has("library")) | .name')
if [ -z "$all_products" ] && [ -z "$EXECUTABLE_PRODUCTS" ]; then
  echo '::error::The package has no library products, and executable_products names none'
  exit 1
fi

read -r -a excluded <<<"$EXCLUDED_PRODUCTS"
is_excluded() {
  local name
  for name in "${excluded[@]}"; do
    if [ "$name" = "$1" ]; then
      return 0
    fi
  done
  return 1
}
products=""
while read -r product; do
  if [ -n "$product" ] && ! is_excluded "$product"; then
    products+="$product"$'\n'
  fi
done <<<"$all_products"
products=${products%$'\n'}
executables=()
read -r -a requested_executables <<<"$EXECUTABLE_PRODUCTS"
for product in "${requested_executables[@]}"; do
  if ! is_excluded "$product"; then
    executables+=("$product")
  fi
done
for product in "${excluded[@]}"; do
  echo "::notice::$product isn't checked: excluded_products names it as linking Foundation through a dependency"
done
if [ -z "$products" ] && [ "${#executables[@]}" -eq 0 ]; then
  echo 'Nothing to check: every product is excluded'
  exit 0
fi

if [ -n "$products" ]; then
  check_path=$(mktemp -d)
  mkdir -p "$check_path/Sources/FoundationLinkingCheck"
  touch "$check_path/Sources/FoundationLinkingCheck/main.swift"
  dependencies=$(jq -Rr --arg package "$package_identity" \
    '".product(name: \"\(.)\", package: \"\($package)\"),"' <<<"$products")
  cat > "$check_path/Package.swift" <<EOF
// swift-tools-version: $tools_version
import PackageDescription

let package = Package(
    name: "foundation-linking-check",
    dependencies: [.package(path: "$package_path")],
    targets: [.executableTarget(name: "FoundationLinkingCheck", dependencies: [$dependencies])]
)
EOF
  echo "Checking the library products: $(tr '\n' ' ' <<<"$products")"
  swift build --package-path "$check_path" --configuration release
  bin_path=$(swift build --package-path "$check_path" --configuration release --show-bin-path)
  check_binary "$bin_path/FoundationLinkingCheck" 'A library product'
fi

# A package that commits Package.resolved is checked at that resolution.
resolution_flags=()
if [ -f Package.resolved ]; then
  resolution_flags=(--disable-automatic-resolution)
fi
for product in "${executables[@]}"; do
  echo "Checking the executable product $product"
  swift build --configuration release "${resolution_flags[@]}" --product "$product"
  bin_path=$(swift build --configuration release --show-bin-path)
  check_binary "$bin_path/$product" "$product"
done

if [ "$found" = true ]; then
  exit 1
fi

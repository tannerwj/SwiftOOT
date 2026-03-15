#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
vendor_oot="$repo_root/Vendor/oot"
patch_dir="$repo_root/docs/vendor-oot-patches"

if ! git -C "$vendor_oot" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Vendor/oot is not initialized. Run 'git submodule update --init Vendor/oot' first." >&2
  exit 1
fi

for patch in "$patch_dir"/*.patch; do
  if git -C "$vendor_oot" apply --check "$patch" >/dev/null 2>&1; then
    git -C "$vendor_oot" apply "$patch"
    echo "Applied $(basename "$patch")"
    continue
  fi

  if git -C "$vendor_oot" apply --reverse --check "$patch" >/dev/null 2>&1; then
    echo "Already applied $(basename "$patch")"
    continue
  fi

  echo "Patch $(basename "$patch") does not apply cleanly to Vendor/oot." >&2
  exit 1
done

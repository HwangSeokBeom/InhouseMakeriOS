#!/usr/bin/env bash
set -euo pipefail

project_path="${1:?project path is required}"
scheme_name="${2:?scheme name is required}"

destination_id="$(
  xcrun simctl list devices available \
    | sed -nE 's/^[[:space:]]+iPhone[^()]*\(([A-F0-9-]+)\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p' \
    | head -n 1
)"

if [[ -z "${destination_id}" ]]; then
  destination_id="$(
    xcrun simctl list devices available \
      | sed -nE 's/^[[:space:]]+.+\(([A-F0-9-]+)\) \((Booted|Shutdown)\)[[:space:]]*$/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "${destination_id}" ]]; then
  echo "Unable to resolve an available iOS Simulator destination for scheme ${scheme_name}." >&2
  exit 1
fi

printf 'platform=iOS Simulator,id=%s\n' "${destination_id}"

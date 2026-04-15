#!/usr/bin/env bash
set -euo pipefail

environment_name="${1:?environment is required (staging|production)}"
mode="${2:-build}"
upper_environment="$(printf '%s' "${environment_name}" | tr '[:lower:]' '[:upper:]')"

required_vars=(
  "IOS_API_BASE_URL_${upper_environment}"
  "IOS_GOOGLE_CLIENT_ID_${upper_environment}"
  "IOS_GOOGLE_REVERSED_CLIENT_ID_${upper_environment}"
  "IOS_DEVELOPMENT_TEAM"
)

if [[ "${mode}" == "upload" ]]; then
  required_vars+=(
    "IOS_FASTLANE_APP_IDENTIFIER"
    "APP_STORE_CONNECT_API_KEY_ID"
    "APP_STORE_CONNECT_ISSUER_ID"
    "APP_STORE_CONNECT_API_KEY_CONTENT"
  )
fi

missing_vars=()

for required_var in "${required_vars[@]}"; do
  if [[ -z "${!required_var:-}" ]]; then
    missing_vars+=("${required_var}")
  fi
done

if (( ${#missing_vars[@]} > 0 )); then
  printf 'Missing required CI environment values for %s: %s\n' \
    "${environment_name}" \
    "$(IFS=', '; printf '%s' "${missing_vars[*]}")" >&2
  exit 1
fi

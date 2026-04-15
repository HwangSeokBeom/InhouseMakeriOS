#!/usr/bin/env bash
set -euo pipefail

environment_name="${1:?environment is required (dev|staging|production)}"
output_path="${2:-${RUNNER_TEMP:-/tmp}/inhouse-ios-ci.xcconfig}"

upper_environment="$(printf '%s' "${environment_name}" | tr '[:lower:]' '[:upper:]')"

api_base_url_var="IOS_API_BASE_URL_${upper_environment}"
google_client_id_var="IOS_GOOGLE_CLIENT_ID_${upper_environment}"
google_reversed_client_id_var="IOS_GOOGLE_REVERSED_CLIENT_ID_${upper_environment}"

api_base_url="${!api_base_url_var:-}"
google_client_id="${!google_client_id_var:-}"
google_reversed_client_id="${!google_reversed_client_id_var:-}"
development_team="${IOS_DEVELOPMENT_TEAM:-63SB2B8YJ5}"

cat > "${output_path}" <<EOF
INHOUSE_API_BASE_URL = ${api_base_url}
INHOUSE_GOOGLE_CLIENT_ID = ${google_client_id}
INHOUSE_GOOGLE_REVERSED_CLIENT_ID = ${google_reversed_client_id}
INHOUSE_DEVELOPMENT_TEAM = ${development_team}
EOF

printf '%s\n' "${output_path}"

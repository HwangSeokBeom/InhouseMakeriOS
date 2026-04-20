#!/usr/bin/env bash
set -euo pipefail

environment_name="${1:?environment is required (development|production)}"
output_path="${2:-${RUNNER_TEMP:-/tmp}/inhouse-ios-ci.xcconfig}"

upper_environment="$(printf '%s' "${environment_name}" | tr '[:lower:]' '[:upper:]')"

google_client_id_var="IOS_GOOGLE_CLIENT_ID_${upper_environment}"
google_reversed_client_id_var="IOS_GOOGLE_REVERSED_CLIENT_ID_${upper_environment}"

google_client_id="${!google_client_id_var:-}"
google_reversed_client_id="${!google_reversed_client_id_var:-}"
development_team="${IOS_DEVELOPMENT_TEAM:-63SB2B8YJ5}"

cat > "${output_path}" <<EOF
INHOUSE_GOOGLE_CLIENT_ID = ${google_client_id}
INHOUSE_GOOGLE_REVERSED_CLIENT_ID = ${google_reversed_client_id}
INHOUSE_DEVELOPMENT_TEAM = ${development_team}
EOF

printf '%s\n' "${output_path}"

#!/usr/bin/env bash
set -euo pipefail

export DEPLOY_ENV="staging"
export DEPLOY_BRANCH="staging"
export PM2_APP_NAME="inhouse-maker-server-staging"
export PM2_ENV_NAME="staging"

bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-common.sh"

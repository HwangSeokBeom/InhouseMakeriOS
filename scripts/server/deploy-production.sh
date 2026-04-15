#!/usr/bin/env bash
set -euo pipefail

export DEPLOY_ENV="production"
export DEPLOY_BRANCH="main"
export PM2_APP_NAME="inhouse-maker-server-production"
export PM2_ENV_NAME="production"

bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deploy-common.sh"

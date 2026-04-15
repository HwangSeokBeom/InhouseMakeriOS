#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

deploy_env="${DEPLOY_ENV:?DEPLOY_ENV is required}"
deploy_branch="${DEPLOY_BRANCH:?DEPLOY_BRANCH is required}"
pm2_app_name="${PM2_APP_NAME:?PM2_APP_NAME is required}"
pm2_env_name="${PM2_ENV_NAME:?PM2_ENV_NAME is required}"
git_remote_name="${GIT_REMOTE_NAME:-origin}"
server_dir="${SERVER_DIR:-${repo_root}/server}"
ecosystem_path="${server_dir}/ecosystem.config.cjs"
env_file="${server_dir}/.env.${deploy_env}"
previous_revision="$(git -C "${repo_root}" rev-parse HEAD)"

log() {
  printf '[deploy:%s] %s\n' "${deploy_env}" "$*"
}

read_env_value() {
  local key="$1"

  if [[ ! -f "${env_file}" ]]; then
    return 0
  fi

  grep -E "^${key}=" "${env_file}" | tail -n 1 | cut -d "=" -f 2- | tr -d '\r' | sed -e 's/^"//' -e 's/"$//'
}

install_dependencies() {
  cd "${server_dir}"

  if [[ -f package-lock.json ]]; then
    npm ci
    return
  fi

  log "package-lock.json is missing. Falling back to npm install. TODO: commit a lockfile before production rollout."
  npm install
}

run_prisma_generate_if_present() {
  cd "${server_dir}"

  if [[ -f prisma/schema.prisma ]]; then
    npx prisma generate
    return
  fi

  log "No prisma/schema.prisma found. Skipping prisma generate."
}

run_prisma_migrate_if_present() {
  cd "${server_dir}"

  if [[ -f prisma/schema.prisma ]]; then
    npx prisma migrate deploy
    return
  fi

  log "No prisma/schema.prisma found. Skipping prisma migrate deploy."
}

reload_pm2() {
  if ! command -v pm2 >/dev/null 2>&1; then
    log "pm2 is not installed on the target server."
    exit 1
  fi

  if pm2 describe "${pm2_app_name}" >/dev/null 2>&1; then
    pm2 reload "${ecosystem_path}" --only "${pm2_app_name}" --env "${pm2_env_name}" --update-env
  else
    pm2 start "${ecosystem_path}" --only "${pm2_app_name}" --env "${pm2_env_name}"
  fi

  pm2 save
}

rollback() {
  local exit_code=$?
  trap - ERR

  log "Deployment failed. Attempting application rollback to ${previous_revision}."

  if git -C "${repo_root}" checkout "${previous_revision}" >/dev/null 2>&1; then
    install_dependencies || true
    run_prisma_generate_if_present || true
    (cd "${server_dir}" && npm run build) || true
    reload_pm2 || true
  fi

  log "Rollback completed with limitations. Prisma migrations are not automatically reverted."
  exit "${exit_code}"
}

trap rollback ERR

if [[ ! -f "${env_file}" ]]; then
  log "Missing ${env_file}. Copy server/.env.${deploy_env}.example to ${env_file} and fill the TODO values first."
  exit 1
fi

log "Fetching latest code for ${deploy_branch}."
git -C "${repo_root}" fetch --prune "${git_remote_name}"
git -C "${repo_root}" checkout "${deploy_branch}"
git -C "${repo_root}" pull --ff-only "${git_remote_name}" "${deploy_branch}"

log "Installing dependencies."
install_dependencies

log "Generating Prisma client when available."
run_prisma_generate_if_present

log "Building NestJS server."
(cd "${server_dir}" && npm run build)

log "Applying Prisma migrations when available."
run_prisma_migrate_if_present

log "Reloading PM2 process ${pm2_app_name}."
reload_pm2

healthcheck_url="${DEPLOY_HEALTHCHECK_URL:-}"

if [[ -z "${healthcheck_url}" ]]; then
  healthcheck_url="$(read_env_value "SERVER_HEALTHCHECK_URL")"
fi

if [[ -z "${healthcheck_url}" ]]; then
  port="$(read_env_value "PORT")"
  health_path="$(read_env_value "HEALTH_CHECK_PATH")"
  port="${port:-3000}"
  health_path="${health_path:-/health}"
  healthcheck_url="http://127.0.0.1:${port}${health_path}"
fi

log "Running health check against ${healthcheck_url}."
bash "${script_dir}/health-check.sh" "${healthcheck_url}"

trap - ERR
log "Deployment completed successfully."

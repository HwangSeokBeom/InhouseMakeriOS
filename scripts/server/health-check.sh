#!/usr/bin/env bash
set -euo pipefail

healthcheck_url="${1:?health check URL is required}"
max_attempts="${2:-10}"
delay_seconds="${3:-3}"

for attempt in $(seq 1 "${max_attempts}"); do
  if curl --fail --silent --show-error "${healthcheck_url}" >/dev/null; then
    printf '[health-check] %s is healthy on attempt %s.\n' "${healthcheck_url}" "${attempt}"
    exit 0
  fi

  printf '[health-check] attempt %s/%s failed for %s. Retrying in %ss.\n' \
    "${attempt}" \
    "${max_attempts}" \
    "${healthcheck_url}" \
    "${delay_seconds}"
  sleep "${delay_seconds}"
done

printf '[health-check] %s never became healthy.\n' "${healthcheck_url}" >&2
exit 1

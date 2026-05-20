#!/usr/bin/env bash
set -Eeuo pipefail

MAJOR="${ELASTIC_MAJOR:-9}"
FALLBACK_VERSION="${ELASTIC_FALLBACK_VERSION:-9.4.1}"
VERSIONS_URL="${ELASTIC_VERSIONS_URL:-https://artifacts-api.elastic.co/v1/versions/}"

latest_from_api() {
  curl -fsSL "$VERSIONS_URL" \
    | tr ',' '\n' \
    | sed -n -E "s/.*\"(${MAJOR}\.[0-9]+\.[0-9]+)\".*/\1/p" \
    | sort -V \
    | tail -n 1
}

main() {
  local latest

  latest="$(latest_from_api 2>/dev/null || true)"
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest"
  else
    printf '%s\n' "$FALLBACK_VERSION"
  fi
}

main "$@"

#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker/compose.yml"
ELASTIC_VERSION="${ELASTIC_VERSION:-$(bash "$SCRIPT_DIR/elastic_version.sh")}"

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

command -v docker >/dev/null 2>&1 || die "Docker is required. On macOS, install Docker Desktop or Colima first."
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required."
[[ -f "$COMPOSE_FILE" ]] || die "compose file not found: $COMPOSE_FILE"

export ELASTIC_VERSION

printf 'Starting Easy-ELK with Docker Compose using Elastic %s\n' "$ELASTIC_VERSION"
compose up -d

printf '\nEasy-ELK is starting.\n'
printf 'Kibana:        http://127.0.0.1:5601\n'
printf 'Elasticsearch: http://127.0.0.1:9200\n'
printf '\nCheck status with:\n'
printf '  docker compose -f docker/compose.yml ps\n'

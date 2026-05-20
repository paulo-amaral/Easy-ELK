#!/usr/bin/env bash
set -Eeuo pipefail

# Standalone Linux installer: Elastic Stack with Kibana behind Nginx.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/scripts/install_elk.sh" nginx "$@"

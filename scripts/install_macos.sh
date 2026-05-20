#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-tarball}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ELASTIC_VERSION="${ELASTIC_VERSION:-$(bash "$SCRIPT_DIR/elastic_version.sh")}"
INSTALL_DIR="${EASY_ELK_HOME:-$PWD/.easy-elk}"
BREW_PREFIX=""

log() {
  printf '\033[32m%s\033[0m\n' "$*"
}

warn() {
  printf '\033[33m%s\033[0m\n' "$*" >&2
}

die() {
  printf '\033[31mError: %s\033[0m\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  scripts/install_macos.sh [homebrew|macports|tarball]

Modes:
  homebrew  Install via Homebrew elastic/tap and start with brew services.
  macports  Install via MacPorts when ports are available.
  tarball   Download official Elastic tarballs into .easy-elk and run locally.

Environment:
  ELASTIC_VERSION=9.4.0
  EASY_ELK_HOME=.easy-elk
EOF
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "this installer is macOS-only"
}

set_yaml_value() {
  local file="$1"
  local key="$2"
  local value="$3"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if grep -Eq "^[#[:space:]]*${key}:" "$file"; then
    sed -i '' -E "s|^[#[:space:]]*${key}:.*|${key}: ${value}|" "$file"
  else
    printf '\n%s: %s\n' "$key" "$value" >> "$file"
  fi
}

install_homebrew() {
  command -v brew >/dev/null 2>&1 || die "Homebrew is not installed"
  BREW_PREFIX="$(brew --prefix)"

  warn "Homebrew Elastic formulae are convenient but may lag official tarball releases."
  log "Installing Elastic Stack with Homebrew"
  brew tap elastic/tap
  brew install elastic/tap/elasticsearch-full elastic/tap/kibana-full elastic/tap/logstash-full

  set_yaml_value "$BREW_PREFIX/etc/elasticsearch/elasticsearch.yml" "cluster.name" "\"easy-elk\""
  set_yaml_value "$BREW_PREFIX/etc/elasticsearch/elasticsearch.yml" "network.host" "127.0.0.1"
  set_yaml_value "$BREW_PREFIX/etc/elasticsearch/elasticsearch.yml" "http.port" "9200"
  set_yaml_value "$BREW_PREFIX/etc/elasticsearch/elasticsearch.yml" "discovery.type" "single-node"
  set_yaml_value "$BREW_PREFIX/etc/elasticsearch/elasticsearch.yml" "xpack.security.enabled" "false"

  set_yaml_value "$BREW_PREFIX/etc/kibana/kibana.yml" "server.host" "\"127.0.0.1\""
  set_yaml_value "$BREW_PREFIX/etc/kibana/kibana.yml" "server.port" "5601"
  set_yaml_value "$BREW_PREFIX/etc/kibana/kibana.yml" "elasticsearch.hosts" "[\"http://127.0.0.1:9200\"]"

  mkdir -p "$BREW_PREFIX/etc/logstash/conf.d"
  cat > "$BREW_PREFIX/etc/logstash/conf.d/easy-elk.conf" <<'EOF'
input {
  beats {
    port => 5044
  }
}

output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "easy-elk-%{+YYYY.MM.dd}"
  }
}
EOF

  brew services start elastic/tap/elasticsearch-full
  brew services start elastic/tap/kibana-full
  brew services start elastic/tap/logstash-full

  log "Homebrew install completed"
  printf 'Kibana: http://127.0.0.1:5601\n'
}

install_macports() {
  command -v port >/dev/null 2>&1 || die "MacPorts is not installed"

  warn "MacPorts package availability/versioning varies by port. The tarball mode is usually more predictable."
  log "Installing Elastic Stack with MacPorts"

  sudo port selfupdate

  for port_name in elasticsearch kibana logstash; do
    if port info "$port_name" >/dev/null 2>&1; then
      sudo port install "$port_name"
    else
      warn "MacPorts port not found: ${port_name}; skipping"
    fi
  done

  if [[ -f /opt/local/etc/elasticsearch/elasticsearch.yml ]]; then
    sudo sh -c "cat >> /opt/local/etc/elasticsearch/elasticsearch.yml" <<'EOF'

cluster.name: "easy-elk"
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
EOF
  fi

  if [[ -f /opt/local/etc/kibana/kibana.yml ]]; then
    sudo sh -c "cat >> /opt/local/etc/kibana/kibana.yml" <<'EOF'

server.host: "127.0.0.1"
server.port: 5601
elasticsearch.hosts: ["http://127.0.0.1:9200"]
EOF
  fi

  for service_name in elasticsearch kibana logstash; do
    if port installed "$service_name" >/dev/null 2>&1; then
      sudo port load "$service_name" || warn "Could not load MacPorts service: ${service_name}"
    fi
  done

  log "MacPorts install completed"
  printf 'Kibana, when the port is available/running: http://127.0.0.1:5601\n'
}

artifact_arch() {
  case "$(uname -m)" in
    arm64|aarch64) printf 'aarch64' ;;
    x86_64|amd64) printf 'x86_64' ;;
    *) die "unsupported macOS architecture: $(uname -m)" ;;
  esac
}

download_artifact() {
  local product="$1"
  local version="$2"
  local dest="$3"
  local arch
  local urls=()
  arch="$(artifact_arch)"

  case "$product" in
    elasticsearch)
      urls+=("https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${version}-darwin-${arch}.tar.gz")
      ;;
    kibana)
      urls+=("https://artifacts.elastic.co/downloads/kibana/kibana-${version}-darwin-${arch}.tar.gz")
      ;;
    logstash)
      urls+=("https://artifacts.elastic.co/downloads/logstash/logstash-${version}-darwin-${arch}.tar.gz")
      urls+=("https://artifacts.elastic.co/downloads/logstash/logstash-${version}.tar.gz")
      ;;
  esac

  for url in "${urls[@]}"; do
    log "Downloading ${url}"
    if curl -fL --retry 3 -o "$dest" "$url"; then
      return 0
    fi
  done

  die "could not download ${product} ${version}"
}

extract_tarball() {
  local archive="$1"
  local target="$2"

  rm -rf "$target"
  mkdir -p "$target"
  tar -xzf "$archive" -C "$target" --strip-components=1
}

install_tarball() {
  local downloads="$INSTALL_DIR/downloads"
  local elasticsearch_dir="$INSTALL_DIR/elasticsearch"
  local kibana_dir="$INSTALL_DIR/kibana"
  local logstash_dir="$INSTALL_DIR/logstash"

  log "Installing official Elastic tarballs into ${INSTALL_DIR}"
  mkdir -p "$downloads" "$INSTALL_DIR/logs" "$INSTALL_DIR/pids"

  download_artifact elasticsearch "$ELASTIC_VERSION" "$downloads/elasticsearch.tar.gz"
  download_artifact kibana "$ELASTIC_VERSION" "$downloads/kibana.tar.gz"
  download_artifact logstash "$ELASTIC_VERSION" "$downloads/logstash.tar.gz"

  extract_tarball "$downloads/elasticsearch.tar.gz" "$elasticsearch_dir"
  extract_tarball "$downloads/kibana.tar.gz" "$kibana_dir"
  extract_tarball "$downloads/logstash.tar.gz" "$logstash_dir"

  set_yaml_value "$elasticsearch_dir/config/elasticsearch.yml" "cluster.name" "\"easy-elk\""
  set_yaml_value "$elasticsearch_dir/config/elasticsearch.yml" "network.host" "127.0.0.1"
  set_yaml_value "$elasticsearch_dir/config/elasticsearch.yml" "http.port" "9200"
  set_yaml_value "$elasticsearch_dir/config/elasticsearch.yml" "discovery.type" "single-node"
  set_yaml_value "$elasticsearch_dir/config/elasticsearch.yml" "xpack.security.enabled" "false"
  printf -- '-Xms1g\n-Xmx1g\n' > "$elasticsearch_dir/config/jvm.options.d/easy-elk.options"

  set_yaml_value "$kibana_dir/config/kibana.yml" "server.host" "\"127.0.0.1\""
  set_yaml_value "$kibana_dir/config/kibana.yml" "server.port" "5601"
  set_yaml_value "$kibana_dir/config/kibana.yml" "elasticsearch.hosts" "[\"http://127.0.0.1:9200\"]"

  cat > "$logstash_dir/config/easy-elk.conf" <<'EOF'
input {
  beats {
    port => 5044
  }
}

output {
  elasticsearch {
    hosts => ["http://127.0.0.1:9200"]
    index => "easy-elk-%{+YYYY.MM.dd}"
  }
}
EOF

  write_tarball_controls

  log "Tarball install completed"
  printf 'Start:  %s/bin/easy-elk-start\n' "$INSTALL_DIR"
  printf 'Stop:   %s/bin/easy-elk-stop\n' "$INSTALL_DIR"
  printf 'Status: %s/bin/easy-elk-status\n' "$INSTALL_DIR"
}

write_tarball_controls() {
  mkdir -p "$INSTALL_DIR/bin"

  cat > "$INSTALL_DIR/bin/easy-elk-start" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$INSTALL_DIR"
mkdir -p "\$ROOT/logs" "\$ROOT/pids"

start_one() {
  local name="\$1"
  shift
  if [[ -f "\$ROOT/pids/\${name}.pid" ]] && kill -0 "\$(cat "\$ROOT/pids/\${name}.pid")" 2>/dev/null; then
    echo "\${name} is already running"
    return
  fi
  nohup "\$@" > "\$ROOT/logs/\${name}.log" 2>&1 &
  echo \$! > "\$ROOT/pids/\${name}.pid"
  echo "started \${name}"
}

start_one elasticsearch "\$ROOT/elasticsearch/bin/elasticsearch"
start_one kibana "\$ROOT/kibana/bin/kibana"
start_one logstash "\$ROOT/logstash/bin/logstash" -f "\$ROOT/logstash/config/easy-elk.conf"
echo "Kibana: http://127.0.0.1:5601"
EOF

  cat > "$INSTALL_DIR/bin/easy-elk-stop" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$INSTALL_DIR"
for name in logstash kibana elasticsearch; do
  pid_file="\$ROOT/pids/\${name}.pid"
  if [[ -f "\$pid_file" ]] && kill -0 "\$(cat "\$pid_file")" 2>/dev/null; then
    kill "\$(cat "\$pid_file")"
    echo "stopped \${name}"
  else
    echo "\${name} is not running"
  fi
  rm -f "\$pid_file"
done
EOF

  cat > "$INSTALL_DIR/bin/easy-elk-status" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$INSTALL_DIR"
for name in elasticsearch kibana logstash; do
  pid_file="\$ROOT/pids/\${name}.pid"
  if [[ -f "\$pid_file" ]] && kill -0 "\$(cat "\$pid_file")" 2>/dev/null; then
    echo "\${name}: running (pid \$(cat "\$pid_file"))"
  else
    echo "\${name}: stopped"
  fi
done
EOF

  chmod +x "$INSTALL_DIR/bin/easy-elk-start" "$INSTALL_DIR/bin/easy-elk-stop" "$INSTALL_DIR/bin/easy-elk-status"
}

require_macos

case "$MODE" in
  homebrew|--homebrew) install_homebrew ;;
  macports|--macports) install_macports ;;
  tarball|--tarball) install_tarball ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac

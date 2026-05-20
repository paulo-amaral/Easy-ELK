#!/usr/bin/env bash
set -Eeuo pipefail

PROXY="${1:-nginx}"
ELASTIC_MAJOR="${ELASTIC_MAJOR:-9}"
KIBANA_USER="${KIBANA_USER:-admin}"
KIBANA_PASSWORD="${KIBANA_PASSWORD:-}"
ELASTIC_SECURITY="${ELASTIC_SECURITY:-false}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180}"
OS_ID=""
OS_ID_LIKE=""
OS_NAME=""
PKG_FAMILY=""
PKG_MANAGER=""
APACHE_SERVICE=""
APACHE_HTPASSWD=""
NGINX_SERVICE="nginx"

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

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '[dry-run] %q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "run this installer as root"
}

detect_os() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found"
  # shellcheck disable=SC1091
  . /etc/os-release

  OS_ID="${ID:-}"
  OS_ID_LIKE="${ID_LIKE:-}"
  OS_NAME="${PRETTY_NAME:-unknown}"

  case "${OS_ID}:${OS_ID_LIKE}" in
    debian:*|ubuntu:*|linuxmint:*|pop:*|zorin:*|elementary:*|*:debian*)
      PKG_FAMILY="deb"
      PKG_MANAGER="apt-get"
      APACHE_SERVICE="apache2"
      APACHE_HTPASSWD="/etc/apache2/.htpasswd-kibana"
      ;;
    rhel:*|centos:*|fedora:*|rocky:*|almalinux:*|ol:*|oracle:*|amzn:*|*:rhel*|*:fedora*)
      PKG_FAMILY="rpm"
      if command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
      elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
      else
        die "dnf/yum not found on ${OS_NAME}"
      fi
      APACHE_SERVICE="httpd"
      APACHE_HTPASSWD="/etc/httpd/.htpasswd-kibana"
      ;;
    sles:*|sled:*|opensuse*:*|suse:*|*:suse*)
      PKG_FAMILY="suse"
      command -v zypper >/dev/null 2>&1 || die "zypper not found on ${OS_NAME}"
      PKG_MANAGER="zypper"
      APACHE_SERVICE="apache2"
      APACHE_HTPASSWD="/etc/apache2/.htpasswd-kibana"
      ;;
    *)
      die "unsupported OS (${OS_NAME}). Supported families: Debian/Ubuntu, RHEL/Fedora/Rocky/Alma/Oracle/Amazon Linux, and SUSE/openSUSE"
      ;;
  esac

  log "Detected ${OS_NAME} (${PKG_FAMILY}/${PKG_MANAGER})"
}

service_ctl() {
  local action="$1"
  local service="$2"

  if command -v systemctl >/dev/null 2>&1; then
    run systemctl "$action" "$service"
  else
    case "$action" in
      enable) run update-rc.d "$service" defaults ;;
      start) run service "$service" start ;;
      restart) run service "$service" restart ;;
      reload) run service "$service" reload ;;
      *) die "unsupported service action: $action" ;;
    esac
  fi
}

pkg_update() {
  case "$PKG_FAMILY" in
    deb) run apt-get update ;;
    rpm) run "$PKG_MANAGER" makecache -y ;;
    suse) run zypper --non-interactive refresh ;;
  esac
}

pkg_install() {
  case "$PKG_FAMILY" in
    deb) run apt-get install -y "$@" ;;
    rpm) run "$PKG_MANAGER" install -y "$@" ;;
    suse) run zypper --non-interactive install -y "$@" ;;
  esac
}

install_dependencies() {
  log "Updating package metadata and installing base dependencies"
  pkg_update
  case "$PKG_FAMILY" in
    deb) pkg_install apt-transport-https ca-certificates curl wget gnupg openssl ;;
    rpm) pkg_install ca-certificates curl wget gnupg2 openssl ;;
    suse) pkg_install ca-certificates curl wget gpg2 openssl ;;
  esac
}

install_proxy_package() {
  case "$PROXY" in
    apache)
      log "Installing Apache"
      case "$PKG_FAMILY" in
        deb) pkg_install apache2 apache2-utils ;;
        rpm) pkg_install httpd httpd-tools ;;
        suse) pkg_install apache2 apache2-utils ;;
      esac
      ;;
    nginx)
      log "Installing Nginx"
      case "$PKG_FAMILY" in
        deb) pkg_install nginx apache2-utils ;;
        rpm) pkg_install nginx httpd-tools ;;
        suse) pkg_install nginx apache2-utils ;;
      esac
      ;;
    *) die "proxy must be 'apache' or 'nginx'" ;;
  esac
}

configure_elastic_repo() {
  local keyring="/usr/share/keyrings/elasticsearch-keyring.gpg"
  local repo_file="/etc/apt/sources.list.d/elastic-${ELASTIC_MAJOR}.x.list"
  local rpm_repo_file="/etc/yum.repos.d/elastic-${ELASTIC_MAJOR}.x.repo"
  local suse_repo_file="/etc/zypp/repos.d/elastic-${ELASTIC_MAJOR}.x.repo"
  local tmp_keyring

  log "Configuring Elastic ${ELASTIC_MAJOR}.x package repository"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    case "$PKG_FAMILY" in
      deb)
        run install -d -m 0755 /usr/share/keyrings
        run wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch
        run tee "$repo_file"
        ;;
      rpm)
        run rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
        run tee "$rpm_repo_file"
        ;;
      suse)
        run rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
        run tee "$suse_repo_file"
        ;;
    esac
    return
  fi

  case "$PKG_FAMILY" in
    deb)
      install -d -m 0755 /usr/share/keyrings
      tmp_keyring="$(mktemp)"
      wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o "$tmp_keyring"
      mv "$tmp_keyring" "$keyring"
      chmod 0644 "$keyring"
      printf 'deb [signed-by=%s] https://artifacts.elastic.co/packages/%s.x/apt stable main\n' \
        "$keyring" "$ELASTIC_MAJOR" > "$repo_file"
      ;;
    rpm)
      rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
      cat > "$rpm_repo_file" <<EOF
[elastic-${ELASTIC_MAJOR}.x]
name=Elastic repository for ${ELASTIC_MAJOR}.x packages
baseurl=https://artifacts.elastic.co/packages/${ELASTIC_MAJOR}.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF
      ;;
    suse)
      rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch
      cat > "$suse_repo_file" <<EOF
[elastic-${ELASTIC_MAJOR}.x]
name=Elastic repository for ${ELASTIC_MAJOR}.x packages
baseurl=https://artifacts.elastic.co/packages/${ELASTIC_MAJOR}.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF
      ;;
  esac
  pkg_update
}

install_elastic_stack() {
  log "Installing Elasticsearch, Kibana and Logstash"
  pkg_install elasticsearch kibana logstash
}

set_yaml_value() {
  local file="$1"
  local key="$2"
  local value="$3"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    run sed -i -E "s|^[#[:space:]]*${key}:.*|${key}: ${value}|" "$file"
    return
  fi

  if grep -Eq "^[#[:space:]]*${key}:" "$file"; then
    sed -i -E "s|^[#[:space:]]*${key}:.*|${key}: ${value}|" "$file"
  else
    printf '\n%s: %s\n' "$key" "$value" >> "$file"
  fi
}

configure_elasticsearch() {
  log "Configuring Elasticsearch for a single-node local install"
  set_yaml_value /etc/elasticsearch/elasticsearch.yml "cluster.name" "\"easy-elk\""
  set_yaml_value /etc/elasticsearch/elasticsearch.yml "network.host" "127.0.0.1"
  set_yaml_value /etc/elasticsearch/elasticsearch.yml "http.port" "9200"
  set_yaml_value /etc/elasticsearch/elasticsearch.yml "discovery.type" "single-node"

  if [[ "$ELASTIC_SECURITY" == "false" ]]; then
    warn "Elastic security is disabled for this Easy-ELK local/sandbox profile."
    set_yaml_value /etc/elasticsearch/elasticsearch.yml "xpack.security.enabled" "false"
  fi

  if [[ -d /etc/elasticsearch/jvm.options.d ]]; then
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      run tee /etc/elasticsearch/jvm.options.d/easy-elk.options
    else
      cat > /etc/elasticsearch/jvm.options.d/easy-elk.options <<EOF
-Xms1g
-Xmx1g
EOF
    fi
  fi

  service_ctl enable elasticsearch.service
  service_ctl start elasticsearch.service
}

configure_kibana() {
  log "Configuring Kibana"
  set_yaml_value /etc/kibana/kibana.yml "server.host" "\"127.0.0.1\""
  set_yaml_value /etc/kibana/kibana.yml "server.port" "5601"
  set_yaml_value /etc/kibana/kibana.yml "elasticsearch.hosts" "[\"http://127.0.0.1:9200\"]"

  service_ctl enable kibana.service
  service_ctl start kibana.service
}

allow_http_proxy_networking() {
  if command -v setsebool >/dev/null 2>&1 && command -v getenforce >/dev/null 2>&1; then
    if [[ "$(getenforce 2>/dev/null || true)" != "Disabled" ]]; then
      run setsebool -P httpd_can_network_connect 1
    fi
  fi
}

allow_http_firewall() {
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    run firewall-cmd --permanent --add-service=http
    run firewall-cmd --reload
  fi
}

configure_apache_proxy() {
  local domain
  local conf_file
  domain="$(hostname -d 2>/dev/null || true)"
  [[ -n "$domain" ]] || domain="local"

  log "Configuring Apache reverse proxy for Kibana"
  ensure_kibana_password

  case "$PKG_FAMILY" in
    deb)
      conf_file="/etc/apache2/sites-available/kibana.conf"
      run a2enmod proxy proxy_http headers rewrite
      ;;
    rpm)
      conf_file="/etc/httpd/conf.d/kibana.conf"
      ;;
    suse)
      conf_file="/etc/apache2/vhosts.d/kibana.conf"
      command -v a2enmod >/dev/null 2>&1 && run a2enmod proxy proxy_http headers rewrite
      ;;
  esac

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    run htpasswd -bc "$APACHE_HTPASSWD" "$KIBANA_USER" "$KIBANA_PASSWORD"
    run tee "$conf_file"
  else
    htpasswd -bc "$APACHE_HTPASSWD" "$KIBANA_USER" "$KIBANA_PASSWORD"
    cat > "$conf_file" <<EOF
<VirtualHost *:80>
    ServerName kibana.${domain}
    ServerAdmin admin@${domain}

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / http://127.0.0.1:5601/
    ProxyPassReverse / http://127.0.0.1:5601/
    RequestHeader set X-Forwarded-Proto "http"

    <Location />
        AuthType Basic
        AuthName "Kibana"
        AuthUserFile ${APACHE_HTPASSWD}
        Require valid-user
    </Location>

    ErrorLog \${APACHE_LOG_DIR}/kibana_error.log
    CustomLog \${APACHE_LOG_DIR}/kibana_access.log combined
</VirtualHost>
EOF
  fi

  if [[ "$PKG_FAMILY" == "deb" ]]; then
    run a2ensite kibana.conf
  fi
  allow_http_proxy_networking
  allow_http_firewall
  service_ctl enable "$APACHE_SERVICE"
  service_ctl restart "$APACHE_SERVICE"
}

ensure_kibana_password() {
  if [[ -z "$KIBANA_PASSWORD" ]]; then
    KIBANA_PASSWORD="$(openssl rand -base64 24)"
    printf 'Generated Kibana basic-auth password for user %s: %s\n' "$KIBANA_USER" "$KIBANA_PASSWORD"
  fi
}

configure_nginx_proxy() {
  local host_name
  local conf_file
  local enabled_file
  host_name="$(hostname -f 2>/dev/null || hostname)"

  log "Configuring Nginx reverse proxy for Kibana"
  ensure_kibana_password

  if [[ -d /etc/nginx/sites-available || "$PKG_FAMILY" == "deb" ]]; then
    conf_file="/etc/nginx/sites-available/kibana"
    enabled_file="/etc/nginx/sites-enabled/kibana"
  else
    conf_file="/etc/nginx/conf.d/kibana.conf"
    enabled_file=""
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    run htpasswd -bc /etc/nginx/.htpasswd.users "$KIBANA_USER" "$KIBANA_PASSWORD"
    run tee "$conf_file"
  else
    mkdir -p "$(dirname "$conf_file")"
    htpasswd -bc /etc/nginx/.htpasswd.users "$KIBANA_USER" "$KIBANA_PASSWORD"
    cat > "$conf_file" <<EOF
server {
    listen 80;
    server_name ${host_name};

    auth_basic "Kibana";
    auth_basic_user_file /etc/nginx/.htpasswd.users;

    access_log /var/log/nginx/kibana.access.log;
    error_log /var/log/nginx/kibana.error.log;

    location / {
        proxy_pass http://127.0.0.1:5601;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    if [[ -n "$enabled_file" ]]; then
      mkdir -p "$(dirname "$enabled_file")"
      ln -sfn "$conf_file" "$enabled_file"
      rm -f /etc/nginx/sites-enabled/default
    fi
    nginx -t
  fi

  allow_http_proxy_networking
  allow_http_firewall
  service_ctl enable "$NGINX_SERVICE"
  service_ctl restart "$NGINX_SERVICE"
}

configure_logstash() {
  log "Configuring Logstash with a minimal local pipeline"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    run tee /etc/logstash/conf.d/easy-elk.conf
  else
    cat > /etc/logstash/conf.d/easy-elk.conf <<'EOF'
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
  fi

  service_ctl enable logstash.service
  service_ctl start logstash.service
}

wait_for_elasticsearch() {
  local elapsed=0
  log "Waiting for Elasticsearch on http://127.0.0.1:9200"

  until curl -fsS http://127.0.0.1:9200 >/dev/null 2>&1; do
    if (( elapsed >= WAIT_TIMEOUT )); then
      die "Elasticsearch did not answer within ${WAIT_TIMEOUT}s; check journalctl -u elasticsearch"
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
}

main() {
  require_root
  detect_os
  install_dependencies
  install_proxy_package
  configure_elastic_repo
  install_elastic_stack
  configure_elasticsearch
  wait_for_elasticsearch
  configure_kibana

  case "$PROXY" in
    apache) configure_apache_proxy ;;
    nginx) configure_nginx_proxy ;;
  esac

  configure_logstash
  log "Easy-ELK installation completed"
}

main "$@"

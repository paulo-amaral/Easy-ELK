#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MODE="${EASY_ELK_MODE:-auto}"
PROXY="${EASY_ELK_PROXY:-nginx}"
ARGS_COUNT="$#"

usage() {
  cat <<'EOF'
Usage:
  scripts/install.sh
  scripts/install.sh [--docker] [--package] [--homebrew] [--macports] [--tarball] [--sandbox] [--proxy nginx|apache]

Modes:
  no args    Show a simple install/test menu.
  --docker   Run Easy-ELK with Docker Compose. Recommended for macOS and local Linux labs.
  --package  Install native Linux packages and system services. Linux only; requires root.
  --homebrew Install native macOS packages with Homebrew.
  --macports Install native macOS packages with MacPorts.
  --tarball  Install official Elastic tarballs locally. macOS only.
  --sandbox  Test the Linux installer in a Vagrant VM.

Environment:
  ELASTIC_VERSION=9.4.1      Elastic version. Auto-detected when omitted.
  ELASTIC_MAJOR=9            Major version used by auto-detection and Linux repos.
  EASY_ELK_MODE=auto|docker|package|homebrew|macports|tarball|sandbox
  EASY_ELK_PROXY=nginx|apache
  EASY_ELK_BOX=ubuntu/noble64   Vagrant box for --sandbox.
  EASY_ELK_PROVIDER=virtualbox  Vagrant provider for --sandbox.
EOF
}

prompt() {
  local answer
  printf '%s' "$1"
  read -r answer
  printf '%s' "$answer"
}

interactive_menu() {
  local os
  os="$(uname -s)"

  printf '\nEasy-ELK install/test menu\n'
  printf '1) Test locally with Docker Compose\n'
  if [[ "$os" == "Darwin" ]]; then
    printf '2) Install on macOS with official Elastic tarballs\n'
    printf '3) Install on macOS with Homebrew\n'
    printf '4) Install on macOS with MacPorts\n'
    printf '5) Test Linux install in Vagrant sandbox\n'
  elif [[ "$os" == "Linux" ]]; then
    printf '2) Install standalone Linux with Nginx\n'
    printf '3) Install standalone Linux with Apache\n'
    printf '4) Test Linux install in Vagrant sandbox\n'
  fi
  printf 'q) Quit\n\n'

  case "$(prompt 'Choose: ')" in
    1)
      MODE="docker"
      ;;
    2)
      if [[ "$os" == "Darwin" ]]; then
        MODE="tarball"
      else
        MODE="package"
        PROXY="nginx"
      fi
      ;;
    3)
      if [[ "$os" == "Darwin" ]]; then
        MODE="homebrew"
      else
        MODE="package"
        PROXY="apache"
      fi
      ;;
    4)
      if [[ "$os" == "Darwin" ]]; then
        MODE="macports"
      else
        MODE="sandbox"
      fi
      ;;
    5)
      [[ "$os" == "Darwin" ]] && MODE="sandbox" || exit 0
      ;;
    q|Q)
      exit 0
      ;;
    *)
      printf 'Invalid choice.\n' >&2
      exit 2
      ;;
  esac
}

detect_vagrant_provider() {
  if [[ -n "${EASY_ELK_PROVIDER:-}" ]]; then
    printf '%s' "$EASY_ELK_PROVIDER"
    return
  fi

  if command -v VBoxManage >/dev/null 2>&1; then
    printf 'virtualbox'
    return
  fi

  if command -v prlctl >/dev/null 2>&1; then
    printf 'parallels'
    return
  fi

  if command -v vmrun >/dev/null 2>&1; then
    printf 'vmware_desktop'
    return
  fi

  if command -v virsh >/dev/null 2>&1; then
    printf 'libvirt'
    return
  fi

  printf ''
}

if [[ "$ARGS_COUNT" -eq 0 && -t 0 ]]; then
  interactive_menu
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker)
      MODE="docker"
      shift
      ;;
    --package)
      MODE="package"
      shift
      ;;
    --homebrew)
      MODE="homebrew"
      shift
      ;;
    --macports)
      MODE="macports"
      shift
      ;;
    --tarball)
      MODE="tarball"
      shift
      ;;
    --sandbox)
      MODE="sandbox"
      shift
      ;;
    --proxy)
      PROXY="${2:-}"
      [[ -n "$PROXY" ]] || {
        usage
        exit 2
      }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$(uname -s)" in
  Darwin)
    [[ "$MODE" == "auto" ]] && MODE="docker"
    ;;
  Linux)
    [[ "$MODE" == "auto" ]] && MODE="package"
    ;;
  *)
    printf 'Unsupported OS: %s\n' "$(uname -s)" >&2
    exit 1
    ;;
esac

case "$MODE" in
  docker)
    exec bash "$SCRIPT_DIR/install_docker.sh"
    ;;
  homebrew|macports|tarball)
    [[ "$(uname -s)" == "Darwin" ]] || {
      printf '%s mode is macOS-only. Use --docker or --package on Linux.\n' "$MODE" >&2
      exit 1
    }
    exec bash "$SCRIPT_DIR/install_macos.sh" "$MODE"
    ;;
  package)
    [[ "$(uname -s)" == "Linux" ]] || {
      printf 'Native package mode is Linux-only. Use --docker on macOS.\n' >&2
      exit 1
    }
    exec bash "$SCRIPT_DIR/install_elk.sh" "$PROXY"
    ;;
  sandbox)
    provider="$(detect_vagrant_provider)"
    command -v vagrant >/dev/null 2>&1 || {
      printf 'Vagrant is required for sandbox mode.\n' >&2
      exit 1
    }
    if [[ -z "$provider" ]]; then
      printf 'No Vagrant provider was detected.\n' >&2
      printf 'Install VirtualBox, VMware, Parallels, or libvirt, or set EASY_ELK_PROVIDER manually.\n' >&2
      exit 1
    fi
    printf 'Using Vagrant provider: %s\n' "$provider"
    cd "$REPO_ROOT/sandbox"
    exec vagrant up --provider="$provider"
    ;;
  *)
    printf 'Invalid mode: %s\n' "$MODE" >&2
    exit 2
    ;;
esac

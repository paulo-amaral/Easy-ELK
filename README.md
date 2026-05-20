![Easy-ELK](https://socialify.git.ci/paulo-amaral/Easy-ELK/image?description=1&font=KoHo&forks=1&issues=1&language=1&owner=1&pattern=Charlie%20Brown&pulls=1&stargazers=1&theme=Light)

# Easy-ELK

Easy-ELK helps you install or test a single-node Elastic Stack:

- Elasticsearch
- Kibana
- Logstash
- Nginx or Apache reverse proxy for standalone Linux installs

The project has two goals:

- Make local testing easy on macOS or Linux.
- Keep standalone Linux installers available for real VMs or servers.

## Quick Start

Clone the repo:

```bash
git clone https://github.com/paulo-amaral/Easy-ELK
cd Easy-ELK
chmod +x scripts/*.sh easyELK*.sh
```

Run the menu and choose what you want:

```bash
./scripts/install.sh
```

You can also skip the menu and run a command directly.

## Version Detection

For Docker and macOS tarball installs, Easy-ELK automatically checks Elastic's public artifacts API and picks the latest stable version for `ELASTIC_MAJOR`.

Default:

```bash
ELASTIC_MAJOR=9
```

If the API cannot be reached, the scripts use this fallback:

```bash
9.4.1
```

Pin a specific version when you need reproducible tests:

```bash
ELASTIC_VERSION=9.4.1 ./scripts/install.sh --docker
ELASTIC_VERSION=9.4.1 ./scripts/install.sh --tarball
```

Check what version would be selected:

```bash
./scripts/elastic_version.sh
```

## Which Option Should I Use?

| Goal | Command |
| --- | --- |
| Test quickly on macOS or Linux | `./scripts/install.sh --docker` |
| Test the Linux installer in a VM | `./scripts/install.sh --sandbox` |
| Install on Linux with Nginx | `sudo ./easyELKnginx.sh` |
| Install on Linux with Apache | `sudo ./easyELKapache.sh` |
| Install on macOS with Elastic tarballs | `./scripts/install.sh --tarball` |
| Install on macOS with Homebrew | `./scripts/install.sh --homebrew` |
| Install on macOS with MacPorts | `./scripts/install.sh --macports` |

## Option 1: Test Locally With Docker

This is the simplest test path. It works on macOS and Linux.

Requirements:

- Docker
- Docker Compose v2

Start:

```bash
./scripts/install.sh --docker
```

Open Kibana:

```text
http://127.0.0.1:5601
```

Check containers:

```bash
docker compose -f docker/compose.yml ps
```

Stop:

```bash
docker compose -f docker/compose.yml down
```

Remove containers and data:

```bash
docker compose -f docker/compose.yml down -v
```

## Option 2: Install On Linux Standalone

Use this on a Linux VM or server when you want native packages and services.

Supported Linux families:

- Debian, Ubuntu, Linux Mint, Pop!_OS, Zorin, elementary OS
- RHEL, CentOS Stream, Rocky Linux, AlmaLinux, Oracle Linux, Fedora, Amazon Linux
- SLES, openSUSE Leap/Tumbleweed

Install with Nginx:

```bash
sudo ./easyELKnginx.sh
```

Install with Apache:

```bash
sudo ./easyELKapache.sh
```

Equivalent commands through the main installer:

```bash
sudo ./scripts/install.sh --package --proxy nginx
sudo ./scripts/install.sh --package --proxy apache
```

Useful variables:

```bash
sudo ELASTIC_MAJOR=9 KIBANA_USER=admin KIBANA_PASSWORD='change-me' ./easyELKnginx.sh
```

After install, check services:

```bash
systemctl status elasticsearch
systemctl status kibana
systemctl status logstash
```

Kibana is exposed through the selected reverse proxy on port `80`.

## Option 3: Install On macOS

macOS has three native install paths.

### Official Elastic Tarballs

This is the most predictable macOS native mode because it downloads Elastic's official archives into `.easy-elk`.

Install:

```bash
./scripts/install.sh --tarball
```

Start:

```bash
.easy-elk/bin/easy-elk-start
```

Status:

```bash
.easy-elk/bin/easy-elk-status
```

Stop:

```bash
.easy-elk/bin/easy-elk-stop
```

Open Kibana:

```text
http://127.0.0.1:5601
```

Choose version or install folder:

```bash
ELASTIC_VERSION=9.4.1 EASY_ELK_HOME="$HOME/easy-elk" ./scripts/install.sh --tarball
```

### Homebrew

Requirements:

- Homebrew

Install:

```bash
./scripts/install.sh --homebrew
```

The script uses `elastic/tap` and starts services with `brew services`.

### MacPorts

Requirements:

- MacPorts

Install:

```bash
./scripts/install.sh --macports
```

MacPorts package availability can vary. If a port is missing, the script reports it and continues.

## Option 4: Test In A Linux Sandbox

Use this when you want to test the standalone Linux installer without touching your machine.

Requirements:

- Vagrant
- VirtualBox, VMware, or another Vagrant provider
- At least 4 GB RAM for the VM

Start the default Ubuntu + Nginx sandbox:

```bash
./scripts/install.sh --sandbox
```

The script tries to detect a Vagrant provider automatically in this order:

1. VirtualBox
2. Parallels
3. VMware Desktop
4. libvirt

Force a provider if needed:

```bash
EASY_ELK_PROVIDER=virtualbox ./scripts/install.sh --sandbox
EASY_ELK_PROVIDER=parallels ./scripts/install.sh --sandbox
EASY_ELK_PROVIDER=vmware_desktop ./scripts/install.sh --sandbox
EASY_ELK_PROVIDER=libvirt ./scripts/install.sh --sandbox
```

Open:

```text
http://127.0.0.1:8080
```

Login:

```text
admin / easyelk
```

Test Apache instead:

```bash
EASY_ELK_PROXY_SCRIPT=easyELKapache.sh ./scripts/install.sh --sandbox
```

Test another distro:

```bash
EASY_ELK_BOX=debian/bookworm64 ./scripts/install.sh --sandbox
EASY_ELK_BOX=rockylinux/9 ./scripts/install.sh --sandbox
EASY_ELK_BOX=opensuse/Leap-15.6.x86_64 ./scripts/install.sh --sandbox
```

Destroy and rebuild after changing distro:

```bash
cd sandbox
vagrant destroy -f
vagrant up
```

## Files

| File | Purpose |
| --- | --- |
| `scripts/install.sh` | Main menu and command router |
| `scripts/elastic_version.sh` | Detects the latest stable Elastic version |
| `easyELKnginx.sh` | Standalone Linux install with Nginx |
| `easyELKapache.sh` | Standalone Linux install with Apache |
| `scripts/install_elk.sh` | Native Linux package installer |
| `scripts/install_macos.sh` | macOS Homebrew/MacPorts/tarball installer |
| `scripts/install_docker.sh` | Docker Compose installer |
| `docker/compose.yml` | Local Docker test stack |
| `sandbox/Vagrantfile` | Linux VM sandbox |

## Notes

- Security is disabled by default for local and sandbox simplicity.
- Review TLS, authentication, firewall rules, and passwords before adapting this for production.
- Elasticsearch can be memory hungry. Use at least 4 GB RAM for VM tests.

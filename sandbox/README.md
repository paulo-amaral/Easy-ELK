# Easy-ELK Sandbox

The sandbox runs the Linux standalone installer inside a clean Vagrant VM.

Use it when you want to test installation on Ubuntu, Debian, Rocky Linux, openSUSE, or another Vagrant box without changing your host machine.

The Linux package installer tracks the configured Elastic major release. By default:

```bash
ELASTIC_MAJOR=9
```

## Requirements

- Vagrant
- VirtualBox, VMware, or another Vagrant provider
- At least 4 GB RAM for the VM

## Default Test

From the repository root:

```bash
./scripts/install.sh --sandbox
```

This starts:

- Ubuntu box: `ubuntu/noble64`
- Proxy: Nginx
- Kibana forwarded to host port `8080`
- Elasticsearch forwarded to host port `9200`

The wrapper detects the Vagrant provider automatically. It checks for:

1. VirtualBox
2. Parallels
3. VMware Desktop
4. libvirt

You can force one:

```bash
EASY_ELK_PROVIDER=virtualbox ./scripts/install.sh --sandbox
EASY_ELK_PROVIDER=parallels ./scripts/install.sh --sandbox
EASY_ELK_PROVIDER=vmware_desktop ./scripts/install.sh --sandbox
EASY_ELK_PROVIDER=libvirt ./scripts/install.sh --sandbox
```

Open Kibana:

```text
http://127.0.0.1:8080
```

Login:

```text
admin / easyelk
```

Check Elasticsearch from your host:

```bash
curl http://127.0.0.1:9200
```

## Run From This Folder

```bash
cd sandbox
vagrant up
```

## Choose Apache Or Nginx

Nginx is the default:

```bash
EASY_ELK_PROXY_SCRIPT=easyELKnginx.sh vagrant up
```

Apache:

```bash
EASY_ELK_PROXY_SCRIPT=easyELKapache.sh vagrant up
```

From the repo root:

```bash
EASY_ELK_PROXY_SCRIPT=easyELKapache.sh ./scripts/install.sh --sandbox
```

## Choose A Distro

Ubuntu default:

```bash
EASY_ELK_BOX=ubuntu/noble64 vagrant up
```

Debian:

```bash
EASY_ELK_BOX=debian/bookworm64 vagrant up
```

Rocky Linux:

```bash
EASY_ELK_BOX=rockylinux/9 vagrant up
```

openSUSE:

```bash
EASY_ELK_BOX=opensuse/Leap-15.6.x86_64 vagrant up
```

## Rebuild After Changes

If you change distro, proxy, or want a clean install:

```bash
vagrant destroy -f
vagrant up
```

## Useful Commands

SSH into the VM:

```bash
vagrant ssh
```

Check services inside the VM:

```bash
systemctl status elasticsearch
systemctl status kibana
systemctl status logstash
```

Stop the VM:

```bash
vagrant halt
```

Delete the VM:

```bash
vagrant destroy -f
```

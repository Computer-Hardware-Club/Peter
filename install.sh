#!/usr/bin/env bash
# Install or update the workshop platform on an audited Ubuntu 24.04 amd64 host.
set -euo pipefail
umask 022
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if [[ $EUID != 0 || $(dpkg --print-architecture) != amd64 ]]; then
    echo 'Run as root on the audited amd64 host.' >&2
    exit 1
fi
. /etc/os-release
if [[ $ID != ubuntu || $VERSION_ID != 24.04 || ! -c /dev/kvm ]]; then
    echo 'Ubuntu 24.04 and /dev/kvm are required.' >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y incus qemu-system-x86 ovmf docker.io docker-compose-v2 nftables curl openssh-client

install -d -m 0755 /opt/workshop /opt/workshop/{infra,templates,docs,guest,portal-reset/extensions}
install -d -m 0700 /var/lib/workshop /etc/workshop
# A checked-out copy may already be in the installation directory.
if [[ $(pwd -P) != /opt/workshop ]]; then
    install -m 0755 workshop install.sh build-template.sh /opt/workshop/
    install -m 0644 workshop_templates.py /opt/workshop/
    install -m 0644 infra/*.* /opt/workshop/infra/
    install -d -m 0755 /opt/workshop/infra/guacd
    install -m 0644 infra/guacd/{Dockerfile,terminal.patch} /opt/workshop/infra/guacd/
    chmod 0755 /opt/workshop/infra/db-init.sh
    install -m 0644 templates/*.json /opt/workshop/templates/
    for manifest in templates/*/workshop.json; do
        [[ -f $manifest ]] || continue
        install -D -m 0644 "$manifest" "/opt/workshop/$manifest"
        init_script="${manifest%/*}/init.sh"
        if [[ -f $init_script ]]; then
            install -D -m 0644 "$init_script" "/opt/workshop/$init_script"
        fi
    done
    install -m 0644 guest/workshop-login.sh /opt/workshop/guest/
    install -m 0755 guest/chcfetch /opt/workshop/guest/
    install -m 0644 portal-reset/{guac-manifest.json,reset.js,reset.css,clipboard.js} /opt/workshop/portal-reset/
    install -m 0644 README.md /opt/workshop/
    install -m 0644 docs/*.md /opt/workshop/docs/
fi
(
    cd /opt/workshop/portal-reset
    python3 -m zipfile -c extensions/workshop-reset.jar.new guac-manifest.json reset.js reset.css clipboard.js
    mv -f extensions/workshop-reset.jar.new extensions/workshop-reset.jar
)
rm -f /opt/workshop/templates/ubuntu-basics.json
ln -sfn /opt/workshop/workshop /usr/local/sbin/workshop

nft -c -f /opt/workshop/infra/firewall.nft
install -m 0644 infra/workshop-*.service /etc/systemd/system/
for service in incus docker; do
    install -D -m 0644 infra/require-firewall.conf "/etc/systemd/system/${service}.service.d/20-workshop-firewall.conf"
done
systemctl daemon-reload
systemctl enable --now workshop-firewall.service
systemctl reload workshop-firewall.service
systemctl enable --now incus.socket incus-startup.service docker.service

if ! incus storage show workshop >/dev/null 2>&1; then
    incus storage create workshop dir
fi
if [[ $(incus storage list --format csv | awk -F, '$1 == "workshop" {print $2}') != dir ]]; then
    echo 'The reserved workshop storage pool must use the dir driver.' >&2
    exit 1
fi
if ! incus project show workshop >/dev/null 2>&1; then
    incus project create workshop -c features.networks=false
fi
incus project set workshop limits.containers=0 limits.virtual-machines=4 limits.cpu=8 limits.memory=8GiB
if ! incus --project workshop profile show workshop-vm >/dev/null 2>&1; then
    incus --project workshop profile create workshop-vm
    incus --project workshop profile device add workshop-vm root disk path=/ pool=workshop size=10GiB
fi
incus --project workshop profile set workshop-vm limits.cpu=2 limits.memory=2GiB \
    boot.autostart=true limits.disk.priority=2 security.guestapi=false security.agent.metrics=false
if ! incus --project workshop image info debian-trixie-base >/dev/null 2>&1; then
    incus image copy images:debian/13/cloud local: --vm --project workshop --alias debian-trixie-base
fi
if ! incus --project workshop image info debian-trixie >/dev/null 2>&1; then
    /opt/workshop/build-template.sh debian-trixie
fi

if [[ ! -s /var/lib/workshop/stack.env ]]; then
    if [[ ! -e /etc/workshop/portal-url ]]; then
        printf '%s\n' 'http://127.0.0.1:18080/' > /etc/workshop/portal-url
    fi
    if docker volume inspect workshop_database >/dev/null 2>&1; then
        echo 'Restore stack.env before starting the existing workshop database.' >&2
        exit 1
    fi
    (umask 077
    python3 - > /var/lib/workshop/stack.env.tmp <<'PY'
import secrets
for name in ("POSTGRES_PASSWORD", "POSTGRESQL_PASSWORD"):
    print(f"{name}={secrets.token_hex(32)}")
PY
    )
    mv /var/lib/workshop/stack.env.tmp /var/lib/workshop/stack.env
fi
# The schema contains no secrets and must be readable by the PostgreSQL user in the container.
if [[ ! -s /var/lib/workshop/schema.sql ]]; then
    schema=$(mktemp /var/lib/workshop/.schema-XXXXXXXX)
    trap 'rm -f -- "$schema"' EXIT
    docker run --rm --network none guacamole/guacamole:1.6.0 /opt/guacamole/bin/initdb.sh --postgresql > "$schema"
    test -s "$schema"
    install -m 0644 "$schema" /var/lib/workshop/schema.sql
    rm -f -- "$schema"
    trap - EXIT
fi
docker compose -f /opt/workshop/infra/compose.yaml \
    --env-file /var/lib/workshop/stack.env build guacd
systemctl enable workshop-portal.service
systemctl restart workshop-portal.service

if ! command -v cloudflared >/dev/null; then
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
    chmod 0644 /usr/share/keyrings/cloudflare-main.gpg
    printf '%s\n' 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
        > /etc/apt/sources.list.d/cloudflared.list
    apt-get update
    apt-get install -y cloudflared
fi
workshop status

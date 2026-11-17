#!/usr/bin/env bash
# Install or update the workshop platform on an audited Ubuntu 24.04 amd64 host.
set -euo pipefail
umask 022
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source_dir=$(pwd -P)
active=/opt/workshop
previous=/opt/.workshop-previous
state=/var/lib/workshop
releases=$state/releases
staged=$releases/staged
extension=(guac-manifest.json reset.js reset.css clipboard.js)

usage() {
    echo 'Usage: install.sh [--stage [--base REF] | --apply-portal | --rollback-portal]' >&2
    exit 2
}
mode=${1:---stage}
case "$mode" in
    --stage)
        if (( $# > 1 )); then
            [[ $# == 3 && $2 == --base && -n $3 ]] || usage
            base=$3
        fi ;;
    --apply-portal|--rollback-portal) [[ $# == 1 ]] || usage ;;
    *) usage ;;
esac
if [[ $EUID != 0 ]]; then
    echo 'Run as root on the audited host.' >&2
    exit 1
fi

mkdir -p -m 0700 "$state" "$releases"
exec 8>>"$releases/lock"
flock -x 8

if [[ $mode == --stage ]]; then
    pending=$(mktemp -d "$releases/.staging.XXXXXXXX")
    trap 'rm -rf -- "$pending"' EXIT
    install -d -m 0755 "$pending/files"
    files=(install.sh install-dashboard.sh workshop workshop_templates.py build-template.sh README.md
           infra templates docs guest portal-reset dashboard)
    # Copy source, excluding checkout artifacts and generated extensions.
    tar --exclude=.DS_Store --exclude=__pycache__ --exclude=extensions --exclude='*.test.js' \
        -cf - "${files[@]}" | tar -xf - -C "$pending/files"
    install -d -m 0755 "$pending/files/portal-reset/extensions"
    (
        cd "$pending/files/portal-reset"
        python3 -m zipfile -c extensions/workshop-reset.jar "${extension[@]}"
    )
    if [[ -n ${base:-} ]]; then
        install -d -m 0755 "$pending/base"
        git -c "safe.directory=$source_dir" archive "$base" | tar -xf - -C "$pending/base"
    fi
    chown -R root:root "$pending"
    chmod -R go-w "$pending"
    rm -rf -- "$staged"
    mv -- "$pending" "$staged"
    echo "Release staged at $staged. Run install.sh --apply-portal between workshops."
    exit
fi

# This is the same lock used by the workshop CLI. Hold it through activation
# and health checks so a workshop cannot start during a release change.
exec 9>>"$state/lock"
flock -x 9
if [[ -e $state/event.json ]]; then
    echo 'End the workshop before changing the active release.' >&2
    exit 1
fi
. /etc/os-release
if [[ $ID != ubuntu || $VERSION_ID != 24.04 || ! -c /dev/kvm || $(dpkg --print-architecture) != amd64 ]]; then
    echo 'Ubuntu 24.04 amd64 and /dev/kvm are required.' >&2
    exit 1
fi

compose_at() (
    cd "$1/infra"
    shift
    docker compose --env-file "$state/stack.env" "$@"
)
portal=workshop-portal.service

# The candidate and active directory live on the same filesystem. Exchange them
# in one operation so the paths used at boot always point to a complete release.
exchange() {
    python3 - "$1" "$2" <<'PYCODE'
import ctypes
import os
import sys

libc = ctypes.CDLL(None, use_errno=True)
if libc.renameat2(-100, os.fsencode(sys.argv[1]), -100, os.fsencode(sys.argv[2]), 2):
    raise OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno()))
PYCODE
}

stop_portal() {
    systemctl stop "$portal"
    compose_at "$active" stop
    # Docker retains the explicit stop across reboots. Keep systemd from
    # bringing the stack up while the tree and image are being switched.
    systemctl disable "$portal"
}

start_portal() {
    # Force recreation so directory bind mounts use the activated files even
    # when Compose sees no change in the path or configuration.
    compose_at "$active" up -d --force-recreate --wait --wait-timeout 120
    systemctl enable --now "$portal"
}

if [[ $mode == --rollback-portal ]]; then
    [[ -s $previous/.guacd-image ]] || { echo 'No previous installation to restore.' >&2; exit 1; }
    stop_portal
    read -r image_id image_tag < "$previous/.guacd-image"
    docker image tag "$image_id" "$image_tag"
    exchange "$active" "$previous"
    if [[ ! -f $active/infra/workshop-recordings.timer ]]; then
        systemctl disable --now workshop-recordings.timer 2>/dev/null || ! systemctl is-active --quiet workshop-recordings.timer
    fi
    systemctl reload workshop-firewall.service
    start_portal
    exit
fi

[[ -d $staged/files ]] || { echo 'Run install.sh to stage a release first.' >&2; exit 1; }
if [[ -L $active || ( -e $active && ! -f $active/infra/compose.yaml ) ]]; then
    echo "Review the existing installation at $active before applying." >&2
    exit 1
fi

fresh=false
if [[ ! -d $active || -e $releases/bootstrap-pending ]]; then
    fresh=true
fi
candidate=$(mktemp -d /opt/.workshop-next.XXXXXXXX)
trap 'rm -rf -- "$candidate"' EXIT
if ! $fresh; then
    cp -a "$active/." "$candidate/"
    baseline=$active/.release-base
    [[ ! -d $staged/base ]] || baseline=$staged/base
    python3 "$staged/files/infra/prepare-release.py" "$staged/files" "$baseline" "$candidate"
    # Existing units, drop-ins, portal credentials and VPN state live outside
    # this tree. Leave those configured by the operator in place.
    nft -c -f "$candidate/infra/firewall.nft"
    compose_at "$candidate" config --quiet
    incoming_image=$(compose_at "$candidate" config --images guacd)
    # Build to a separate tag while the old service, paths and image still
    # form a working release. Honor the site's Compose build configuration.
    (
        cd "$candidate/infra"
        build_files=(-f compose.yaml)
        for override in compose.override.yaml compose.override.yml; do
            if [[ -f $override ]]; then
                build_files+=(-f "$override")
                break
            fi
        done
        printf 'services:\n  guacd:\n    image: peter-guacd:pending-installation\n' > .release-build.yaml
        docker compose --env-file "$state/stack.env" "${build_files[@]}" -f .release-build.yaml build guacd
        rm -f .release-build.yaml
    )
    rm -f -- "$candidate/.guacd-image"
    image=$(docker inspect --format '{{.Image}} {{.Config.Image}}' workshop-guacd-1)
    read -r image_id image_tag <<< "$image"
    docker image tag "$image_id" peter-guacd:previous-installation
    printf '%s %s\n' "$image_id" "$image_tag" > "$active/.guacd-image"
    stop_portal
    rm -rf -- "$previous"
    mv -- "$candidate" "$previous"
    exchange "$active" "$previous"
    echo "Previous release saved at $previous. Use --rollback-portal if activation fails."
    docker image tag peter-guacd:pending-installation "$incoming_image"
else
    cp -a "$staged/files/." "$candidate/"
    cp -a "$staged/files" "$candidate/.release-base"
    chmod 0755 "$candidate"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-upgrade incus qemu-system-x86 ovmf docker.io docker-compose-v2 nftables curl openssh-client
    if [[ ! -d $active ]]; then
        touch "$releases/bootstrap-pending"
        mv -- "$candidate" "$active"
    fi
fi

install -d -m 0700 /etc/workshop
ln -sfn "$active/workshop" /usr/local/sbin/workshop
nft -c -f "$active/infra/firewall.nft"
for unit in workshop-{firewall,portal,recordings}.service workshop-recordings.timer; do
    target=/etc/systemd/system/$unit
    [[ -e $target || -L $target ]] || install -m 0644 "$active/infra/$unit" "$target"
done
if $fresh; then
    for service in incus docker; do
        install -D -m 0644 "$active/infra/require-firewall.conf" "/etc/systemd/system/${service}.service.d/20-workshop-firewall.conf"
    done
fi
systemctl daemon-reload
systemctl enable --now workshop-firewall.service
systemctl reload workshop-firewall.service

if $fresh; then
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
    if ! command -v cloudflared >/dev/null; then
        curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
        chmod 0644 /usr/share/keyrings/cloudflare-main.gpg
        printf '%s\n' 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
            > /etc/apt/sources.list.d/cloudflared.list
        apt-get update
        apt-get install -y cloudflared
    fi
fi

if $fresh; then
    compose_at "$active" build guacd
fi
start_portal
systemctl enable --now workshop-recordings.timer
rm -f -- "$releases/bootstrap-pending"
"$active/workshop" status

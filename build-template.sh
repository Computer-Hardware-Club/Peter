#!/usr/bin/env bash
# Build a Debian VM image without giving the builder a network interface.
set -euo pipefail
umask 077
if [[ $EUID != 0 || $# -lt 1 || ! $1 =~ ^[a-z][a-z0-9-]{0,23}$ || $1 == debian-trixie-base ]]; then
    echo 'Usage: sudo build-template.sh OUTPUT_ALIAS [additional-debian-packages...]' >&2
    exit 2
fi
alias_name=$1
shift
for package in "$@"; do
    if [[ ! $package =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then
        echo "Invalid Debian package name: $package" >&2
        exit 2
    fi
done

exec 9>/var/lib/workshop/lock
flock -n 9 || { echo 'Another workshop command is running.' >&2; exit 1; }
if [[ -e /var/lib/workshop/event.json ]]; then
    echo 'Destroy the active event before building an image.' >&2
    exit 1
fi

incus=(incus --force-local --project workshop)
tmp=$(mktemp -d /run/workshop-build-XXXXXXXX)
builder="ws-build-${tmp##*-}"
created=false
cleanup() {
    if $created; then
        "${incus[@]}" delete "$builder" --force || true
    fi
    rm -rf -- "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"${incus[@]}" init debian-trixie-base "$builder" --vm --profile workshop-vm \
    -c boot.autostart=false </dev/null
created=true
"${incus[@]}" start "$builder"
timeout 180 bash -c '
    until "$@" exec "$0" -- true </dev/null 2>/dev/null; do sleep 2; done
' "$builder" "${incus[@]}" </dev/null
timeout 180 "${incus[@]}" exec "$builder" -- cloud-init status --wait </dev/null

# Use the base image's Debian archive key and a separate APT cache on the host.
chmod 0755 "$tmp"
mkdir -m 0755 "$tmp/archives" "$tmp/lists" "$tmp/empty"
"${incus[@]}" exec "$builder" -- cat /var/lib/dpkg/status </dev/null > "$tmp/status"
"${incus[@]}" exec "$builder" -- cat /usr/share/keyrings/debian-archive-keyring.gpg </dev/null > "$tmp/debian.gpg"
chmod 0644 "$tmp/status" "$tmp/debian.gpg"
cat > "$tmp/debian.list" <<EOF
deb [signed-by=$tmp/debian.gpg] https://deb.debian.org/debian trixie main
deb [signed-by=$tmp/debian.gpg] https://deb.debian.org/debian trixie-updates main
deb [signed-by=$tmp/debian.gpg] https://security.debian.org/debian-security trixie-security main
EOF
chmod 0644 "$tmp/debian.list"
apt=(apt-get -o "Dir::Etc::sourcelist=$tmp/debian.list" -o "Dir::Etc::sourceparts=$tmp/empty"
     -o "Dir::Etc::parts=$tmp/empty" -o "Dir::State::lists=$tmp/lists"
     -o "Dir::State::status=$tmp/status" -o "Dir::Cache::archives=$tmp/archives"
     -o "Dir::Cache::pkgcache=$tmp/pkgcache.bin" -o "Dir::Cache::srcpkgcache=$tmp/srcpkgcache.bin")
"${apt[@]}" update
"${apt[@]}" --download-only --no-install-recommends -y install openssh-server sudo "$@"

# Incus exec uses the VM agent over vsock and needs no guest networking.
"${incus[@]}" exec "$builder" -- mkdir -p /run/workshop-packages </dev/null
(cd "$tmp/archives" && tar -cf - -- ./*.deb) | \
    "${incus[@]}" exec "$builder" --mode non-interactive -- tar -xf - -C /run/workshop-packages
"${incus[@]}" exec "$builder" -- bash -s <<'GUEST'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=- \
    --no-install-recommends -y install /run/workshop-packages/*.deb
systemctl enable ssh.service
apt-get clean
cloud-init clean --logs --machine-id --seed --configs network ssh_config
rm -f /etc/ssh/ssh_host_*
GUEST
"${incus[@]}" stop "$builder" --timeout 60
"${incus[@]}" publish "$builder" --alias "$alias_name" --reuse \
    description="Debian 13 workshop VM ($alias_name)"

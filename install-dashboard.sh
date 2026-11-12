#!/usr/bin/env bash
# Install the dashboard after the workshop platform has been installed.
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
usage() {
    echo 'Usage: sudo ./install-dashboard.sh [LAN_IP/PREFIX | --tailscale HOST LOGIN]' >&2
    exit 2
}
if [[ $EUID != 0 || ! -x /opt/workshop/workshop ]]; then
    usage
fi
lan=
tail_args=
if [[ ${1:-} == --tailscale ]]; then
    if [[ $# != 3 || ! $2 =~ ^[a-z0-9][a-z0-9.-]*\.ts\.net$ ||
          ! $3 =~ ^[A-Za-z0-9_.+-]+@[A-Za-z0-9_.+-]+$ ]]; then
        usage
    fi
    tail_args="--tailscale $2 $3"
else
    [[ $# -le 1 ]] || usage
    lan=${1:-}
fi
ip=$(python3 - "$lan" <<'PY'
import ipaddress
import sys
if sys.argv[1]:
    address = ipaddress.IPv4Interface(sys.argv[1])
    if not address.ip.is_private or address.ip.is_loopback or address.network.prefixlen < 16:
        raise SystemExit("Use Peter's private LAN IPv4 address and subnet.")
    print(address.ip)
else:
    print("127.0.0.1")
PY
)
if [[ -n $lan ]]; then
    lan=$(python3 -c 'import ipaddress,sys; print(ipaddress.IPv4Interface(sys.argv[1]))' "$lan")
fi

if ! id workshop-dashboard >/dev/null 2>&1; then
    useradd --system --user-group --no-create-home --shell /usr/sbin/nologin workshop-dashboard
fi
install -d -m 0755 /opt/workshop/dashboard/vendor
install -d -m 0700 /etc/workshop/dashboard
if [[ $(pwd -P) != /opt/workshop ]]; then
    install -m 0644 dashboard/{host.py,server.py,mirror.py,index.html,app.js,mirror.js,style.css} /opt/workshop/dashboard/
    install -m 0644 dashboard/vendor/* /opt/workshop/dashboard/vendor/
    install -m 0755 install-dashboard.sh /opt/workshop/
fi
install -m 0644 infra/workshop-dashboard{.service,-host.socket,-host@.service} /etc/systemd/system/
guard_dropin=/etc/systemd/system/workshop-dashboard.service.d/tailscale.conf
if [[ -n $tail_args ]]; then
    if [[ $(pwd -P) != /opt/workshop ]]; then
        install -D -m 0644 infra/dashboard-serve.nft /opt/workshop/infra/dashboard-serve.nft
    fi
    install -m 0644 infra/workshop-dashboard-serve-guard.service /etc/systemd/system/
    nft -c -f /opt/workshop/infra/dashboard-serve.nft
    install -d -m 0755 "${guard_dropin%/*}"
    cat > "$guard_dropin" <<'UNIT'
[Unit]
Requires=workshop-dashboard-serve-guard.service
After=workshop-dashboard-serve-guard.service
UNIT
elif [[ -f $guard_dropin ]]; then
    unlink "$guard_dropin"
fi
cd /etc/workshop/dashboard
if [[ ! -s officer-password ]]; then
    python3 -c 'import secrets; print(secrets.token_urlsafe(24))' > officer-password
fi
if [[ ! -s tls.crt || ! -s tls.key ]] ||
   { [[ -z $tail_args ]] && { [[ ! -s lan-ca.crt || ! -s tls-address || $(cat tls-address) != "$ip" ]] ||
       ! openssl x509 -checkend 2592000 -noout -in tls.crt >/dev/null; }; }; then
    temp=$(mktemp -d)
    trap 'rm -rf -- "$temp"' EXIT
    openssl req -new -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc -days 397 \
        -subj '/CN=Peter Workshop Dashboard CA' -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign' -keyout "$temp/ca.key" -out "$temp/ca.crt"
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -noenc \
        -subj "/CN=$ip" -keyout "$temp/tls.key" -out "$temp/tls.csr"
    printf '%s\n' "subjectAltName=IP:$ip" 'basicConstraints=critical,CA:FALSE' \
        'keyUsage=critical,digitalSignature' 'extendedKeyUsage=serverAuth' > "$temp/server.cnf"
    openssl x509 -req -in "$temp/tls.csr" -CA "$temp/ca.crt" -CAkey "$temp/ca.key" \
        -CAcreateserial -extfile "$temp/server.cnf" -days 365 -out "$temp/tls.crt"
    install -m 0600 "$temp/tls.key" tls.key
    install -m 0644 "$temp/tls.crt" tls.crt
    install -m 0644 "$temp/ca.crt" lan-ca.crt
    printf '%s\n' "$ip" > tls-address
fi
printf 'DASHBOARD_LAN_ARGS="%s"\nDASHBOARD_TAILSCALE_ARGS="%s"\n' "${lan:+--lan $lan}" "$tail_args" > listen.env

systemctl daemon-reload
if [[ -n $tail_args ]]; then
    systemctl reload-or-restart workshop-dashboard-serve-guard.service
fi
systemctl enable --now workshop-dashboard-host.socket
systemctl enable workshop-dashboard.service
systemctl restart workshop-dashboard.service

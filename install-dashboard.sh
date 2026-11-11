#!/usr/bin/env bash
# Install the dashboard after the workshop platform has been installed.
set -euo pipefail
umask 077
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
if [[ $EUID != 0 || $# -gt 1 || ! -x /opt/workshop/workshop ]]; then
    echo 'Usage: sudo ./install-dashboard.sh [LAN_IP/PREFIX]' >&2
    exit 2
fi
lan=${1:-}
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
install -d -m 0755 /opt/workshop/dashboard
install -d -m 0700 /etc/workshop/dashboard
if [[ $(pwd -P) != /opt/workshop ]]; then
    install -m 0644 dashboard/{host.py,server.py,index.html,app.js,style.css} /opt/workshop/dashboard/
    install -m 0755 install-dashboard.sh /opt/workshop/
fi
install -m 0644 infra/workshop-dashboard{.service,-host.socket,-host@.service} /etc/systemd/system/
cd /etc/workshop/dashboard
if [[ ! -s officer-password ]]; then
    python3 -c 'import secrets; print(secrets.token_urlsafe(24))' > officer-password
fi
if [[ ! -s smtp.json ]]; then
    printf '{}\n' > smtp.json
fi
if [[ ! -s tls.crt || ! -s tls.key || ! -s lan-ca.crt || ! -s tls-address ||
      $(cat tls-address) != "$ip" ]] || ! openssl x509 -checkend 2592000 -noout -in tls.crt >/dev/null; then
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
if [[ -n $lan ]]; then
    printf 'DASHBOARD_LAN_ARGS="--lan %s"\n' "$lan" > listen.env
else
    printf 'DASHBOARD_LAN_ARGS=""\n' > listen.env
fi

systemctl daemon-reload
systemctl enable --now workshop-dashboard-host.socket
systemctl enable workshop-dashboard.service
systemctl restart workshop-dashboard.service

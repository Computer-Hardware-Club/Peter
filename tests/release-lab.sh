#!/usr/bin/env bash
# Run the non-fresh installer on a disposable GitHub-hosted VM.
set -euo pipefail

if [[ $EUID != 0 || ${GITHUB_ACTIONS:-} != true || ${RUNNER_ENVIRONMENT:-} != github-hosted ]]; then
    echo 'This test needs its own disposable GitHub-hosted runner.' >&2
    exit 2
fi
active=/opt/workshop
state=/var/lib/workshop
for path in "$active" /opt/.workshop-previous "$state" /etc/workshop /usr/local/sbin/workshop \
            /etc/systemd/system/workshop-*; do
    if [[ -e $path || -L $path ]]; then
        echo "Refusing to use existing installation at $path." >&2
        exit 2
    fi
done
if [[ -n $(docker ps -a -q --filter label=com.docker.compose.project=workshop) ]] ||
   docker volume inspect workshop_database >/dev/null 2>&1; then
    echo 'Refusing to use an existing workshop Compose project.' >&2
    exit 2
fi

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
lab=$(mktemp -d "${1:?Pass the runner temporary directory}/peter-release.XXXXXXXX")
source=$lab/source
mkdir "$source"
git -C "$repo" -c "safe.directory=$repo" archive HEAD | tar -xf - -C "$source"
trap 'if (( $? != 0 )); then
    journalctl --no-pager -n 80 -u workshop-dashboard.service -u workshop-portal.service || true
    docker logs --tail 40 workshop-web-1 || true
fi' EXIT

# These paths and units belong only to this runner VM. The update path
# checks for a KVM device but never opens it on a pre-existing installation.
if [[ ! -c /dev/kvm ]]; then
    ln -s /dev/null /dev/kvm
fi
compose=(docker compose --env-file "$state/stack.env" -f "$active/infra/compose.yaml"
         -f "$active/infra/compose.override.yaml")
installer=(bash "$source/install.sh")
stage=$state/releases/staged/files
host=release-lab.example.ts.net
login=officer@example.test
officer_password=disposable-release-lab-password
dashboard=(curl --silent --show-error --max-time 5 -H "Host: $host" -H "Tailscale-User-Login: $login")
dashboard_url=http://127.0.0.1:18090

sql() {
    "${compose[@]}" exec -T db sh -ec 'PGPASSWORD=$POSTGRES_PASSWORD exec psql -XqAt -h 127.0.0.1 -U postgres -d guacamole -v ON_ERROR_STOP=1 -c "$1"' sh "$1"
}

set_version() {
    local version=$1
    sed -i "/PETER_RELEASE_FIXTURE:/s/: .*/: $version/" "$source/infra/compose.yaml"
    sed -i "/X-Peter-Release-Fixture/s/\(, \).*/\1\"$version\")/" "$source/dashboard/server.py"
    printf 'FROM peter-guacd:review-check\nLABEL peter.release.fixture=%s\n' "$version" > "$source/infra/guacd/Dockerfile"
    printf '\n/* Release activation fixture %s. */\n' "$version" >> "$source/portal-reset/reset.js"
}

report_dashboard_version() {
    "${dashboard[@]}" --fail --retry 15 --retry-connrefused --retry-delay 1 -D - -o /dev/null "$dashboard_url/" |
        tr -d '\r' | sed -n 's/^X-Peter-Release-Fixture: //p'
}

sign_in() {
    "${dashboard[@]}" --fail -D - -o /dev/null -H "Origin: https://$host" \
        -H 'Content-Type: application/json' -d "{\"password\":\"$officer_password\"}" "$dashboard_url/api/login" |
        sed -n 's/^Set-Cookie: \([^;]*\);.*/\1/p'
}

configuration() {
    sha256sum "$active/infra/compose.override.yaml" "$state/stack.env" \
        /etc/workshop/dashboard/{listen.env,officer-password,tls.crt,tls.key} \
        /etc/systemd/system/workshop-{portal,firewall,dashboard,dashboard-serve-guard,recordings}.service \
        /etc/systemd/system/workshop-{dashboard-host.socket,dashboard-host@.service,recordings.timer} \
        /etc/systemd/system/workshop-dashboard.service.d/{tailscale.conf,release-lab.conf}
}

runtime_identity() {
    sha256sum "$active"/{infra/compose.yaml,dashboard/server.py,portal-reset/extensions/workshop-reset.jar}
    docker inspect --format '{{.Id}} {{.Image}} {{.State.StartedAt}}' workshop-{db,guacd,web}-1
    docker image inspect --format '{{.Id}}' peter-guacd:release-lab
    systemctl show --property=InvocationID --value workshop-portal.service workshop-dashboard.service
}

verify_release() {
    local version=$1 image
    cmp "$lab/$version.compose" "$active/infra/compose.yaml"
    cmp "$lab/$version.reset" <(unzip -p "$active/portal-reset/extensions/workshop-reset.jar" reset.js)
    docker exec workshop-web-1 cat /etc/guacamole/extensions/workshop-reset.jar > "$lab/mounted.jar"
    cmp "$active/portal-reset/extensions/workshop-reset.jar" "$lab/mounted.jar"
    image=$(docker inspect --format '{{.Image}}' workshop-guacd-1)
    [[ $image == "$(docker image inspect --format '{{.Id}}' peter-guacd:release-lab)" ]]
    [[ $(docker image inspect --format '{{index .Config.Labels "peter.release.fixture"}}' "$image") == "$version" ]]
    [[ $(docker exec workshop-guacd-1 printenv PETER_RELEASE_FIXTURE) == "$version" ]]
    [[ $(docker exec workshop-web-1 printenv API_SESSION_TIMEOUT) == 41 ]]
    [[ $(report_dashboard_version) == "$version" ]]
    systemctl is-enabled --quiet workshop-portal.service
    systemctl is-enabled --quiet workshop-dashboard.service
    systemctl is-active --quiet workshop-portal.service
    systemctl is-active --quiet workshop-dashboard.service
    configuration | diff -u "$lab/configuration" -
    docker volume inspect workshop_database | diff -u "$lab/database" -
    [[ $(sql 'SELECT value FROM release_fixture') == retained ]]
    [[ $(docker exec workshop-db-1 sh -ec '
        PGPASSWORD=$APP_DB_PASSWORD exec psql -XqAt -h 127.0.0.1 -U guacamole -d guacamole -v ON_ERROR_STOP=1 \
            -c "SELECT value FROM release_fixture"') == retained ]]
    printf 'Verified %s release in the portal containers and dashboard (guacd %s).\n' "$version" "$image"
}

# Seed an installed release and its merge base from the real staging path.
sed -i '/XDG_CACHE_HOME: /a\      PETER_RELEASE_FIXTURE: before' "$source/infra/compose.yaml"
sed -i '/self.send_response(status)/a\        self.send_header("X-Peter-Release-Fixture", "before")' "$source/dashboard/server.py"
set_version before
"${installer[@]}" --stage
cp -a "$stage" "$active"
cp -a "$stage" "$active/.release-base"
cp "$source/infra/compose.yaml" "$lab/before.compose"
cp "$source/portal-reset/reset.js" "$lab/before.reset"
cat > "$active/infra/compose.override.yaml" <<'YAML'
services:
  web:
    environment:
      API_SESSION_TIMEOUT: "41"
  guacd:
    image: peter-guacd:release-lab
YAML
(umask 077
printf 'POSTGRES_PASSWORD=release-admin-password\nPOSTGRESQL_PASSWORD=release-app-password\n' > "$state/stack.env"
)
docker run --rm --network none guacamole/guacamole:1.6.0 /opt/guacamole/bin/initdb.sh --postgresql > "$state/schema.sql"
install -m 0644 "$active"/infra/workshop-{portal,firewall,recordings}.service "$active"/infra/workshop-recordings.timer /etc/systemd/system/
install -d -m 0700 /etc/workshop/dashboard
install -m 0600 /dev/null /etc/workshop/dashboard/officer-password
printf '%s\n' "$officer_password" > /etc/workshop/dashboard/officer-password
install -d /etc/systemd/system/workshop-dashboard.service.d
cat > /etc/systemd/system/workshop-dashboard.service.d/release-lab.conf <<'UNIT'
[Service]
Restart=no
ExecStartPre=+/usr/bin/test ! -e /var/lib/workshop/fail-dashboard
UNIT
bash "$active/install-dashboard.sh" --tailscale "$host" "$login"
"${compose[@]}" build guacd
systemctl enable --now workshop-firewall.service workshop-portal.service workshop-recordings.timer
sql "CREATE TABLE release_fixture (value text); INSERT INTO release_fixture VALUES ('retained'); GRANT SELECT ON release_fixture TO guacamole;"
configuration > "$lab/configuration"
docker volume inspect workshop_database > "$lab/database"
verify_release before
before_image=$(docker inspect --format '{{.Image}}' workshop-guacd-1)

cookie=$(sign_in)
"${dashboard[@]}" --fail -b "$cookie" "$dashboard_url/api/state" > /dev/null

printf '{}\n' > "$state/event.json"
runtime_identity > "$lab/runtime"
set_version after
cp "$source/infra/compose.yaml" "$lab/after.compose"
cp "$source/portal-reset/reset.js" "$lab/after.reset"
"${installer[@]}" --stage
for option in --apply-portal --rollback-portal; do
    if output=$("${installer[@]}" "$option" 2>&1); then
        echo "$option unexpectedly succeeded during an event." >&2
        exit 1
    fi
    grep -F 'End the workshop before changing the active release.' <<< "$output"
done
runtime_identity | diff -u "$lab/runtime" -
verify_release before
rm "$state/event.json"

# Make the dashboard refuse to start after the tree/image switch, then
# clear the fault and use the documented rollback to recover both services.
touch "$state/fail-dashboard"
if "${installer[@]}" --apply-portal; then
    echo 'Apply unexpectedly succeeded despite the dashboard startup failure.' >&2
    exit 1
fi
cmp "$lab/after.compose" "$active/infra/compose.yaml"
systemctl is-failed --quiet workshop-dashboard.service
rm "$state/fail-dashboard"
"${installer[@]}" --rollback-portal
verify_release before

cookie=$(sign_in)
"${dashboard[@]}" --fail -b "$cookie" "$dashboard_url/api/state" > /dev/null
"${installer[@]}" --apply-portal
verify_release after
[[ $(docker inspect --format '{{.Image}}' workshop-guacd-1) != "$before_image" ]]
[[ $("${dashboard[@]}" -b "$cookie" -o /dev/null -w '%{http_code}' "$dashboard_url/api/state") == 401 ]]
"${dashboard[@]}" --fail -b "$(sign_in)" "$dashboard_url/api/state" > /dev/null

"${installer[@]}" --rollback-portal
verify_release before
[[ $(docker inspect --format '{{.Image}}' workshop-guacd-1) == "$before_image" ]]
systemctl restart workshop-portal.service workshop-dashboard.service
verify_release before

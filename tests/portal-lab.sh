#!/usr/bin/env bash
# A disposable portal using the real PostgreSQL, Guacamole, guacd and SSH path.
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
action=${1:?Usage: portal-lab.sh ACTION LAB_DIR}
lab_dir=${2:-${PETER_LAB_DIR:?A disposable lab directory is required}}
mkdir -p "$lab_dir"
cd -- "$lab_dir"
export PETER_LAB_PORT=${PETER_LAB_PORT:-18081}
export PETER_LAB_GUACD_IMAGE=${PETER_LAB_GUACD_IMAGE:-peter-guacd:review-check}
compose=(docker compose -p peter-portal-test -f active/infra/compose.yaml)

sql() {
    "${compose[@]}" exec -T db psql -XqAt -U postgres --dbname guacamole -v ON_ERROR_STOP=1 -c "$1"
}
guest_file() {
    "${compose[@]}" exec -T guest test -f "/tmp/peter-$1"
}
active_assets() {
    docker inspect --format '{{.Id}} {{.Image}}' $("${compose[@]}" ps -q) | sort
    docker image inspect --format '{{.Id}}' "$PETER_LAB_GUACD_IMAGE"
    sha256sum active/infra/compose.yaml active/portal-reset/extensions/workshop-reset.jar
    "${compose[@]}" exec -T web sha256sum /etc/guacamole/extensions/workshop-reset.jar
}

case "$action" in
    down) "${compose[@]}" down -v; exit ;;
    logs)
        "${compose[@]}" ps -a
        "${compose[@]}" logs --no-color --timestamps --tail 150
        "${compose[@]}" exec -T guacd sh -c 'df -k /recordings; cat /sys/fs/cgroup/memory.events' || true
        exit ;;
    outage) "${compose[@]}" stop guacd; exit ;;
    restore) "${compose[@]}" up -d --no-deps --no-recreate --wait --wait-timeout 25 guacd; exit ;;
    bad-password)
        sql "UPDATE guacamole_connection_parameter SET parameter_value = 'deliberately-wrong'
             WHERE parameter_name = 'password';"
        exit ;;
    auth-failed)
        "${compose[@]}" logs --no-color guacd | grep -i 'password authentication failed'
        exit ;;
    stage)
        active_assets > active.before
        docker inspect --format '{{.Id}} {{.State.StartedAt}}' $("${compose[@]}" ps -q) | sort > starts.before
        mkdir -p stage-opt/workshop stage-varlib/workshop stage-source
        cp -a "$source_dir"/{install.sh,install-dashboard.sh,workshop,workshop_templates.py,build-template.sh,README.md,infra,templates,docs,guest,portal-reset,dashboard} stage-source/
        printf '
/* A staged extension must never be served. */
' >> stage-source/portal-reset/reset.js
        printf '{}
' > stage-varlib/workshop/event.json
        sudo unshare --mount --propagation private bash -euc '
            mount --bind "$PWD/stage-opt" /opt
            mount --bind "$PWD/active" /opt/workshop
            mount --bind "$PWD/stage-varlib" /var/lib
            bash stage-source/install.sh
            staged=/var/lib/workshop/releases/staged/files/portal-reset/extensions/workshop-reset.jar
            test -s "$staged"
            ! cmp -s "$staged" /opt/workshop/portal-reset/extensions/workshop-reset.jar
            for option in --apply-portal --rollback-portal; do
                if output=$(bash stage-source/install.sh "$option" 2>&1); then exit 1; fi
                grep -F "End the workshop before changing the active release." <<< "$output"
            done
        '
        active_assets | diff -u active.before -
        docker inspect --format '{{.Id}} {{.State.StartedAt}}' $("${compose[@]}" ps -q) | sort | diff -u starts.before -
        exit ;;
    restart-staged)
        "${compose[@]}" restart web
        "${compose[@]}" up -d --no-deps --no-recreate --wait --wait-timeout 25 web
        active_assets | diff -u active.before -
        exit ;;
    dashboard-live)
        # docker inspect supplies a host PID. Read its real namespace on the runner.
        sudo python3 "$source_dir/tests/dashboard-lab.py" "$PWD"
        exit ;;
    size-cap)
        mkdir -p size-check
        chmod 0777 size-check
        docker run --rm --user root --entrypoint sh \
            -v "$source_dir/tests/recording-limit.c:/recording-limit.c:ro" \
            -v "$PWD/size-check:/out" "$PETER_LAB_GUACD_IMAGE" \
            -ec 'apk add --no-cache build-base=0.5-r3 cairo-dev=1.17.8-r1
                 cc -Wall -Wextra -Werror -I/opt/guacamole/include /recording-limit.c \
                    -L/opt/guacamole/lib -lguac -o /out/recording-limit'
        "${compose[@]}" cp size-check/recording-limit guacd:/tmp/recording-limit
        "${compose[@]}" exec -T guacd /tmp/recording-limit
        exit ;;
    reserve)
        # Leave less than 16 MiB free, independently of the per-file limit.
        "${compose[@]}" exec -T guacd sh -ec '
            free=$(df -Pk /recordings | awk "NR == 2 { print \$4 }")
            test "$free" -gt 16384
            dd if=/dev/zero of=/recordings/fixture-space bs=1024 count=$((free - 15360))'
        exit ;;
    interrupt)
        "${compose[@]}" exec -T guacd sh -ec '
            worker=$(pidof guacd | tr " " "\n" | grep -vx 1)
            test "$(echo "$worker" | wc -w)" -eq 1
            kill -KILL "$worker"'
        exit ;;
    output-complete) guest_file output-completed; exit ;;
    responsive) guest_file session-responsive; exit ;;
    paused)
        guest_file recording-paused
        "${compose[@]}" logs --no-color guacd | grep 'Workshop screen recording paused at its size or storage limit.'
        "${compose[@]}" exec -T guacd stat -c %s /recordings/review-ab123456-team-1-cd123456.guac > paused.size
        exit ;;
    after-pause)
        guest_file responsive-after-pause
        "${compose[@]}" exec -T guacd stat -c %s /recordings/review-ab123456-team-1-cd123456.guac | diff -u paused.size -
        "${compose[@]}" exec -T guacd rm -f /recordings/fixture-space
        exit ;;
    probe)
        "${compose[@]}" exec -T guest sh -ec 'test -f /tmp/peter-output-completed && test -f /tmp/peter-session-responsive && test -f /tmp/peter-reconnected'
        "${compose[@]}" exec -T guacd df -k /recordings
        "${compose[@]}" logs --no-color guacd | grep 'Workshop screen recording paused at its size or storage limit.'
        exit ;;
    up) ;;
    *) exit 2 ;;
esac

mkdir -p active/portal-reset/extensions active/infra
python3 - "$source_dir/portal-reset" "$PWD/active/portal-reset/extensions/workshop-reset.jar" <<'PY'
from pathlib import Path
import sys
from zipfile import ZipFile

with ZipFile(sys.argv[2], 'w') as archive:
    for name in ('guac-manifest.json', 'reset.js', 'reset.css', 'clipboard.js'):
        archive.write(Path(sys.argv[1]) / name, name)
PY
docker run --rm --network none guacamole/guacamole:1.6.0 /opt/guacamole/bin/initdb.sh --postgresql > schema.sql
cat > fixture.sql <<'SQL'
INSERT INTO guacamole_entity (name, type) VALUES ('1', 'USER');
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
SELECT entity_id, sha256(convert_to('peter-review-only' || repeat('00', 32), 'UTF8')),
       decode(repeat('00', 32), 'hex'), now() FROM guacamole_entity WHERE name = '1';
INSERT INTO guacamole_connection (connection_name, protocol, max_connections, max_connections_per_user)
VALUES ('review-ab123456-team-1-cd123456', 'ssh', 1, 1);
INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
SELECT connection_id, name, value FROM guacamole_connection CROSS JOIN (VALUES
    ('hostname', '10.241.1.2'), ('port', '22'), ('username', 'team'), ('password', 'terminal-fixture'),
    ('recording-path', '/recordings'), ('recording-name', 'review-ab123456-team-1-cd123456.guac')) AS p(name, value);
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, connection_id, 'READ' FROM guacamole_entity CROSS JOIN guacamole_connection WHERE name = '1';
INSERT INTO guacamole_connection (connection_name, protocol)
VALUES ('review-ab123456-team-2-cd123457', 'ssh');
SQL
chmod 0644 schema.sql fixture.sql active/portal-reset/extensions/workshop-reset.jar
cat > active/infra/compose.yaml <<'YAML'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: guacamole
      POSTGRES_PASSWORD: lab-db-password
    volumes:
      - ../../schema.sql:/docker-entrypoint-initdb.d/10-schema.sql:ro
      - ../../fixture.sql:/docker-entrypoint-initdb.d/20-fixture.sql:ro
    healthcheck:
      test: [CMD-SHELL, 'pg_isready -h 127.0.0.1 -U postgres -d guacamole']
      interval: 1s
      retries: 30
  guacd:
    image: ${PETER_LAB_GUACD_IMAGE:?}
    mem_limit: 1g
    cpus: 2
    pids_limit: 128
    tmpfs: ["/recordings:size=128m,uid=1000,gid=1000,mode=0700"]
    networks:
      default: {}
      guest-link:
        ipv4_address: 10.241.1.3
    healthcheck:
      test: [CMD, nc, -z, 127.0.0.1, '4822']
      interval: 1s
      retries: 30
  guest:
    image: guacamole/guacd:1.6.0
    user: root
    networks:
      default: {}
      guest-link:
        ipv4_address: 10.241.1.2
    entrypoint: [/bin/sh, -ec]
    command:
      - |
        apk add --no-cache openssh-server
        adduser -D team && echo 'team:terminal-fixture' | chpasswd
        ssh-keygen -A
        mkdir -p /run/sshd
        exec /usr/sbin/sshd -D -e -o PasswordAuthentication=yes
    healthcheck:
      test: [CMD, nc, -z, 127.0.0.1, '22']
      interval: 2s
      retries: 40
  web:
    image: guacamole/guacamole:1.6.0
    ports:
      - 127.0.0.1:${PETER_LAB_PORT:?}:8080
    volumes:
      - ../portal-reset/extensions:/etc/guacamole/extensions:ro
    environment:
      WEBAPP_CONTEXT: ROOT
      GUACD_HOSTNAME: guacd
      POSTGRESQL_HOSTNAME: db
      POSTGRESQL_DATABASE: guacamole
      POSTGRESQL_USERNAME: postgres
      POSTGRESQL_PASSWORD: lab-db-password
    depends_on:
      db: {condition: service_healthy}
      guacd: {condition: service_healthy}
      guest: {condition: service_healthy}
    healthcheck:
      test: [CMD, curl, -fsS, -o, /dev/null, 'http://127.0.0.1:8080/']
      interval: 2s
      retries: 40
networks:
  guest-link:
    internal: true
    ipam:
      config:
        - subnet: 10.241.1.0/29
YAML
"${compose[@]}" up -d --wait --wait-timeout 120

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
compose=(docker compose -p peter-portal-test -f compose.yaml)

case "$action" in
    down) "${compose[@]}" down -v; exit ;;
    logs) "${compose[@]}" logs --no-color --tail 100; exit ;;
    reserve)
        # Leave less than the production reserve on the lab's smaller tmpfs.
        "${compose[@]}" exec -T guacd dd if=/dev/zero of=/recordings/fixture-space bs=1M count=49
        exit ;;
    interrupt)
        "${compose[@]}" exec -T guacd sh -ec '
            worker=$(pidof guacd | tr " " "\n" | grep -vx 1)
            test "$(echo "$worker" | wc -w)" -eq 1
            kill -KILL "$worker"'
        exit ;;
    responsive)
        "${compose[@]}" exec -T guest sh -ec 'test -f /tmp/peter-output-completed && test -f /tmp/peter-session-responsive'
        exit ;;
    probe)
        "${compose[@]}" exec -T guest sh -ec 'test -f /tmp/peter-output-completed && test -f /tmp/peter-session-responsive && test -f /tmp/peter-reconnected'
        "${compose[@]}" exec -T guacd df -k /recordings
        "${compose[@]}" logs --no-color guacd | grep 'Workshop screen recording paused at its size or storage limit.'
        exit ;;
    up) ;;
    *) exit 2 ;;
esac

mkdir -p extensions
python3 - "$source_dir/portal-reset" "$PWD/extensions/workshop-reset.jar" <<'PY'
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
    ('hostname', 'guest'), ('port', '22'), ('username', 'team'), ('password', 'terminal-fixture'),
    ('recording-path', '/recordings'), ('recording-name', 'review-ab123456-team-1-cd123456.guac')) AS p(name, value);
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
SELECT entity_id, connection_id, 'READ' FROM guacamole_entity CROSS JOIN guacamole_connection WHERE name = '1';
SQL
chmod 0644 schema.sql fixture.sql extensions/workshop-reset.jar
cat > compose.yaml <<'YAML'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: guacamole
      POSTGRES_PASSWORD: lab-db-password
    volumes:
      - ./schema.sql:/docker-entrypoint-initdb.d/10-schema.sql:ro
      - ./fixture.sql:/docker-entrypoint-initdb.d/20-fixture.sql:ro
    healthcheck:
      test: [CMD-SHELL, 'pg_isready -h 127.0.0.1 -U postgres -d guacamole']
      interval: 1s
      retries: 30
  guacd:
    image: ${PETER_LAB_GUACD_IMAGE:?}
    mem_limit: 1g
    cpus: 2
    pids_limit: 128
    tmpfs: ["/recordings:size=64m,uid=1000,gid=1000,mode=0700"]
    healthcheck:
      test: [CMD, nc, -z, 127.0.0.1, '4822']
      interval: 1s
      retries: 30
  guest:
    image: guacamole/guacd:1.6.0
    user: root
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
      - ./extensions:/etc/guacamole/extensions:ro
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
YAML
"${compose[@]}" up -d --wait --wait-timeout 120

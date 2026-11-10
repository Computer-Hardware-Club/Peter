#!/usr/bin/env bash
set -euo pipefail

# The image's initdb helper runs this as the database owner on first initialization.
psql -X -v ON_ERROR_STOP=1 --username postgres --dbname guacamole <<'SQL'
\getenv app_password APP_DB_PASSWORD
BEGIN;
DELETE FROM guacamole_entity WHERE type = 'USER' AND name = 'guacadmin';
CREATE ROLE guacamole LOGIN PASSWORD :'app_password';
GRANT CONNECT ON DATABASE guacamole TO guacamole;
GRANT USAGE ON SCHEMA public TO guacamole;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO guacamole;
GRANT INSERT, UPDATE ON guacamole_user_history, guacamole_connection_history TO guacamole;
GRANT SELECT, USAGE ON ALL SEQUENCES IN SCHEMA public TO guacamole;
COMMIT;
SQL

#!/usr/bin/env bash
set -euo pipefail

for team_user in team-{1..4}; do
    if ! entry=$(getent passwd "$team_user"); then
        continue
    fi
    IFS=: read -r _ _ _ _ _ team_home _ <<< "$entry"
    install -d -o "$team_user" -g "$team_user" -m 0755 "$team_home/lab"
    cat > "$team_home/lab/README.txt" <<'EOF'
Welcome to the Hello Lab.

Try pwd, ls -la, and chcfetch to get oriented.
Open this file with nano and make an edit.
A workshop VM reset will recreate this file from init.sh.
EOF
    chown "$team_user:$team_user" "$team_home/lab/README.txt"
    exit 0
done

echo 'No workshop team account found.' >&2
exit 1

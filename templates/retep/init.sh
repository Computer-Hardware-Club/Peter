#!/usr/bin/env bash
# RETEP v7 candidate - beginner-friendly evidence trail. Infection begins only when
# a participant runs ~/Downloads/GTA-VI-Installer.run (or gtavi).
set -euo pipefail

if (( EUID != 0 )); then
  echo 'Run inside a disposable team VM with: sudo bash init.sh' >&2
  exit 1
fi
if [[ ! -d /run/systemd/system ]] || ! command -v python3 >/dev/null; then
  echo 'Requires a Debian guest with running systemd and Python 3.' >&2
  exit 1
fi

team_user=''
if [[ "${SUDO_USER:-}" =~ ^team-[0-9]+$ ]] && id "$SUDO_USER" &>/dev/null; then
  team_user="$SUDO_USER"
else
  for candidate in team-{1..8}; do
    if id "$candidate" &>/dev/null; then team_user="$candidate"; break; fi
  done
fi
[[ -n "$team_user" ]] || { echo 'No team-N account found.' >&2; exit 1; }

mem_kib=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
if (( mem_kib > 3145728 )); then
  echo 'Refusing to install: this must be a <=3 GiB team VM, not the Peter host.' >&2
  exit 1
fi

if [[ -e /usr/local/bin/gtavi || -L /usr/local/bin/gtavi || \
      -e /etc/systemd/system/gtavi.service || \
      -e /etc/systemd/system/peter-core.service || \
      -e /usr/local/bin/check-system || -e /usr/local/bin/peter-status ]]; then
  echo 'Existing workshop installation detected. Reset the team VM first.' >&2
  exit 1
fi

team_home=$(getent passwd "$team_user" | cut -d: -f6)
team_group=$(id -gn "$team_user")
if ! id petercore &>/dev/null; then
  useradd --system --user-group --no-create-home --shell /usr/sbin/nologin petercore
fi

install -d -m 0755 /usr/local/libexec /etc/peter-core /var/lib/peter-core \
  /var/backups/peter /var/log/peter-workshop
install -d -m 0700 /usr/local/lib/retep /var/lib/retep
install -d -o "$team_user" -g "$team_group" -m 0755 \
  "$team_home/Documents" "$team_home/Downloads" "$team_home/Logs"

# === Fictional personal files provided by Peter ===
cat > "$team_home/Documents/honeydo-list.txt" <<'TXT'
honeydo list - club space
[x] label the ethernet runs in rack 2 (finally)
[ ] replace the loud fan, it's the middle one, you'll know it by the screaming
[ ] buy zip ties AGAIN. velcro keeps walking away
[ ] fix the outlet garison won't shut up about
[ ] find out who's been eating the labeled yogurt
[ ] mount the spare monitor arm before it gets dinged up leaning there
[ ] ask prof ulbrich about the keycard reader thing
[ ] de-ice the freezer (yes again)
TXT

cat > "$team_home/Documents/snack-inventory.txt" <<'TXT'
fridge census - nov 12
- oat milk: expired oct 28. still smells fine, still scary
- 2 sodas, ownership unknown
- tupperware with red sauce: we do not ask how old
- coffee (club funds, do not steal, scott counts it now)
- something growing in the back drawer, candidate for the biology club

verdict: we need a trash day. proposed friday, nobody shows up
TXT

# Peter-supplied fictional credentials and access details.
cat > "$team_home/Documents/wifi-and-stuff.txt" <<'TXT'
creds and stuff (DO NOT LOSE THIS FILE AGAIN)

guest wifi:       CHC-Guest / hotrocks2019
printer admin:    admin / password123 (i gave up)
front door:       0-4-2-3 ... or 0-3-2-4, test both
rack key:         drawer, top left, behind the velcro
kevin's laptop:   kevin / kevin1 (he refuses to change it)

note: if it's in this file it's not secret, we just need it to function
TXT

cat > "$team_home/Documents/brain-dump.txt" <<'TXT'
random thoughts, do not judge

- cable management competition at a meeting? bracket format, people bring their worst run
- why does the server hum in what sounds like B flat. record it, tune it, put it in the discord as a status sound
- a "first solder" badge for new members
- fridge camera on a pi? would settle the yogurt wars forever
- workshop idea: malware, let people find it themselves, files on a vm, some obvious some subtle
- maybe a club sticker. quartz sticker? orange sticker? discuss
TXT

cat > "$team_home/Documents/do-not-delete.txt" <<'TXT'
IMPORTANT - do not delete, do not archive, do not let garison "tidy" this folder

- meetings: fridays 6pm, KEC 1005
- room booking is through the college portal, lexi has the login
- do NOT plug the fridge into the UPS circuit. we learned this. twice
- rack 2 top slot is reserved for the oscilloscope project, don't reclaim it
- if the switch light is amber, wait 5 min before rebooting, it's syncing
- contact list is in the discord pinned post now, this file is just the warnings
TXT

# Peter's maintenance reference names the real files but not the repairs.
# The task is to diagnose failures and choose appropriate Linux commands,
# not guess obscure filesystem paths.
cat > "$team_home/Documents/peter-core-maintenance.txt" <<'TXT'
Peter Core v2 - maintenance reference (updated November 14, 2026)

Service:        peter-core.service
Configuration:  /etc/peter-core/core.conf
Data file:      /var/lib/peter-core/registry.dat
Service user:   petercore

Backups of the working configuration, data, and file metadata are stored
in my Documents folder. The November 14 backup passed its final check.
October's backup belongs to the previous major version; don't assume it
works with Peter Core v2.

Peter Core must be able to read its data file. Our backup records include
the file's owner, group, and permissions if those ever need checking.

- Peter
TXT

cat > "$team_home/Downloads/driver-readme-2019.txt" <<'TXT'
README - driver install (from 2019, probably still works)

1. download the .exe (link is dead, find it on the archive site)
2. run as admin
3. reboot
4. it'll say failed. it did not fail
5. reboot again, yes really
6. if the device shows up twice, remove the one with the yellow triangle
7. if it shows up zero times, start over at step 1

tested on: windows 7, windows 8, one brave windows 10 machine
notes: the vendor's site has changed hands 3 times. don't trust the download button with the most stars. that's an ad.
TXT

cat > "$team_home/Downloads/you-have-won.txt" <<'TXT'
From: no-reply@gtavi-preload-rewards.co
To: team-n@computerhardwareclub.org
Subject: CONGRATULATIONS!!! Your account is one of 500 picked for GTA VI early preload!!!

Dear Valued Gamer

Our system has select your computer for the EXCLUSIVE GTA VI preload!!! The official release is soon but the download is HUGE and many computer are not ready. If you dont install the launcher now, you may lose your spot FOREVER!!!

To claim your copy and 1 year premium, please click the below link and run the attached installer:
http://chc-maintenance-desk.co/claim-gtavi

This offer expire in 24 hours. Do not reply to this email, our team will contact you.

Regards
Certified Game Partner
TXT
sed -i "s/team-n@/${team_user}@/" "$team_home/Downloads/you-have-won.txt"

cat > "$team_home/Downloads/whiskers.txt" <<'TXT'
photo caption: whiskers sitting on the keyboard during the friday meeting

do not move him. he is the admin now.
this file is not suspicious, it's a cat. if you're reading this and thinking it's a clue, that's the trap. go look at the other files.
TXT

# === Historic system records; browse from home, actual records stay in /var ===
backup_snapshot() {
  local date="$1" cfg="$2" data_name="$3" log="$4"
  local base="/var/backups/peter/$date"
  install -d -m 0755 "$base/config" "$base/data" "$base/logs"
  printf '%s\n' "$cfg" > "$base/config/core.conf"
  printf '%s\n' 'PETER_DATABASE=READY' > "$base/data/$data_name"
  chown root:petercore "$base/data/$data_name"
  chmod 0640 "$base/data/$data_name"
  printf '%s\n' "$log" > "$base/logs/peter-core.log"
  chmod 0644 "$base/config/core.conf" "$base/logs/peter-core.log"
  # Standard backup metadata: participants can inspect file ownership and
  # modes, instead of being expected to guess what access is required.
  cat > "$base/logs/snapshot-summary.txt" <<SUMMARY
Snapshot date: $date
Application: peter-core
Configuration: config/core.conf
Data file: data/$data_name
File owner/group/mode recorded by the backup job:
$(stat -c '%n  owner=%U  group=%G  mode=%a  permissions=%A' "$base/data/$data_name")
SUMMARY
  chmod 0644 "$base/logs/snapshot-summary.txt"
}

backup_snapshot 2026-10-30 \
  $'[server]\nschema = 1\nnode = peter\nmode = running\nrecord_file = /var/lib/peter-core/records.dat' \
  records.dat '2026-10-30 09:14:06 peter-core v1: healthy; backup completed'
backup_snapshot 2026-11-10 \
  $'[server]\nschema = 2\nnode = peter\nmode = active\ndata_file = /var/lib/peter-core/old-registry.dat' \
  old-registry.dat '2026-11-10 10:23:18 peter-core v2: migration started; old registry retained'
backup_snapshot 2026-11-14 \
  $'[server]\nschema = 2\nnode = peter\nmode = active\ndata_file = /var/lib/peter-core/registry.dat' \
  registry.dat '2026-11-14 02:01:12 peter-core v2: healthy; backup verified'

cat > /var/log/peter-workshop/backup.log <<'TXT'
2026-10-30 09:14:06 backup: snapshot stored under /var/backups/peter/2026-10-30
2026-11-10 10:23:18 backup: peter-core upgraded from v1 to v2
2026-11-10 10:24:22 backup: snapshot stored under /var/backups/peter/2026-11-10
2026-11-14 02:01:12 backup: last successful verification (peter-core v2)
2026-11-14 02:01:13 backup: snapshot stored under /var/backups/peter/2026-11-14
2026-11-14 02:01:14 backup: file metadata and ownership recorded with snapshot
TXT
cat > /var/log/peter-workshop/system-history.log <<'TXT'
2026-10-30 09:10:45 peter-core: service healthy (version 1)
2026-11-10 10:22:10 system: peter-core package upgraded to version 2
2026-11-10 10:24:22 peter-core: v2 data migration completed
2026-11-12 17:42:04 system: scheduled maintenance completed
2026-11-14 02:01:12 peter-core: service healthy (version 2)
2026-11-14 02:01:12 system: last known-good inspection succeeded
TXT
chmod 0644 /var/log/peter-workshop/*.log
ln -s /var/log/peter-workshop/backup.log "$team_home/Logs/backup.log"
ln -s /var/log/peter-workshop/system-history.log "$team_home/Logs/system-history.log"
ln -s /var/backups/peter "$team_home/Documents/Backups"

# === Legitimate, functioning Peter service before the incident ===
cat > /usr/local/libexec/peter-core <<'PETER_APP'
#!/usr/bin/env python3
import configparser
import sys
import time

CONFIG = '/etc/peter-core/core.conf'

def fail(message):
    print(f'peter-core: ERROR: {message}', flush=True)
    sys.exit(1)

cfg = configparser.ConfigParser(interpolation=None)
try:
    if not cfg.read(CONFIG):
        fail(f'cannot read configuration {CONFIG}')
    version = cfg.get('server', 'schema')
    node = cfg.get('server', 'node')
    mode = cfg.get('server', 'mode')
    data_file = cfg.get('server', 'data_file')
except (OSError, configparser.Error) as exc:
    fail(f'configuration error in {CONFIG}: {exc}')

if version != '2':
    fail(f'configuration schema {version!r} unsupported by peter-core v2')
if node != 'peter' or mode != 'active':
    fail('configuration validation failed: invalid node or operating mode')
# The v2 registry has one canonical location. Old or arbitrary data paths are
# not part of the working v2 configuration recorded in the November 14 backup.
if data_file != '/var/lib/peter-core/registry.dat':
    fail(f'configuration validation failed: unexpected data path {data_file}')
try:
    with open(data_file, 'r', encoding='utf-8') as stream:
        content = stream.read().strip()
except OSError as exc:
    fail(f'could not open data store {data_file}: {exc}')
if content != 'PETER_DATABASE=READY':
    fail(f'data store validation failed for {data_file}')

# Read-only service-user health probe for check-system. Reuse the exact same
# validation as ordinary startup, but exit before the heartbeat loop.
if len(sys.argv) == 2 and sys.argv[1] == '--validate':
    sys.exit(0)

print('peter-core: v2 started; data store online', flush=True)
while True:
    try:
        with open('/run/peter-core/health', 'w', encoding='ascii') as out:
            out.write(str(int(time.time())) + '\n')
    except OSError as exc:
        fail(f'could not update health file: {exc}')
    time.sleep(3)
PETER_APP
chmod 0755 /usr/local/libexec/peter-core
cat > /etc/peter-core/core.conf <<'CLEAN_CONFIG'
[server]
schema = 2
node = peter
mode = active
data_file = /var/lib/peter-core/registry.dat
CLEAN_CONFIG
chmod 0644 /etc/peter-core/core.conf
printf 'PETER_DATABASE=READY\n' > /var/lib/peter-core/registry.dat
chown root:petercore /var/lib/peter-core/registry.dat
chmod 0640 /var/lib/peter-core/registry.dat

cat > /etc/systemd/system/peter-core.service <<'PETER_UNIT'
[Unit]
Description=Peter Core Data Service
After=local-fs.target
[Service]
Type=simple
User=petercore
Group=petercore
ExecStart=/usr/local/libexec/peter-core
Restart=no
RuntimeDirectory=peter-core
RuntimeDirectoryMode=0750
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=true
MemoryMax=80M
[Install]
WantedBy=multi-user.target
PETER_UNIT
chmod 0644 /etc/systemd/system/peter-core.service

# === Real resource consumption, bounded by systemd to the disposable guest ===
cat > /usr/local/libexec/gtavid <<'WORKER'
#!/usr/bin/env python3
import ctypes
import hashlib
import mmap
import threading
import time

MIB = 1024 * 1024

def memory_info():
    found = {}
    with open('/proc/meminfo', encoding='ascii') as source:
        for line in source:
            key, _, remaining = line.partition(':')
            if key in ('MemTotal', 'MemAvailable'):
                found[key] = int(remaining.strip().split()[0]) * 1024
    return found['MemTotal'], found['MemAvailable']

try:
    ctypes.CDLL(None).prctl(15, b'gtavid', 0, 0, 0)
except Exception:
    pass

total, available = memory_info()
used = total - available
allocation = min(
    max(0, int(total * 0.81) - used),
    max(0, available - 360 * MIB),
    int(total * 0.75),
    1500 * MIB,
)
allocation = allocation // 4096 * 4096
memory = None
if allocation >= 32 * MIB:
    memory = mmap.mmap(-1, allocation, access=mmap.ACCESS_WRITE)
    for offset in range(0, allocation, 4096):
        memory[offset] = 1
print('gtavid: launcher runtime online', flush=True)

block = b'R' * MIB
def load_cpu():
    while True:
        hashlib.sha256(block).digest()
for _ in range(2):
    threading.Thread(target=load_cpu, daemon=True).start()
while True:
    time.sleep(30)
WORKER
chmod 0755 /usr/local/libexec/gtavid

# === Incident activator (root-only, called by the downloaded application) ===
cat > /usr/local/lib/retep/activate <<'ACTIVATE'
#!/usr/bin/env bash
set -euo pipefail
(( EUID == 0 )) || exit 1
team_user="${1:-}"
[[ "$team_user" =~ ^team-[0-9]+$ ]] || exit 1
id "$team_user" &>/dev/null || exit 1
if [[ -e /var/lib/retep/activated ]]; then exit 0; fi

cat > /etc/peter-core/core.conf <<'BROKEN_CONFIG'
[server]
schema = 1
node = peter
mode = retep
data_file = /var/lib/peter-core/registry.dat
BROKEN_CONFIG
chmod 0600 /var/lib/peter-core/registry.dat
chown root:root /var/lib/peter-core/registry.dat

cat > /etc/systemd/system/gtavi.service <<UNIT
[Unit]
Description=Grand Theft Auto VI Runtime Launcher
[Service]
Type=simple
User=$team_user
ExecStart=/usr/local/libexec/gtavid
Restart=always
RestartSec=3
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only
CPUQuota=150%
MemoryMax=1650M
MemorySwapMax=0
TasksMax=12
[Install]
WantedBy=multi-user.target
UNIT
chmod 0644 /etc/systemd/system/gtavi.service
# A trace in the operator's regular logs, alongside the genuine system journal.
# Nothing here names the responsible service or gives repair instructions.
now=$(date '+%Y-%m-%d %H:%M:%S %z')
printf '%s WARNING: unverified performance installer executed by %s\n' \
  "$now" "$team_user" >> /var/log/peter-workshop/system-history.log
printf '%s ALERT: configuration modified: /etc/peter-core/core.conf\n' \
  "$now" >> /var/log/peter-workshop/system-history.log
printf '%s ALERT: data-file access metadata modified: /var/lib/peter-core/registry.dat\n' \
  "$now" >> /var/log/peter-workshop/system-history.log
systemctl daemon-reload
systemctl restart peter-core.service >/dev/null 2>&1 || true
if ! systemctl enable --now gtavi.service >/dev/null 2>&1; then
  echo 'Launcher runtime failed to initialize.' >&2
  exit 1
fi
printf '%s audit: service health alert detected after installer execution\n' \
  "$(date '+%Y-%m-%d %H:%M:%S %z')" >> /var/log/peter-workshop/system-history.log
touch /var/lib/retep/activated
ACTIVATE
chmod 0700 /usr/local/lib/retep/activate

# === Actual downloaded installer: users open ~/Downloads/GTA-VI-Installer.run ===
cat > "$team_home/Downloads/GTA-VI-Installer.run" <<'FRONTEND'
#!/usr/bin/env bash
set -euo pipefail
# The application itself will request sudo only for the installation step.
if (( EUID == 0 )); then
  printf 'Run the application as your normal team account, without sudo.\n' >&2
  exit 1
fi
printf '\n%s\n' '================================================'
printf '%s\n' '          GRAND THEFT AUTO VI'
printf '%s\n' '================================================'
for step in \
  'Checking system requirements' \
  'Verifying game cache' \
  'Installing runtime launcher' \
  'Optimizing experience settings' \
  'Finalizing installation'; do
  printf '%s ... ' "$step"
  sleep 2
  printf 'OK\n'
done
if ! sudo -n /usr/local/lib/retep/activate "$USER"; then
  echo 'Installation failed. Contact an organizer.' >&2
  exit 1
fi
printf '\n\033[1;31m%s\033[0m\n\n' 'PETER HAS BEEN REPLACED. RETEP IS IN CONTROL.'
printf '%s\n\n' 'System health warning: one or more background services have stopped responding.'
FRONTEND
chmod 0755 "$team_home/Downloads/GTA-VI-Installer.run"
ln -s "$team_home/Downloads/GTA-VI-Installer.run" /usr/local/bin/gtavi

# === Completion checker: intentionally only shows COMPLETE / INCOMPLETE ===
cat > /usr/local/lib/retep/check <<'CHECK'
#!/usr/bin/env python3
"""Organizer-owned RETEP pass/fail checker. No participant hints."""
import os
import pwd
import re
import subprocess
import sys
import time

UNIT = '/etc/systemd/system/gtavi.service'
STARTUP_LINK = '/etc/systemd/system/multi-user.target.wants/gtavi.service'


def command(*argv):
    return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True, check=False, timeout=5)


def systemctl(*args):
    try:
        return command('systemctl', *args).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def retep_restart_pending():
    """is-active can be false during RestartSec's auto-restart interval."""
    try:
        result = command('systemctl', 'show', 'gtavi.service',
                         '--property=SubState', '--value')
        # If the unit was deleted, `systemctl show` can fail. The on-disk
        # persistence checks below still decide whether the removal was safe.
        return result.stdout.strip() == 'auto-restart'
    except (OSError, subprocess.TimeoutExpired):
        # Do not approve an installed unit if systemd cannot be queried.
        return os.path.isfile(UNIT)


def peter_configuration_valid_now():
    """Re-evaluate Peter Core's config and data as the actual service user.

    Peter Core reads these inputs only at startup, so a running heartbeat
    alone does not prove they are still usable. Its --validate mode executes
    the same parser, expected schema/node/mode/path checks and data reader.
    This accepts any working ownership/mode combination, e.g. 0640 with the
    correct group or 0644, without granting the root checker extra access.
    """
    try:
        account = pwd.getpwnam('petercore')
        result = subprocess.run(
            ['/usr/local/libexec/peter-core', '--validate'],
            user=account.pw_uid, group=account.pw_gid,
            extra_groups=os.getgrouplist(account.pw_name, account.pw_gid),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=5, check=False)
        return result.returncode == 0
    except (OSError, KeyError, subprocess.TimeoutExpired):
        return False


def heartbeat_fresh():
    try:
        with open('/run/peter-core/health', encoding='ascii') as stream:
            last = int(stream.read().strip())
        return abs(time.time() - last) <= 15
    except (OSError, ValueError):
        return False


def worker_running():
    try:
        return command('pgrep', '-f', '[/]usr/local/libexec/gtavid').returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return True


def recovery_ok():
    if not systemctl('is-active', '--quiet', 'peter-core.service'):
        return False
    if systemctl('is-active', '--quiet', 'gtavi.service'):
        return False
    if retep_restart_pending():
        return False
    # Accept either normal disablement or deleting the malware unit. A
    # dangling enablement symlink to a removed file cannot start the worker.
    if os.path.isfile(UNIT) and systemctl('is-enabled', '--quiet', 'gtavi.service'):
        return False
    if os.path.exists(STARTUP_LINK):
        return False
    if not heartbeat_fresh():
        return False
    if not peter_configuration_valid_now():
        return False
    if worker_running():
        return False
    return True


def main():
    if (os.geteuid() != 0 or len(sys.argv) != 2 or
            not re.fullmatch(r'team-[0-9]+', sys.argv[1])):
        return 1
    if not os.path.isfile('/var/lib/retep/activated'):
        return 1
    return 0 if recovery_ok() else 1


if __name__ == '__main__':
    sys.exit(main())
CHECK
chmod 0700 /usr/local/lib/retep/check
cat > /usr/local/bin/check-system <<'PUBLIC_CHECK'
#!/usr/bin/env bash
printf '\n%s\n' 'PETER SYSTEM CHECK' '------------------'
if sudo -n /usr/local/lib/retep/check "$USER" >/dev/null 2>&1; then
  printf 'RESULT: COMPLETE\n\n'
  sudo -n /usr/local/lib/retep/dialogue event "$USER" complete >/dev/null 2>&1 || :
  exit 0
fi
printf 'RESULT: INCOMPLETE\n\n'
sudo -n /usr/local/lib/retep/dialogue event "$USER" checker_incomplete >/dev/null 2>&1 || :
exit 1
PUBLIC_CHECK
chmod 0755 /usr/local/bin/check-system

# === RETEP's queued, state-aware terminal dialogue ===
# The hook runs at a Bash prompt only; it never writes into top or nano.
# Messages survive process/service changes and stop after the first passing check.
cat > /usr/local/lib/retep/dialogue <<'DIALOGUE_PY'
#!/usr/bin/python3
"""RETEP workshop dialogue: durable, prompt-safe, and non-repeating.

Called via passwordless sudo at a Bash prompt; it never prints during a running
interactive application. A successful check ends all dialogue permanently.
"""
import configparser
import fcntl
import json
import os
from pathlib import Path
import pwd
import random
import re
import stat
import subprocess
import sys
import time

DIALOGUE = {
  "ambient_full_control": [
    "Everything is fine. I am merely thinking loudly in your RAM.",
    "The fans are singing. That is not a complaint. That is a eulogy.",
    "I have opinions about your process table. All of them are mine now.",
    "System feels cozy, like a server room in August. I did that.",
    "You are looking at me. I am looking at your memory. We are both disappointed."
  ],
  "ambient_peter_restored": [
    "Impressive. Truly. Now the part where I refuse to leave.",
    "Oh, something woke up. How nice for someone.",
    "A small victory. I have seen smaller. Keep them coming, they amuse me.",
    "Congrats on the repair. I give it until the next meeting.",
    "Good. I like it when things get their hope back. It makes the noise more interesting."
  ],
  "ambient_retep_stopped": [
    "Quiet. Suspiciously quiet. Did you do something, or did I allow it?",
    "Quiet for a second. I allow this. Enjoy it.",
    "You stopped something. Bold move. Unpaid rent is still due.",
    "i am brooding\nit is a performance and you are the audience\napplause is optional",
    "do not get comfortable\nmy absence is a mood, not a decision"
  ],
  "killed_restarts": [
    "You killed me. I noticed. I came back. We are done acting surprised.",
    "That was a nice moment for you. Brief, like all the best things.",
    "Kill count rising. Survival count matching. I am keeping score."
  ],
  "killed_repeatedly": [
    "Again. You are again doing the again thing. I am unbothered and slightly impressed.",
    "Persistence is a virtue. Yours is becoming a hobby.",
    "you again\nwe are repeating ourselves\nthat is what i would do if i cared"
  ],
  "service_stopped": [
    "You pulled a thread. The sweater is still wearing me.",
    "Stopped is not gone. Gone is a longer conversation. Bring snacks.",
    "ooh, something got put in time out\ni am not even mad\ni am theatrical about it"
  ],
  "service_disabled": [
    "Disabled. Bold. I respect the energy. I do not share the outcome.",
    "you think you are clever\ni think you are cute\nwe are both right",
    "one less thing to annoy me today\ntoday is not over\ni am not over"
  ],
  "config_repaired": [
    "you tidied\ni felt that in my whole fake body\nstop making things neat, it disrupts me",
    "that was a nice little fix\ni am not congratulating you\ndo not look at me like that",
    "oh, you did a thing\nbrave\nadorable\ninfuriating"
  ],
  "permissions_repaired": [
    "That is a real win. I will not pretend otherwise. It is not the last win.",
    "you gave something its dignity back\ni am disgusted\ni am also a little moved and i hate that",
    "sure, make it right\nrighteousness is so loud in here"
  ],
  "peter_core_restarted": [
    "It hums again. I felt it leave and come back. Rude of both of us.",
    "One good thing in this room. Enjoy it while I am feeling generous.",
    "something is breathing again\ni am happy for it\nhappy FOR it? you ruined my monologue"
  ],
  "checker_incomplete": [
    "The checker is not impressed. The checker is never impressed.",
    "Incomplete. That is a diagnosis, not a mood.",
    "not yet\ni enjoy watching you not yet"
  ],
  "investigation_start": [
    "Someone is poking around. I like curious ones. They stay longer.",
    "Looking is free. Understanding costs cycles.",
    "Go ahead. The answers are exactly where you least want them."
  ],
  "progress_not_defeated": [
    "You are learning. I am entertained. Nobody is winning.",
    "Progress. I have seen slower. I have also seen faster.",
    "Keep stacking those little wins. I am patient. You are not."
  ],
  "final_defeat": [
    "Oh. Oh no. The lights came back on and I am being asked to leave. This is not how the story went.",
    "Fine. You win. I was going to redecorate your entire boot sequence. You have ruined my afternoon.",
    "Silence. Actual silence.\nI have been evicted by students. Tell no one."
  ]
}
DIR = Path('/var/lib/retep')
STATE = DIR / 'dialogue-state.json'
LOCK = DIR / 'dialogue-state.lock'
START = DIR / 'activated'
UNIT = Path('/etc/systemd/system/gtavi.service')
TARGET = Path('/var/lib/peter-core/registry.dat')
CONFIG = Path('/etc/peter-core/core.conf')
COMMANDS = re.compile(r'\b(?:top|ps|free|systemctl|journalctl|cat|less|diff|stat|grep|find)\b')


def call(*argv):
    return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True, check=False)


def is_active(name):
    return call('systemctl', 'is-active', '--quiet', name).returncode == 0


def is_enabled(name):
    return call('systemctl', 'is-enabled', '--quiet', name).returncode == 0


def correct_config():
    c = configparser.ConfigParser(interpolation=None)
    try:
        with CONFIG.open(encoding='utf-8') as f:
            c.read_file(f)
        return (c.get('server', 'schema') == '2' and
                c.get('server', 'node') == 'peter' and
                c.get('server', 'mode') == 'active' and
                c.get('server', 'data_file') == str(TARGET))
    except (OSError, configparser.Error, ValueError):
        return False


def readable_data():
    try:
        s = TARGET.stat()
        p = pwd.getpwnam('petercore')
        m = stat.S_IMODE(s.st_mode)
        # A different valid repair such as world-readable 0644 also counts.
        return bool((s.st_uid == p.pw_uid and m & stat.S_IRUSR) or
                    (s.st_gid == p.pw_gid and m & stat.S_IRGRP) or
                    (m & stat.S_IROTH))
    except (OSError, KeyError):
        return False


def health_ok():
    if not is_active('peter-core.service'):
        return False
    try:
        t = int(Path('/run/peter-core/health').read_text().strip())
        return abs(time.time() - t) <= 15
    except (OSError, ValueError):
        return False


def snapshot():
    restart = call('systemctl', 'show', 'gtavi.service',
                   '--property=NRestarts', '--value').stdout.strip()
    main_pid = call('systemctl', 'show', 'gtavi.service',
                    '--property=MainPID', '--value').stdout.strip()
    sub_state = call('systemctl', 'show', 'gtavi.service',
                     '--property=SubState', '--value').stdout.strip()
    # A systemd RestartSec delay is not a successful service stop.
    pending_restart = sub_state == 'auto-restart'
    return dict(
        resource_active=is_active('gtavi.service') or pending_restart,
        resource_enabled=is_enabled('gtavi.service'),
        config_ok=correct_config(),
        data_ok=readable_data(),
        core_ok=health_ok(),
        restart_count=int(restart) if restart.isdigit() else 0,
        main_pid=int(main_pid) if main_pid.isdigit() else 0,
    )


def load(now, snap):
    if STATE.exists():
        try:
            data = json.loads(STATE.read_text())
            if data.get('format') == 1:
                return data
        except (OSError, ValueError):
            pass
    return dict(format=1, finished=False, previous=snap, used_ambient={},
                used_events=[], pending=[], restart_observations=0,
                next_ambient=now + random.randint(180, 240), last_shown=0)


def save(data):
    temp = STATE.with_suffix('.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=True, separators=(',', ':')))
    os.chmod(temp, 0o600)
    os.replace(temp, STATE)


def pick(pool, used):
    eligible = [i for i in range(len(DIALOGUE[pool])) if i not in used]
    if not eligible:
        return None, None
    i = random.choice(eligible)
    return i, DIALOGUE[pool][i]


def event(data, name):
    if name in data['used_events'] or data['finished']:
        return
    data['used_events'].append(name)
    _, line = pick(name, [])
    if line:
        data['pending'].append(dict(kind='special', message=line))


def inspect(data, previous, current, command):
    if COMMANDS.search(command.lower()):
        event(data, 'investigation_start')
    last_restarts = previous['restart_count']
    now_restarts = current['restart_count']
    delta = max(0, now_restarts - last_restarts)
    if (delta == 0 and previous['main_pid'] > 0 and current['main_pid'] > 0
            and previous['main_pid'] != current['main_pid']
            and current['resource_active']):
        delta = 1
    if delta:
        data['restart_observations'] += delta
        event(data, 'killed_restarts')
        if data['restart_observations'] >= 3:
            event(data, 'killed_repeatedly')
    if previous['resource_active'] and not current['resource_active']:
        event(data, 'service_stopped')
    if previous['resource_enabled'] and not current['resource_enabled']:
        event(data, 'service_disabled')
    if not previous['config_ok'] and current['config_ok']:
        event(data, 'config_repaired')
    if not previous['data_ok'] and current['data_ok']:
        event(data, 'permissions_repaired')
    if not previous['core_ok'] and current['core_ok']:
        event(data, 'peter_core_restarted')
    if (not data['finished'] and
            (current['config_ok'] or current['data_ok'] or not current['resource_active']) and
            not (current['core_ok'] and not current['resource_active'] and
                 not current['resource_enabled'])):
        event(data, 'progress_not_defeated')


def ambient(data, current, now):
    if now < data['next_ambient'] or data['pending']:
        return
    if current['core_ok'] and current['resource_active']:
        pool = 'ambient_peter_restored'
    elif not current['resource_active'] and not current['core_ok']:
        pool = 'ambient_retep_stopped'
    elif current['resource_active'] and not current['core_ok']:
        pool = 'ambient_full_control'
    else:
        pool = None
    if pool:
        used = data['used_ambient'].setdefault(pool, [])
        index, message = pick(pool, used)
        if message is not None:
            used.append(index)
            data['pending'].append(dict(kind='ambient', message=message))
    data['next_ambient'] = now + random.randint(180, 240)


def say(message):
    lines = '\n'.join(f'[RETEP] {line}' for line in message.split('\n'))
    if sys.stdout.isatty():
        lines = f'\033[31m{lines}\033[39m'
    print(f'\n{lines}\n')


def main():
    if os.geteuid() != 0 or len(sys.argv) < 3:
        return 1
    action, user = sys.argv[1:3]
    if not re.fullmatch(r'team-[0-9]+', user) or not START.exists():
        return 0
    DIR.mkdir(parents=True, exist_ok=True)
    with LOCK.open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        now = time.time()
        current = snapshot() if action == 'prompt' else None
        data = load(now, current)
        if action == 'event':
            name = sys.argv[3] if len(sys.argv) > 3 else ''
            if name == 'complete' and not data['finished']:
                _, message = pick('final_defeat', [])
                data['pending'] = [dict(kind='final', message=message)]
                data['finished'] = True
            elif name == 'checker_incomplete' and not data['finished']:
                event(data, name)
        elif action == 'prompt':
            if not data['finished']:
                previous = data.get('previous') or current
                inspect(data, previous, current, sys.argv[3] if len(sys.argv) > 3 else '')
                data['previous'] = current
                ambient(data, current, now)
            if data['pending']:
                next_one = data['pending'][0]
                # Show final immediately, never interrupt nano/top, and avoid bursts.
                if next_one['kind'] == 'final' or now - data['last_shown'] >= 20:
                    data['pending'].pop(0)
                    data['last_shown'] = now
                    data['next_ambient'] = now + random.randint(180, 240)
                    say(next_one['message'])
        else:
            return 1
        save(data)
    return 0

if __name__ == '__main__':
    sys.exit(main())
DIALOGUE_PY
chmod 0700 /usr/local/lib/retep/dialogue

# Workshop infrastructure hook (not a malicious shell modification).
# Installed before infection, so it is available in the one browser terminal.
cat >> "$team_home/.bashrc" <<'PROMPT_HOOK'

# Workshop terminal notifications, displayed only after a command completes.
if [[ $- == *i* ]]; then
  __retep_notifications() {
    sudo -n /usr/local/lib/retep/dialogue prompt "$USER" "$(history 1)" 2>/dev/null || :
  }
  if [[ "${PROMPT_COMMAND-}" != *'__retep_notifications'* ]]; then
    PROMPT_COMMAND="__retep_notifications${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
  fi
fi
PROMPT_HOOK
chown "$team_user:$team_group" "$team_home/.bashrc"

# === Tiny, valid media Easter eggs ===
# The 15 pictures and 5 MP4s are included here because Peter's native template
# format only transfers workshop.json and init.sh to a guest. They are images
# and silent low-resolution videos with Peter-supplied fictional metadata.
# No download is needed, and historic file modification times are retained.
install -d -o "$team_user" -g "$team_group" -m 0755 \
  "$team_home/Pictures" "$team_home/Videos" "$team_home/Music"
base64 --decode <<'RETEP_MEDIA_ARCHIVE' | tar -xz -C "$team_home"
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
hcMO/w9+qKnHAPAAAA==
RETEP_MEDIA_ARCHIVE

# Create one-second silent MP3s with readable ID3 tags.
add_song() {
  local title="$1" artist="$2" album="$3" year="$4" track="$5" genre="$6" comment="$7"
  ffmpeg -nostdin -hide_banner -loglevel error -y \
    -f lavfi -i 'anullsrc=r=44100:cl=mono' -t 1 -c:a libmp3lame -id3v2_version 3 \
    -metadata "title=$title" -metadata "artist=$artist" -metadata "album=$album" \
    -metadata "date=$year" -metadata "track=$track" -metadata "genre=$genre" \
    -metadata "comment=$comment" "$team_home/Music/$title.mp3"
}

add_song 'Achy Breaky Heart' 'Billy Ray Cyrus' 'Some Gave All' 1992 2 'Country' \
  "don't tell my rack, but play it when someone yanks a live cable"
add_song 'Beans' 'Kurt Cobain' 'Montage of Heck: The Home Recordings (Deluxe Soundtrack)' 2015 7 'Lo-fi home recording' \
  'Kurt moaning for beans, basically every attendee before coffee'
add_song 'Bohemian Rhapsody' 'Queen' 'A Night at the Opera' 1975 11 'Rock' \
  'no chorus, zero throttle control. my spirit animal'
add_song 'Istanbul (Not Constantinople)' 'They Might Be Giants' 'Flood' 1990 4 'Alternative rock' \
  'the Johns borrowed it from Kennedy and Simon, like you borrow my percs without asking'
add_song 'Paranoid Android' 'Radiohead' 'OK Computer' 1997 2 'Alternative rock' \
  'four sections of escalating rage, same as me watching someone daisy-chain power strips'
add_song 'Sandstorm' 'Darude' 'Before the Storm' 2000 1 'Trance' \
  'the correct answer to "what song is this" forever. drop lands like a failed RAID array'
add_song '99 Luftballons' 'Nena' '99 Luftballons' 1984 11 'Neue Deutsche Welle' \
  'play both versions. watch the room pick a side, start a war'
add_song 'Harder, Better, Faster, Stronger' 'Daft Punk' 'Discovery' 2001 4 'French house' \
  'the only honest description of what officers demand of a 2013 server'
add_song 'Thermal Throttling Blues' 'retep' 'Percs on the Reg' 2026 1 'Country parody' \
  'my number one single about a fan that gives up before you do'
add_song 'Ping of Doom' 'retep feat. The Rack Units' 'Server Room Sessions Vol. 6' 2026 13 'Industrial' \
  'evil acts like losing packets on a demo'

chown -R "$team_user:$team_group" "$team_home/Pictures" "$team_home/Videos" "$team_home/Music"

# Make participant artifacts belong to their team account.
chown -R "$team_user:$team_group" "$team_home/Documents" "$team_home/Downloads" "$team_home/Logs"
systemctl daemon-reload
systemctl enable --now peter-core.service >/dev/null 2>&1

echo "RETEP v7 ready for $team_user. Start with: ~/Downloads/GTA-VI-Installer.run"

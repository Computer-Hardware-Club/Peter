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
      -e /etc/systemd/system/mem-boost.service || \
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
From: it-support@chc-maintenance-desk.co
To: team-n@computerhardwareclub.org
Subject: URGENT: Your system performance is LOW!!!

Dear Valued Member

Our monitoring system has detect that your computer memory is running at critical levels!!! This is a SERIOUS warning and if ignore may cause your files to loss forever.

To claim your free system tune-up and 1 year premium, please click the below link and run the attached installer:
http://chc-maintenance-desk.co/claim-gtavi

This offer expire in 24 hours. Do not reply to this email, our team will contact you.

Regards
Certified Maintenance Partner
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
cat > /usr/local/libexec/mem-boostd <<'WORKER'
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
    ctypes.CDLL(None).prctl(15, b'mem-boostd', 0, 0, 0)
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
print('mem-boostd: optimization runtime online', flush=True)

block = b'R' * MIB
def load_cpu():
    while True:
        hashlib.sha256(block).digest()
for _ in range(2):
    threading.Thread(target=load_cpu, daemon=True).start()
while True:
    time.sleep(30)
WORKER
chmod 0755 /usr/local/libexec/mem-boostd

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

cat > /etc/systemd/system/mem-boost.service <<UNIT
[Unit]
Description=Adaptive Memory Optimization Service
[Service]
Type=simple
User=$team_user
ExecStart=/usr/local/libexec/mem-boostd
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
chmod 0644 /etc/systemd/system/mem-boost.service
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
if ! systemctl enable --now mem-boost.service >/dev/null 2>&1; then
  echo 'Optimization runtime failed to initialize.' >&2
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

UNIT = '/etc/systemd/system/mem-boost.service'
STARTUP_LINK = '/etc/systemd/system/multi-user.target.wants/mem-boost.service'


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
        result = command('systemctl', 'show', 'mem-boost.service',
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
        return command('pgrep', '-f', '[/]usr/local/libexec/mem-boostd').returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return True


def recovery_ok():
    if not systemctl('is-active', '--quiet', 'peter-core.service'):
        return False
    if systemctl('is-active', '--quiet', 'mem-boost.service'):
        return False
    if retep_restart_pending():
        return False
    # Accept either normal disablement or deleting the malware unit. A
    # dangling enablement symlink to a removed file cannot start the worker.
    if os.path.isfile(UNIT) and systemctl('is-enabled', '--quiet', 'mem-boost.service'):
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
UNIT = Path('/etc/systemd/system/mem-boost.service')
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
    restart = call('systemctl', 'show', 'mem-boost.service',
                   '--property=NRestarts', '--value').stdout.strip()
    main_pid = call('systemctl', 'show', 'mem-boost.service',
                    '--property=MainPID', '--value').stdout.strip()
    sub_state = call('systemctl', 'show', 'mem-boost.service',
                     '--property=SubState', '--value').stdout.strip()
    # A systemd RestartSec delay is not a successful service stop.
    pending_restart = sub_state == 'auto-restart'
    return dict(
        resource_active=is_active('mem-boost.service') or pending_restart,
        resource_enabled=is_enabled('mem-boost.service'),
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
    print('\n[RETEP] ' + message.replace('\n', '\n[RETEP] ') + '\n')


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

# === Tiny, valid media Easter eggs (15 pictures, 5 MP4s) ===
# These binaries are included in this script because Peter's native template
# format only transfers workshop.json and init.sh to a guest. They are images
# and silent low-resolution videos with Peter-supplied fictional metadata.
# No download is needed, and historic file modification times are retained.
install -d -o "$team_user" -g "$team_group" -m 0755 \
  "$team_home/Pictures" "$team_home/Videos"
base64 --decode <<'RETEP_MEDIA_ARCHIVE' | tar -xz -C "$team_home"
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
VwDwAAA=
RETEP_MEDIA_ARCHIVE
chown -R "$team_user:$team_group" "$team_home/Pictures" "$team_home/Videos"

# Make participant artifacts belong to their team account.
chown -R "$team_user:$team_group" "$team_home/Documents" "$team_home/Downloads" "$team_home/Logs"
systemctl daemon-reload
systemctl enable --now peter-core.service >/dev/null 2>&1

echo "RETEP v7 ready for $team_user. Start with: ~/Downloads/GTA-VI-Installer.run"

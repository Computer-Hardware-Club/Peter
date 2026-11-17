#!/usr/bin/env python3
"""Keep the latest screen recording per team and leave open recordings alone."""

import fcntl
import os
from pathlib import Path
import re
import stat
import subprocess
import time


FILENAME = re.compile(r"[a-z][a-z0-9-]{0,23}-[0-9a-f]{8}-team-([1-4])"
                      r"(?:-[0-9a-f]{8})?(?:-r[0-9a-f]{12})?\.guac(?:\.[1-9][0-9]{0,4})?")
GRACE_NS = 60 * 10**9


def prune(directory, now):
    recordings = {}
    for entry in directory.iterdir():
        match = FILENAME.fullmatch(entry.name)
        if not match:
            continue
        try:
            metadata = entry.stat(follow_symlinks=False)
        except FileNotFoundError:
            continue
        if stat.S_ISREG(metadata.st_mode):
            recordings.setdefault(match[1], []).append((metadata.st_mtime_ns, metadata.st_ino, entry))

    for entries in recordings.values():
        for updated, inode, entry in sorted(entries, reverse=True)[1:]:
            if now - updated < GRACE_NS:
                continue
            try:
                fd = os.open(entry, os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK)
            except FileNotFoundError:
                continue
            try:
                try:
                    # Guacamole uses a POSIX write lock for the entire recording lifetime.
                    fcntl.lockf(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    continue
                metadata = os.fstat(fd)
                if metadata.st_ino == inode and metadata.st_mtime_ns == updated:
                    entry.unlink(missing_ok=True)
            finally:
                os.close(fd)


if __name__ == "__main__":
    result = subprocess.run(["docker", "volume", "inspect", "--format", "{{.Mountpoint}}", "workshop_screens"],
                            capture_output=True, text=True, timeout=10)
    if result.returncode == 0:
        prune(Path(result.stdout.strip()), time.time_ns())

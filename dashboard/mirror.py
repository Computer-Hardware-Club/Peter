"""Read bounded chunks of Guacamole's graphical session recordings."""

import base64
import os
from pathlib import Path
import re
import stat


CHUNK_SIZE = 192 * 1024
MAX_OFFSET = (1 << 53) - 1
LOW_SPACE = 16 * 1024 * 1024
RECORDING_LIMIT = 48 * 1024 * 1024
LIMIT_MARGIN = 64 * 1024
IDENTITY = re.compile(r"[a-z0-9-]{1,64}")
TOKEN = re.compile(r"[0-9a-f]{1,16}-[0-9a-f]{1,16}-[0-9a-f]{1,5}")


def read_recording(directory: Path, identity: str, token: str | None = None,
                   offset: int = 0) -> dict:
    if not isinstance(identity, str) or not IDENTITY.fullmatch(identity):
        raise ValueError("Invalid team identity.")
    if type(offset) is not int or not 0 <= offset <= MAX_OFFSET:
        raise ValueError("Invalid screen position.")
    if token is not None and (not isinstance(token, str) or not TOKEN.fullmatch(token)):
        raise ValueError("Invalid screen session.")

    # Rotation can free an earlier numeric suffix, which Guacamole then reuses.
    pattern = re.compile(re.escape(identity) + r"\.guac(?:\.([1-9][0-9]{0,4}))?")
    newest = None
    for entry in directory.iterdir():
        match = pattern.fullmatch(entry.name)
        if not match:
            continue
        try:
            metadata = entry.stat(follow_symlinks=False)
        except FileNotFoundError:
            continue
        if stat.S_ISREG(metadata.st_mode):
            candidate = (metadata.st_mtime_ns, int(match[1] or 0), entry)
            if newest is None or candidate > newest:
                newest = candidate
    storage = os.statvfs(directory)
    storage_low = storage.f_bavail * storage.f_frsize < LOW_SPACE
    empty = {"token": None, "offset": 0, "data": "", "more": False, "storageLow": storage_low}
    if newest is None:
        return empty

    _, suffix, entry = newest
    try:
        fd = os.open(entry, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return empty
    try:
        metadata = os.fstat(fd)
        if not stat.S_ISREG(metadata.st_mode):
            raise RuntimeError("Invalid screen recording.")
        current = f"{metadata.st_dev:x}-{metadata.st_ino:x}-{suffix:x}"
        if token != current or offset > metadata.st_size:
            offset = 0
        data = os.pread(fd, CHUNK_SIZE, offset)
        position = offset + len(data)
        return {"token": current, "offset": position, "data": base64.b64encode(data).decode("ascii"),
                "more": position < metadata.st_size,
                "storageLow": storage_low or metadata.st_size >= RECORDING_LIMIT - LIMIT_MARGIN}
    finally:
        os.close(fd)

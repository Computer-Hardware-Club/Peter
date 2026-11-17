#!/usr/bin/env python3
"""Prepare the new workshop tree while retaining local changes."""

from pathlib import Path
import shutil
import stat
import subprocess
import sys
from zipfile import ZipFile


EXTENSION = {"guac-manifest.json", "reset.js", "reset.css", "clipboard.js"}
JAR = Path("portal-reset/extensions/workshop-reset.jar")


def prepare(release, baseline, candidate):
    extra_assets = {}
    jar = candidate / JAR
    if jar.is_symlink() or any(parent.is_symlink() for parent in (jar.parent, jar.parent.parent)):
        raise SystemExit("Review the symlinked portal extension before applying.")
    if jar.is_file():
        with ZipFile(jar) as installed:
            for asset in installed.infolist():
                data = installed.read(asset)
                if asset.filename in EXTENSION:
                    # The JAR is the runtime source of truth on installs with
                    # locally patched extensions.
                    target = candidate / "portal-reset" / asset.filename
                    if target.is_symlink():
                        raise SystemExit(f"Review the symlinked extension source {asset.filename} before applying.")
                    target.write_bytes(data)
                else:
                    extra_assets[asset.filename] = data

    conflicts = []
    for source in sorted(release.rglob("*")):
        if not source.is_file():
            continue
        name = source.relative_to(release)
        if name == JAR:
            continue
        previous = baseline / name
        target = candidate / name
        incoming = source.read_bytes()
        if any((candidate / parent).is_symlink() for parent in name.parents):
            conflicts.append(str(name))
            continue
        if target.exists() or target.is_symlink():
            if previous.is_file() and incoming == previous.read_bytes():
                continue
            if target.is_symlink() or not target.is_file():
                conflicts.append(str(name))
                continue
            local = target.read_bytes()
            if incoming == local:
                continue
            if not previous.is_file():
                conflicts.append(str(name))
                continue
            if local != previous.read_bytes():
                merged = subprocess.run(
                    ["git", "merge-file", "-p", str(target), str(previous), str(source)],
                    capture_output=True, check=False,
                )
                if merged.returncode:
                    conflicts.append(str(name))
                    continue
                target.write_bytes(merged.stdout)
                continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    if conflicts:
        raise SystemExit("Reconcile local changes in the staged release before applying: " + ", ".join(conflicts))
    jar.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(jar, "w") as archive:
        for filename, data in extra_assets.items():
            archive.writestr(filename, data)
        for filename in sorted(EXTENSION):
            archive.write(candidate / "portal-reset" / filename, filename)

    reference = candidate / ".release-base"
    if reference.exists():
        shutil.rmtree(reference)
    shutil.copytree(release, reference)
    candidate.chmod(stat.S_IMODE(release.stat().st_mode))


if __name__ == "__main__":
    prepare(*(Path(arg) for arg in sys.argv[1:]))

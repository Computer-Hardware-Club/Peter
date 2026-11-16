"""Read the workshop manifest shared by the CLI and officer dashboard."""

import json
from pathlib import Path
import re
from urllib.parse import urlsplit

SLUG = re.compile(r"[a-z][a-z0-9-]{0,23}")
PACKAGE = re.compile(r"[a-z0-9][a-z0-9+.-]*")
DEFAULT_IMAGE = "debian-trixie"
DEFAULT_RESOURCES = {"vcpus": 2, "memory_mib": 2048, "disk_gib": 10}
RESOURCE_RANGES = {"vcpus": (1, 8), "memory_mib": (512, 8192), "disk_gib": (10, 40)}
PORTAL_CONFIG = Path("/etc/workshop/portal-url")


def portal_url():
    try:
        value = PORTAL_CONFIG.read_text().strip()
    except FileNotFoundError:
        return "https://workshop.computerhardwareclub.org/"
    url = urlsplit(value)
    if (any(character.isspace() for character in value) or not url.hostname
            or url.username is not None or url.query or url.fragment
            or not (url.scheme == "https" or (url.scheme == "http" and url.hostname in
                                             {"127.0.0.1", "localhost", "::1"}))):
        raise ValueError("Set /etc/workshop/portal-url to an HTTPS or loopback HTTP URL.")
    return value


def team_limit(resources):
    return min(4, 8 // resources["vcpus"], 8192 // resources["memory_mib"])


def template_names(directory):
    return sorted({entry.stem for entry in directory.glob("*.json") if SLUG.fullmatch(entry.stem)}
                  | {entry.parent.name for entry in directory.glob("*/workshop.json")
                     if SLUG.fullmatch(entry.parent.name)})


def load_template(directory, name):
    if not SLUG.fullmatch(name):
        raise ValueError("Template names must be lowercase slugs of up to 24 characters.")
    folder = directory / name
    manifest = folder / "workshop.json"
    legacy = not manifest.is_file()
    if legacy:
        manifest = directory / f"{name}.json"
    if not manifest.is_file():
        raise ValueError(f"Template {name} does not exist.")
    if not manifest.resolve().is_relative_to(directory.resolve()):
        raise ValueError(f"Template {name} is outside the template directory.")
    data = json.loads(manifest.read_text(encoding="utf-8"))
    allowed = {"image", "description"} if legacy else {"version", "description", "image", "packages", "init", "resources"}
    allowed.add("populate_home")
    if not isinstance(data, dict) or data.keys() - allowed:
        raise ValueError(f"Template {name} has unknown fields or is not a JSON object.")
    if not legacy and (type(data.get("version")) is not int or data["version"] != 1):
        raise ValueError(f"Template {name} must use version 1.")
    description = data.get("description", "" if legacy else None)
    if not isinstance(description, str) or (not legacy and not description.strip()):
        raise ValueError(f"Template {name} must have a description.")
    image = data.get("image", None if legacy else DEFAULT_IMAGE)
    if not isinstance(image, str) or not image.strip() or (not legacy and not SLUG.fullmatch(image)):
        raise ValueError(f"Template {name} has an invalid Incus image alias.")
    populate_home = data.get("populate_home", False)
    if type(populate_home) is not bool:
        raise ValueError(f"Template {name}: populate_home must be a boolean.")
    packages = data.get("packages", [])
    if not isinstance(packages, list) or any(not isinstance(pkg, str) or not PACKAGE.fullmatch(pkg) for pkg in packages):
        raise ValueError(f"Template {name} must list Debian package names.")
    if packages and image in {DEFAULT_IMAGE, "debian-trixie-base"}:
        raise ValueError(f"Template {name} needs a separate image alias for additional packages.")
    resources = data.get("resources", {})
    if not isinstance(resources, dict) or resources.keys() - RESOURCE_RANGES.keys():
        raise ValueError(f"Template {name} has unknown resource settings.")
    for key, value in resources.items():
        minimum, maximum = RESOURCE_RANGES[key]
        if type(value) is not int or not minimum <= value <= maximum:
            raise ValueError(f"Template {name}: {key} must be an integer from {minimum} to {maximum}.")
    script = None
    if "init" in data:
        if data["init"] != "init.sh":
            raise ValueError(f"Template {name} must name its initializer init.sh.")
        path = folder / "init.sh"
        if path.resolve().parent != manifest.resolve().parent or not path.is_file():
            raise ValueError(f"Template {name} is missing a local init.sh.")
        with path.open(encoding="utf-8") as source:
            script = source.read(65537)
        if not script.strip() or len(script.encode("utf-8")) > 65536:
            raise ValueError(f"Template {name}: init.sh must contain 1 to 65536 bytes of Bash.")
    return {"description": description, "image": image, "packages": packages,
            "resources": {**DEFAULT_RESOURCES, **resources}, "init": script,
            "populate_home": populate_home}

# Workshop VM templates

A template describes the changes a workshop needs on top of the club’s Debian 13 VM. Put each template in its own directory under `templates/`. The [hello-lab example](../templates/hello-lab/) uses the default image and adds a first-boot script and resource overrides.

```text
templates/
  hello-lab/
    workshop.json
    init.sh
```

The directory name becomes the template ID used by the CLI and officer dashboard. Start it with a lowercase letter and use up to 24 lowercase letters, digits, or hyphens. The [JSON Schema](workshop.schema.json) describes the manifest for editor validation.

| Manifest field | Meaning |
| --- | --- |
| `version` | Required. Set to `1`. |
| `description` | Required. Short description shown to officers. |
| `image` | Optional local Incus VM image alias. Defaults to `debian-trixie`. |
| `packages` | Optional list of extra Debian package names. When nonempty, set `image` to a distinct alias for the derived image, such as `shell-lab`. |
| `populate_home` | Optional boolean. Defaults to `false`. Set to `true` to create Desktop, Documents, Downloads, Music, Pictures, Public, Templates, and Videos in each team user’s home before `init.sh` runs. The home directory and SSH setup are available with either value. Also supported in flat JSON templates. |
| `init` | Optional. Set to `"init.sh"` to run that file from the same directory. |
| `resources.vcpus` | Optional integer from 1 to 8. Defaults to 2 per VM. |
| `resources.memory_mib` | Optional integer from 512 to 8192. Defaults to 2048 MiB per VM. |
| `resources.disk_gib` | Optional integer from 10 to 40. Defaults to 10 GiB per VM. |

The whole workshop is limited to four VMs, 8 vCPUs, and 8192 MiB of RAM. A template with 4 vCPUs and 4096 MiB per team can run two teams at once. Disk allocation also depends on the host’s free space.

For a template that adds packages, the manifest might look like this:

```json
{
  "version": 1,
  "description": "Shell exercises with jq and tree",
  "image": "shell-lab",
  "packages": ["jq", "tree"],
  "init": "init.sh",
  "resources": { "vcpus": 2, "memory_mib": 2048, "disk_gib": 12 }
}
```

Use the package list for software that needs to be downloaded. The image builder fetches signed Debian packages on the host and installs them in a builder VM without a network interface. Use `init.sh` for local setup such as creating lab files, applying configuration, or preparing an exercise. Peter runs the script with Bash as root inside each guest before enabling team access. The guest has no internet access, so use the build step for package downloads. The script runs once for each new VM and again when a reset replaces it. If the script fails, the team does not become ready and an officer can retry it.

Review the script before installing someone else’s template. Keep it under 64 KiB and allow enough time for the VM to boot and finish the script within the three-minute readiness window. Keep tokens, passwords, and private workshop materials out of public template files.

## Validate, install, and run

From a checkout, validate your definition without root:

```sh
./workshop validate-template hello-lab
```

Install the entire template directory to the root-owned catalog on a server that already runs Peter. You can also install bundled templates by running `sudo ./install.sh` from the checkout.

```sh
sudo install -d -m 0755 /opt/workshop/templates/hello-lab
sudo install -m 0644 templates/hello-lab/{workshop.json,init.sh} /opt/workshop/templates/hello-lab/
sudo workshop deploy intro-shell --template hello-lab --teams 2
```

If your template declares extra packages, build its image between events after installing the manifest:

```sh
sudo workshop build-template shell-lab
sudo workshop deploy shell-tools --template shell-lab --teams 2
```

The dashboard lists an installed template once its image alias is available. Peter pins the image fingerprint, initialization script, resources, and home-folder setting when you start the event. Changes to the source template apply to the next event. Keep the pinned image available until the current event ends.

Older flat manifests such as [test-vm.json](../templates/test-vm.json) still work. Use the directory format for new templates.

# Create a workshop VM template

A Peter template describes what each team gets when its Debian 13 VM starts. You can write a template on your workstation, give it to an officer for a workshop, or share it as a pull request. This tutorial starts with a working example and turns it into a one-team test event.

1. [Create the starter files](#1-create-the-starter-files)
2. [Customize the VM and handout](#2-customize-the-vm-and-handout)
3. [Validate on your workstation](#3-validate-on-your-workstation)
4. [Install the template on your server](#4-install-the-template-on-your-server)
5. [Run a test workshop](#5-run-a-test-workshop)

## 1. Create the starter files

You need Git, Python 3.12 or later, and Bash. Run the workstation commands on Linux, macOS, or Windows Subsystem for Linux. A normal user account is enough to create and validate the files. For steps 4 and 5, use a test server with Peter installed or ask an officer with administrative SSH access to help.

Clone the repository, or start in the root of an existing checkout.

```sh
git clone https://github.com/Computer-Hardware-Club/Peter.git
cd Peter
./workshop new-template shell-tools --description "Practice exploring files and JSON"
```

The command creates these files next to the bundled templates.

```text
templates/
  shell-tools/
    workshop.json
    init.sh
```

`shell-tools` is the template ID. Officers use it with `workshop deploy --template`. The dashboard displays the ID unless the manifest includes a label. Choose an ID that starts with a lowercase ASCII letter and is at most 24 characters long. Use lowercase ASCII letters, digits, and hyphens. The command refuses to replace an existing template.

## 2. Customize the VM and handout

Open `templates/shell-tools/workshop.json` in your editor. The starter uses the standard `debian-trixie` image with the default VM size. Its initializer, `init.sh`, creates a short lab handout. To teach a workshop that only needs the default software, edit the description and handout and go straight to validation.

### Add programs with `packages`

For this walkthrough, give teams `jq` and `tree`. Save this complete manifest as `templates/shell-tools/workshop.json`.

```json
{
  "version": 1,
  "description": "Practice exploring files and JSON with tree and jq",
  "image": "shell-tools",
  "packages": ["jq", "tree"],
  "init": "init.sh"
}
```

The template ID and image alias can share a name. The alias is the label Incus uses for the built VM image. Choose an alias unique to your template on the host. With a nonempty `packages` list, you must specify an alias other than the two reserved Debian aliases, `debian-trixie` and `debian-trixie-base`. Use names from the Debian 13 repositories configured by the builder. Use the package list for required software so Peter can fetch and verify the packages on the host and install them before the VM boots for participants. The template builder uses a separate VM without a network interface.

### Prepare team files with `init.sh`

Open `templates/shell-tools/init.sh`. Keep the code that looks up the team account and creates `~/lab`. Replace the text between the `EOF` markers with your exercise. Leave the closing `EOF` at the start of its line.

```text
Welcome to Shell Tools.

Run tree ~/lab to inspect the lab directory.
Run printf '%s\n' '{"team":"practice","ready":true}' | jq '.ready'
Open this handout with nano ~/lab/README.txt and make an edit.
```

Peter runs `init.sh` with Bash as root from `/root` after cloud-init has created the guest's `team-N` account. Each VM gets one team account. The starter looks it up with `getent passwd` and sets ownership so a team can edit the handout. Use the discovered home path when adding files to a team's home. During initialization, `~` refers to root's home. For a command that needs to run as the team, use `runuser -u "$team_user" -- COMMAND` and pass explicit paths.

Keep the initializer offline. A standard Peter guest has no internet access, and templates that depend on a download can fail before participants can sign in. Put Debian packages in the manifest and embed small exercise files in the script. Peter transfers the initializer's contents to the guest. Sibling files in the source template directory stay on the host. Save `init.sh` as UTF-8 with Unix line endings and keep it within 64 KiB.

The script runs before Peter grants portal access, including on each replacement VM created by a reset. It should exit promptly with a nonzero status on failure. Keep the total VM boot and initialization within the roughly three-minute readiness window. Leave the guest account, SSH configuration, and cloud-init intact. Review an initializer before installing it and keep credentials, participant data, and private material out of a shared template.

If you only need packages or VM sizing, remove the `"init": "init.sh"` entry from the manifest and leave out the script. Check the remaining JSON for a trailing comma.

### Manifest reference

Use [the JSON Schema](workshop.schema.json) for editor validation. JSON uses double quotes for strings and field names and permits neither comments nor trailing commas. The CLI also checks the initializer file and its Bash syntax.

| Field | Required | Meaning |
| --- | --- | --- |
| `version` | Yes | Set to the integer `1`. |
| `label` | No | Nonblank name shown in the officer dashboard. Defaults to the template ID. |
| `description` | Yes | Write a short, nonblank sentence that tells officers what the template is for. |
| `image` | With extra packages | Local Incus VM image alias. Defaults to `debian-trixie`. Use the same naming rules as for the template ID. |
| `packages` | No | Array of extra Debian package names. Defaults to an empty list. Use plain names such as `jq`, without versions or architecture qualifiers. |
| `init` | No | Set to `"init.sh"` to include the initializer next to the manifest. |
| `populate_home` | No | Boolean. Set to `true` to create Desktop, Documents, Downloads, Music, Pictures, Public, Templates, and Videos in the team home before initialization. Defaults to `false`. |
| `resources.vcpus` | No | Integer from 1 to 8. Defaults to 2 per team. |
| `resources.memory_mib` | No | Integer from 512 to 8192. Defaults to 2048 MiB per team. |
| `resources.disk_gib` | No | Integer from 10 to 40. Defaults to 10 GiB per team. Available host storage also limits deployment. |

Put resource overrides inside a single `"resources"` object, for example `"resources": {"disk_gib": 12}`. The workshop can allocate up to four VMs, 8 vCPUs, and 8192 MiB RAM in total. With 4 vCPUs and 4096 MiB per VM, an event can run two teams. Omitted resource settings retain their defaults.

Older flat files in the form `templates/<id>.json` still load. Use `templates/<id>/workshop.json` for new templates.

<a id="validate-install-and-run"></a>

## 3. Validate on your workstation

From the same checkout where you wrote the files, run:

```sh
./workshop validate-template shell-tools
```

For the package example, expect:

```text
shell-tools: valid template; image shell-tools; up to 4 team(s)
```

Validation checks the manifest fields, the initializer's presence and size, and Bash syntax. A successful check means you can hand the files to an officer. Package availability, the VM boot, and the exercise itself are checked on a test server. Run validation again after editing the files.

## 4. Install the template on your server

Use a test host or coordinate a window between workshops with the officer who runs the shared host. The steps below install a single template into an existing Peter installation. An administrator can use the same steps for a private template.

On your workstation, substitute your SSH destination for `YOUR_SERVER`. Use a transfer directory that does not already exist in the remote account's home.

```sh
scp -r templates/shell-tools YOUR_SERVER:~/shell-tools
ssh YOUR_SERVER
```

On the server, review the transferred files and run the following as a user with sudo access. The first command in the chain creates a new catalog directory and stops the copy if that directory already exists. Install the manifest last so the catalog can see the template after its initializer is present. For a manifest-only template, leave out the line that installs `init.sh`.

```sh
source_dir="$HOME/shell-tools"
catalog_dir=/opt/workshop/templates/shell-tools
sudo mkdir -m 0755 "$catalog_dir" &&
    sudo install -m 0644 "$source_dir/init.sh" "$catalog_dir/init.sh" &&
    sudo install -m 0644 "$source_dir/workshop.json" "$catalog_dir/workshop.json"
```

Validate the installed files with the server's CLI. For a template with extra packages, also run the second and third commands to build the new image and confirm the alias exists. A template using the already installed `debian-trixie` image only needs the first command.

```sh
sudo workshop validate-template shell-tools
sudo workshop build-template shell-tools
sudo incus --force-local --project workshop image alias list
```

Peter only builds template images between events. Wait until `sudo workshop status` shows `No workshop event.` and leave anyone else's event running until its owner ends it. The officer dashboard lists the template when its installed manifest loads and its image alias points to an Incus VM image in the `workshop` project. You can also use a trusted existing image prepared according to the [custom image requirements](operations.md#templates).

Templates bundled in the repository can also be installed by a maintainer using the [normal release process](operations.md#stage-apply-and-roll-back-a-release).

## 5. Run a test workshop

On a server with no active event, open the [officer dashboard](dashboard.md#run-a-workshop), enter `shell-tools-test`, select the `shell-tools` template, and start one team. The same test can be started and inspected over administrative SSH.

```sh
sudo workshop status
sudo workshop deploy shell-tools-test --template shell-tools --teams 1
sudo workshop status
sudo workshop credentials --team 1
```

When Team 1 is ready, open the participant portal using the URL from the credentials command or the dashboard. Sign in with the test team's credentials and run the commands below in the browser terminal. Skip the package checks if your template has no extra packages.

```sh
id -un
cat ~/lab/README.txt
test -w ~/lab/README.txt && echo "Handout is writable"
tree ~/lab
printf '%s\n' '{"ready":true}' | jq '.ready'
```

You should see `team-1`, the handout you wrote, a writable-file confirmation, and `true` from `jq`. Try the actual exercises from the participant account. To verify that a reset gives the next team a clean copy, append a line to the handout in the browser terminal and use **Reset VM** for the test team. The equivalent officer command is `sudo workshop reset --team 1 --yes`. Sign in again if prompted and confirm the extra line is gone and the original handout and programs are available.

When you finish, verify that the active event is `shell-tools-test`, then use **End workshop** or `sudo workshop destroy --yes`. Ending the event removes its guest disks and credentials. The image and template remain available.

Peter saves the image fingerprint, initializer content, home-folder setting, and resources at deployment. Adding or resetting a team uses those saved settings. To test an updated template, validate and install the revised files between events, build a new image if the package list changed, and start a new event. If you want to keep two image versions available, give the revised image a new alias such as `shell-tools-v2`. Keep any image pinned by a current event available until the event ends.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| The command says the template does not exist | Validate from the checkout where you created it or use `sudo workshop validate-template` for the installed copy. Check the ID and the exact filename `workshop.json`. |
| Validation rejects the manifest | Check field spelling, required values, and JSON punctuation. Verify that a nonempty package list has a distinct image alias. |
| Validation rejects the initializer | Confirm that `init.sh` is next to the manifest and that the manifest names it exactly. Run `bash -n templates/shell-tools/init.sh` to locate a Bash syntax error. |
| The template is absent from the dashboard | Validate the installed manifest on the server and check that its image alias exists as a VM image. Build package images between events. |
| The dashboard offers fewer teams than expected | Check the resource settings and the team limit from validation. Reduce per-VM CPU or memory if the exercises can run with less. |
| The image build fails | Check for an active event first. Then read the build output and check that the requested packages exist for Debian 13 on the host's architecture and that the host can reach its package repositories. |
| A test team shows **Needs retry** | Inspect `sudo incus --force-local --project workshop exec ws-team-1 -- tail -n 100 /var/log/cloud-init-output.log` on the server while the test VM exists. Fix and validate the source files. If the initializer itself changed, end your test event and start a new one to pick up the new script. |

If you want others to reuse your template, include participant instructions and your test results in the [pull request](CONTRIBUTING.md#submit-a-pull-request).

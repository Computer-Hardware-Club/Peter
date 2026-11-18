# Contributing to Peter

You can contribute workshop templates, documentation, fixes, and improvements to the officer or participant experience. A template or documentation change can be developed on a laptop. Changes to provisioning, networking, the portal stack, and releases also need testing in an environment that matches the parts they affect.

## Set up a development checkout

1. Fork [Peter on GitHub](https://github.com/Computer-Hardware-Club/Peter).
2. Replace `YOUR_GITHUB_USERNAME` below with your GitHub username, then clone your fork and create a branch from the upstream default branch. Use a name that describes your change.

   ```sh
   git clone https://github.com/YOUR_GITHUB_USERNAME/Peter.git
   cd Peter
   git remote add upstream https://github.com/Computer-Hardware-Club/Peter.git
   git fetch upstream
   git switch -c shell-tools-template upstream/main
   ```

3. Use Linux, macOS, or Windows Subsystem for Linux with Git, Bash, and Python 3.12 or later. The repository's Python checks use the standard library. For the JavaScript checks, use Node.js 24, the version used by the repository's CI.
4. Run commands from the root of your checkout unless a guide tells you to use a server. Keep the checkout separate from the installed application under `/opt/workshop`.

The [template tutorial](templates.md) takes you from an empty template to a browser-tested event. You can complete the authoring and validation steps locally. If you have no test host, ask for an officer to test the VM and say which checks you ran in your pull request.

## Find the part you want to change

| Path | What it does |
| --- | --- |
| [`templates/`](../templates/) | Bundled workshop definitions and the starter initializer. |
| [`workshop`](../workshop) and [`workshop_templates.py`](../workshop_templates.py) | Officer CLI, event lifecycle, and shared template parsing. |
| [`build-template.sh`](../build-template.sh) and [`guest/`](../guest/) | Debian image building and files supplied to guests. |
| [`dashboard/`](../dashboard/) | Officer web UI, Python HTTP server, and privileged host socket handler. |
| [`portal-reset/`](../portal-reset/) | Guacamole browser extension for terminal reset, reconnect, and clipboard controls. |
| [`infra/`](../infra/), [`install.sh`](../install.sh), and [`install-dashboard.sh`](../install-dashboard.sh) | Compose, systemd, firewall rules, guacd build, and deployment. |
| [`tests/`](../tests/) and [the Verification workflow](../.github/workflows/verification.yml) | Local regression tests and disposable integration environments. |
| [`docs/`](./) | Template, operations, dashboard, and verification guides. |

Keep the change focused on one issue or workshop. When changing a command, manifest field, or officer workflow, update the guide people follow. When adding a template, use its own directory with a short description, an initializer only if needed, and a distinct image alias if it adds packages. Include enough instructions that a second person can run the exercise from a fresh VM. Keep generated images and build artifacts outside the repository.

## Check your change

Run the checks that cover your change. These examples work from a regular checkout without touching a running workshop.

```sh
git diff --check
./workshop validate-template hello-lab
./workshop validate-template test-vm
python3 -m unittest discover -s tests -q
node --test portal-reset/*.test.js
```

- **Templates** should also pass `./workshop validate-template YOUR_TEMPLATE_ID`. Replace `YOUR_TEMPLATE_ID` with the new directory name. If you have a test host, run the [one-team acceptance steps](templates.md#5-run-a-test-workshop) including reset. Check that the exercise files are readable and editable by the participant where appropriate.
- **Python and shell** changes should use the Python suite and `bash -n PATH_TO_CHANGED_SCRIPT` for each changed Bash script. Use a disposable Peter host for a change that depends on Incus, network routing, or systemd.
- **Dashboard and terminal** changes should exercise the relevant browser workflow, using a disposable event if VMs are needed. For changes affecting clipboard, terminal recovery, or the portal stack, see [verification and integration checks](verification.md#current-regression-checks). Share screenshots for visible changes where they help reviewers, with private host and team information removed.
- **Installer and release** changes should use the disposable runner checks in the Verification workflow. The release fixture changes system services and installation directories. Run it only on a disposable Ubuntu runner.

If a check needs equipment or access you lack, say which check it was and what remains to be verified. Use fabricated data in examples and logs. Keep team credentials, dashboard passwords, tokens, and private terminal recordings out of issues and pull requests.

## Submit a pull request

1. Review the changes with `git status --short` and `git diff`. Stage only the intended files. For a template, for example:

   ```sh
   git add templates/shell-tools/
   git diff --cached --check
   git commit -m "Add Shell Tools workshop template"
   git push -u origin shell-tools-template
   ```

2. On GitHub, open a pull request from your fork's branch into `Computer-Hardware-Club/Peter` on `main`. Describe the problem or teaching goal, what changed, and how you verified it. Link any related issue.
3. For a template, give the template ID, expected team count, required packages or services, and the commands or exercises a reviewer can try. Report whether you tested the browser login, the exercise, and reset on a real VM.
4. Review the Verification results. If a maintainer requests changes, commit and push to the same branch to update the pull request.

The maintainers handle deployment to the club's Peter host. A template can also be [installed privately on a self-hosted server](templates.md#4-install-the-template-on-your-server) without submitting it upstream.

## Report a problem

For an ordinary bug, use [GitHub Issues](https://github.com/Computer-Hardware-Club/Peter/issues). Include the Peter revision if known, the host OS for install issues, the browser and OS for portal issues, and the steps and expected result. Redact account data and secrets from logs. For problems involving the club's live workshop or a possible exposure of credentials, contact a club officer privately.

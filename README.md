# Computer Hardware Club workshop platform

Peter runs one workshop at a time with up to four Debian 13 KVM virtual machines. Each team signs in to Guacamole with its team number and password. The VM accepts one active browser terminal at a time. Inside the guest, the prompt is `team-N@peter` and the team can run `sudo` without a password. Nano and `chcfetch` are included in the default template.

## Officer quick start

Use the [officer dashboard](docs/dashboard.md) to start a workshop, add or remove teams, copy team logins, view terminal output, or refresh a VM. The dashboard starts from the standard Debian `test-vm` image.

The same operations are available in your administrative SSH session on Peter.

```sh
sudo workshop deploy linux-basics --teams 4
sudo workshop status
sudo workshop credentials --team 1
```

Repeat the credentials command for each team and share the login privately with that team. Participants open the workshop portal and sign in once with their team username and password. They select their team’s SSH connection if Guacamole shows the connection list. [Workshop portal](https://workshop.computerhardwareclub.org/)

Officers can also forward the loopback portal over their existing SSH connection and open [the local portal](http://127.0.0.1:18080/).

```sh
ssh -N -L 127.0.0.1:18080:127.0.0.1:8080 192.168.1.12
```

```sh
sudo workshop add
sudo workshop reset --team 2 --yes --keep-password
sudo workshop credentials --team 2
sudo workshop remove --team 2 --yes
sudo workshop reset --all --yes
sudo workshop destroy --yes
```

Reset replaces the selected VM from the event’s pinned image. The participant’s open terminal shows reset progress and reconnects when the fresh VM is ready. The team keeps its password by default. Use `--rotate-password` when you need to issue a new password instead. Destroy revokes all event logins and removes the team VMs, guest disks, bridges, saved credentials, and event database history. The image catalog, database service, firewall, and portal stay available between workshops.

- [Operations, templates, and recovery](docs/operations.md)
- [Cloudflare configuration and recovery](docs/cloudflare.md)
- [Peter audit and acceptance checks](docs/verification.md)
- [Workshop work list](docs/work-list.md)

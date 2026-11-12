# Computer Hardware Club workshop platform

Peter runs a single workshop at a time with one to four Debian 13 KVM virtual machines. Each team gets its own VM and Guacamole login. The VM accepts one active browser terminal at a time. Inside the guest, `student` can run `sudo` without a password.

## Officer quick start

Use the [officer dashboard](docs/dashboard.md) to start a workshop, add or remove teams, copy team logins, view terminal output, or refresh a VM. The dashboard starts from the standard Debian `test-vm` image.

The same operations are available in your administrative SSH session on Peter.

```sh
sudo workshop deploy linux-basics --teams 4
sudo workshop status
sudo workshop credentials --team 1
```

Repeat the credentials command for each team and share the login privately with that team. Participants open [workshop.computerhardwareclub.org](https://workshop.computerhardwareclub.org/), enter the one-time code sent to their `@oregonstate.edu` email, and sign in to Guacamole with the team credentials. They select their team’s SSH connection if Guacamole shows the connection list.

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

Reset replaces the selected VM from the event’s pinned image and drops its live terminal session. The dashboard preserves the team password on reset. Destroy revokes all event logins and removes the team VMs, guest disks, bridges, saved credentials, and event database history. The image catalog, database service, firewall, and portal stay available between workshops.

- [Operations, templates, and recovery](docs/operations.md)
- [Cloudflare configuration and recovery](docs/cloudflare.md)
- [Peter audit and acceptance checks](docs/verification.md)

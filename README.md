# Computer Hardware Club workshop platform

Peter runs a single workshop at a time with two to four Ubuntu 24.04 LTS KVM virtual machines. Each team gets its own VM and Guacamole login. The VM accepts one active browser terminal at a time. Inside the guest, `student` can run `sudo` without a password.

## Officer quick start

Run these commands in your existing administrative SSH session on Peter.

```sh
sudo workshop deploy linux-basics --teams 4
sudo workshop status
sudo workshop credentials --team 1
```

Repeat the credentials command for each team. Send each login privately to the corresponding team. Once the administrator has configured Cloudflare, participants use [workshop.computerhardwareclub.org](https://workshop.computerhardwareclub.org/) and sign in to Cloudflare Access, then to Guacamole. They select their team’s SSH connection if Guacamole shows the connection list.

Before Cloudflare is configured, officers can forward the loopback portal over their existing SSH connection and open [the local portal](http://127.0.0.1:18080/).

```sh
ssh -N -L 127.0.0.1:18080:127.0.0.1:8080 192.168.1.12
```

```sh
sudo workshop reset --team 2 --yes
sudo workshop credentials --team 2
sudo workshop reset --all --yes
sudo workshop destroy --yes
```

Reset replaces the selected VM from the event’s pinned image, drops its live terminal sessions, and rotates its portal password and SSH keys. Destroy revokes all event logins and removes the team VMs, guest disks, bridges, saved credentials, and event database history. The image catalog, database service, firewall, and portal stay available between workshops.

- [Operations, templates, and recovery](docs/operations.md)
- [Cloudflare administrator handoff](docs/cloudflare.md)
- [Peter audit and acceptance checks](docs/verification.md)

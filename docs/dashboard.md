# Officer dashboard

Peter’s officer dashboard uses Tailscale Serve. Open Peter’s Tailscale HTTPS hostname from a device signed in with the configured account, then enter the officer password. Other Tailscale identities are denied before the sign-in page. The participant portal has a separate address and login.

Read the officer password over Peter's administrative SSH connection.

```sh
ssh -t YOUR_SERVER 'sudo cat /etc/workshop/dashboard/officer-password'
```

On a self-hosted server installed in SSH-forwarding mode, open an SSH forward and visit [the forwarded dashboard](http://127.0.0.1:8090/). Keep the SSH connection open while using it.

```sh
ssh -N -L 127.0.0.1:8090:127.0.0.1:8090 YOUR_SERVER
```

## Run a workshop

1. Sign in, enter a workshop name, choose `test-vm` or an [installed workshop template](templates.md), and select the number of teams. The default is a minimal Debian 13 VM with SSH, sudo, and the Incus agent.
2. As each team shows **Ready**, open **Team login** and use **Copy password** to share the password privately. The portal username is the team number. Participants see the Computer Hardware Club title above their `team-N@peter` prompt. If a team shows **Needs retry**, select it and use **Retry VM**. The other teams can connect while it rebuilds.
3. Use **Add team** or **Remove team** as attendance changes. The other teams keep their running VMs and credentials. Each VM accepts one active browser terminal.
4. Select a team to mirror its screen, or open **All terminals** for a tiled view. The dashboard renders Guacamole’s graphical output, including full-screen applications and colors. Officers can see the screen without taking a participant connection or sending input. Tell participants about monitoring before they begin.
5. Use **Reset VM** to rebuild a team with the event’s original image, initialization script, and VM resources. The participant’s open terminal shows reset progress and reconnects automatically to the fresh VM. The team keeps its password, and the other VMs continue running.
6. Use **End workshop** to remove the VMs, team logins, and screen recordings.

Screen recordings are stored in a shared 512 MiB memory volume and survive a team reset. The dashboard shows the latest session for each team and warns when space runs low. Removing a team or ending the workshop clears the corresponding files. Restarting guacd or Peter clears the memory volume.

If the participant portal is unavailable, the dashboard still shows the VM roster and marks session status unknown. Team login becomes available again once the portal is healthy and the VM is running. If screen updates stop, **Stale** marks the last available frame.

## Install or restore

Install the workshop platform first. From a trusted checkout on a host already connected to Tailscale, run the following with the hostname and allowed login from `tailscale status --json`.

```sh
sudo ./install-dashboard.sh --tailscale YOUR_HOST.YOUR_TAILNET.ts.net YOUR_LOGIN
sudo tailscale serve --bg --https=443 http://127.0.0.1:18090
sudo tailscale serve status
```

The Serve status should say **tailnet only**. This mode disables the old LAN and SSH dashboard listeners and permits only Tailscale’s privileged daemon to reach the loopback backend. Keep the dashboard off Funnel and the public Cloudflare tunnel. See the [Tailscale Serve documentation](https://tailscale.com/docs/features/tailscale-serve) for HTTPS setup and how it forwards the account identity.

For SSH forwarding on a self-hosted server, run `sudo ./install-dashboard.sh` with no arguments. For optional LAN HTTPS, pass the LAN address and prefix, then retrieve and trust the server’s local CA at `/etc/workshop/dashboard/lan-ca.crt`. The installer retains the existing officer password in all three modes.

Check both services with `sudo systemctl status workshop-dashboard.service workshop-dashboard-host.socket`. To rotate the officer password, replace `/etc/workshop/dashboard/officer-password` with a new secret of at least 12 characters and restart the dashboard. Existing officer sessions end when the service restarts.

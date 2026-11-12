# Officer dashboard

On Peter's LAN, open [the officer dashboard](https://192.168.1.12:8443/) after trusting its local CA. The dashboard also works over an SSH forward, including from a Tailscale client if Peter is joined to the tailnet and reachable over SSH. It uses a separate address and password from the public participant portal.

Read the officer password over Peter's administrative SSH connection.

```sh
ssh -t 192.168.1.12 'sudo cat /etc/workshop/dashboard/officer-password'
```

For a browser connection without installing a local CA, open an SSH forward and visit [the forwarded dashboard](http://127.0.0.1:8090/). Keep the SSH connection open while using it.

```sh
ssh -N -L 127.0.0.1:8090:127.0.0.1:8090 192.168.1.12
```

For direct LAN access, retrieve the public CA certificate over the same SSH connection. On macOS, import it into your login keychain and set its SSL trust in Keychain Access. Verify that the certificate came from Peter before trusting it. The LAN certificate is valid for one year. When the installer issues a replacement, import its new CA.

```sh
ssh 192.168.1.12 'sudo -n cat /etc/workshop/dashboard/lan-ca.crt' > peter-workshop-ca.crt
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

Install the workshop platform first, then run `sudo ./install-dashboard.sh 192.168.1.12/24` from a trusted checkout. Substitute the replacement host's LAN address and subnet. Omit the address to enable SSH forwarding only. The installer retains the existing officer password. Keep this dashboard off the public Cloudflare tunnel.

Check both services with `sudo systemctl status workshop-dashboard.service workshop-dashboard-host.socket`. To rotate the officer password, replace `/etc/workshop/dashboard/officer-password` with a new secret of at least 12 characters and restart the dashboard. Existing officer sessions end when the service restarts.

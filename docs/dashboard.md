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

1. Sign in, enter a workshop name, choose `test-vm`, and start with one to four teams. The default is a minimal Debian 13 VM with SSH, sudo, and the Incus agent.
2. When a team shows **Ready**, open **Team login**, choose **Copy team login**, and send the details privately in Discord or another channel you already use. The copied text includes the workshop link, username, and password.
3. Use **Add team** or **Remove team** as attendance changes. The other teams keep their running VMs and credentials. Each VM accepts one active browser terminal.
4. Select a team to see its current connection state and live or recent terminal output. Guacamole records what the browser terminal receives, including commands echoed by the shell and their results. Commands that run without appearing in that terminal are outside the recording. Tell participants about monitoring before they begin.
5. Use **Reset VM** to rebuild a team from the event's original image. The old terminal disconnects and the team can reconnect with the same credentials once the replacement is ready. The other VMs continue running.
6. Use **End workshop** to remove the VMs, team logins, and transcripts.

The dashboard shows the last 64 KiB of the most recent terminal session for the selected team. Recordings are stored in a shared 64 MiB memory volume and survive a team reset. The dashboard warns when recording space runs low. Removing a team or ending the workshop clears the corresponding files. Restarting guacd or Peter clears the memory volume.

## Install or restore

Install the workshop platform first, then run `sudo ./install-dashboard.sh 192.168.1.12/24` from a trusted checkout. Substitute the replacement host's LAN address and subnet. Omit the address to enable SSH forwarding only. The installer retains the existing officer password. Keep this dashboard off the public Cloudflare tunnel.

Check both services with `sudo systemctl status workshop-dashboard.service workshop-dashboard-host.socket`. To rotate the officer password, replace `/etc/workshop/dashboard/officer-password` with a new secret of at least 12 characters and restart the dashboard. Existing officer sessions end when the service restarts.

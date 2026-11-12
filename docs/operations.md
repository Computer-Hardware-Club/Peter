# Operations and recovery

## Layout

| Component | Location |
| --- | --- |
| Officer dashboard | `https://192.168.1.12:8443/` on the LAN or SSH forwarding to loopback TCP 8090 |
| Officer command | `/usr/local/sbin/workshop` |
| Root-owned install | `/opt/workshop` |
| Incus VM project and directory storage pool | `workshop` |
| Event credentials and stack passwords | `/var/lib/workshop`, root-only |
| Tunnel credential | `/etc/workshop/tunnel-token`, root-only, installed by the administrator |
| Portal origin | `http://127.0.0.1:8080/` on Peter |

Use Peter’s existing SSH access for administration. Root and the `incus-admin` and Docker groups can administer the host. Keep these privileges with trusted officers. Guacamole has only temporary team accounts with permission to read their own connection. The application has no Guacamole administrator account. PostgreSQL, guacd, and the Incus API have no externally published listeners.

Each VM has 2 vCPUs, 2 GiB of RAM, and a 10 GiB virtual root disk. The Incus project caps allocation at four VMs, eight vCPUs, and 8 GiB RAM. Deployment checks room for the selected disks plus a 16 GiB host reserve. Storage is sparse, so monitor real free space on the host. The portal services have container memory and process limits, and their Docker logs rotate.

Each team has a separate `wks1`–`wks4` bridge with a private /30, one VM NIC, and static guest configuration. Each guest gets a single return route to guacd. The host firewall drops traffic to host listeners and routed traffic across the workshop bridges, with an exception for SSH from guacd and the matching replies. The guest firewall is irrelevant to that decision. There is no guest NAT, DHCP, DNS, default gateway, or IPv6 route. The database uses an internal Docker network without a host gateway. The web application can read portal configuration and write session history. Officers manage accounts and connections through the dashboard or CLI. The firewall loads before Incus or Docker, and both services require it. Incus restores the VMs and the portal restarts under systemd.

## Templates

The default `test-vm` template points to the private Incus alias `debian-trixie`. The upstream Linux Containers Debian 13 cloud image is cached as `debian-trixie-base`. The builder downloads signed Debian packages on Peter, installs them through the VM agent into a VM with zero NICs, and removes the builder’s SSH host keys and cloud-init identity before publishing. The VM boots with a fresh host identity and team SSH key. To build a workshop with additional Debian packages, work between events.

```sh
sudo /opt/workshop/build-template.sh linux-networking tcpdump dnsutils iproute2
```

Add `templates/linux-networking.json` to Git and install that file to the root-owned copy at `/opt/workshop/templates/`. The dashboard lists the template as soon as both the manifest and its Incus image alias exist.

```json
{
  "image": "linux-networking",
  "description": "Debian with tcpdump and DNS utilities"
}
```

Deploy with `sudo workshop deploy networking --template linux-networking --teams 3`. The CLI records the complete image fingerprint at deployment. Keep that image until the event is over. The builder replaces the alias when rebuilding the same name. You can also import a trusted custom Incus VM image into the `workshop` project. Use Debian 13 with cloud-init and Incus VM agent support, include `openssh-server` and `sudo`, and remove passwords, authorized keys, machine identity, and SSH host keys before publishing. Never publish a team VM after participants have accessed it.

To update the upstream base, copy a fresh cloud image into the project under a temporary alias. Review its architecture and type, move `debian-trixie-base` to the new fingerprint, then rebuild your template aliases. Remove retired unreferenced images after verifying the replacement.

## Troubleshooting

```sh
sudo workshop status
sudo systemctl status workshop-firewall workshop-portal incus docker
sudo journalctl -u workshop-firewall -u workshop-portal -u incus -b
sudo nft list table inet workshop
sudo docker ps --filter label=com.docker.compose.project=workshop
sudo docker logs --tail 100 workshop-web-1
sudo docker logs --tail 100 workshop-guacd-1
sudo incus --project workshop list
sudo incus --project workshop exec ws-team-1 -- cloud-init status --long
sudo incus --project workshop exec ws-team-1 -- ip route
sudo incus --project workshop console ws-team-1 --show-log
df -h /var/lib/incus
```

- Teams provision independently. If a team still shows pending after the command exits, or reports that it needs a retry, fix the service or VM problem and use **Retry VM** or run `sudo workshop reset --team N --yes --keep-password`. The CLI serializes event mutations and checks Incus ownership before removing a resource. If the event state was lost and a reserved resource remains, verify its `user.workshop.run` marker and name in Incus before removing it manually. Review the database connection and login records before removing an orphan.
- For an SSH host key mismatch, reset the team from the pinned image. The portal pins each new VM’s Ed25519 host key before granting access.
- Test HTTP on Peter using `curl -fsS http://127.0.0.1:8080/ -o /dev/null`. If this works and the public hostname fails, check `sudo journalctl -u cloudflared.service -b`, Cloudflare connector health, and the hostname route and Access settings.
- Use `sudo systemctl reload workshop-firewall` to apply changes atomically to the workshop tables. Keep general firewall managers from flushing the full nftables ruleset while VMs are running.
- If the database initialization fails on a new host, inspect `sudo docker logs workshop-db-1`. Its health check requires the schema and the application role. Treat any existing volume as persistent data and preserve it before repair.
- A host reboot interrupts browser sessions. Participants can reconnect with the same team credentials after the portal and guests recover.

## Disaster recovery

Keep an off-host copy of this Git repository and export any custom images you cannot rebuild from Debian packages. Run the following with a protected off-host destination or a mounted backup target.

```sh
sudo incus --project workshop image export linux-networking /secure/backup/linux-networking
```

Keep the exported files together. Treat images with custom material as private. Normal workshop recovery creates a new event with fresh team logins. Event credentials, guest work, and portal history live on Peter and are disposable for that recovery path.

On an audited bare-metal Ubuntu 24.04 amd64 replacement with KVM, verify the workshop ranges and interface names in `infra/firewall.nft`, `infra/compose.yaml`, and `workshop` are available. The workshop uses `10.241.1.0/30` through `10.241.4.0/30`, `172.31.253.0/28`, `172.31.253.16/28`, `wks1`–`wks4`, `wks-guac`, and loopback TCP port 8080. Preserve the replacement host’s management network and existing firewall.

1. Transfer a trusted checkout of this repository. Run `sudo ./install.sh` from that checkout. It installs packages, the root-owned configuration, the default image, and the systemd units. It generates stack passwords on the host. Re-running the installer restarts the portal. Run `sudo ./install-dashboard.sh LAN_IP/PREFIX` to restore the officer dashboard.
2. Rebuild custom aliases from the documented packages, or import the trusted exported VM image into the `workshop` project with its original alias. Restore its manifest in `/opt/workshop/templates/`.
3. Reissue the Cloudflare Tunnel token or retrieve it from the administrator’s protected secret store. Install it and follow the [Cloudflare handoff](cloudflare.md).
4. Deploy a small test event, confirm browser SSH and isolation, then destroy it. Deploy the real event and distribute fresh credentials.

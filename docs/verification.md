# Peter audit and acceptance

## Read-only preflight

Audited November 10, 2026 over Peter’s existing SSH connection.

| Item | Finding |
| --- | --- |
| Hardware | Dell PowerEdge R620, two Intel Xeon E5-2670 processors, 16 physical cores and 32 logical CPUs |
| Memory | 31 GiB usable RAM and 8 GiB swap |
| OS | Bare-metal Ubuntu 24.04.5 LTS, amd64, kernel 6.8.0-149-generic |
| KVM | VT-x and EPT present, `kvm_intel` loaded, `/dev/kvm` present. QEMU QMP later reported KVM present and enabled. |
| Storage | 223 GiB PERC logical disk, 216 GiB ext4 root on LVM, 195 GiB available before installation, no unallocated VG space |
| Management | `eno1` via DHCP at `192.168.1.12/24`, default gateway `192.168.1.1`, OpenSSH on TCP 22 |
| Existing services | No existing Incus pool, Docker stack, or workshop firewall. IPv4 and IPv6 forwarding were already enabled, and UFW was inactive. |

Peter keeps its existing SSH, DHCP, interface configuration, and disk layout. The workshop uses at most eight vCPUs even though the hardware has more capacity. During the audit, Ubuntu’s `lxc` compatibility launcher unexpectedly began a snap install. The action was aborted and no LXD snap was installed.

## Local acceptance

Used a disposable four-team event on Peter and Chrome through the loopback SSH forward. The test authenticated to the actual Guacamole portal and sent commands through its WebSocket SSH terminal.

| Check | Result |
| --- | --- |
| Deploy and status | Four Incus virtual machines booted from the offline-built Ubuntu image. Each reported ready with its own bridge, SSH host identity, and browser account. |
| VM isolation | From root inside each VM, added a default route and attempted TCP to Peter’s SSH listener, the home router, a public IP, the portal containers, and all three peer VMs. Each attempt was blocked. Host nftables drop counters increased. |
| Proxy isolation | guacd reached TCP 22 on every VM. Probes to other guest ports, Peter’s SSH port, the home router, and a public IP were blocked. |
| Browser authorization | Each of the four logins listed one connection and ran a sudo command that wrote a root-owned marker in its assigned VM. Two simultaneous Team 1 terminals accepted commands. Cross-team lookup, private connection parameters, and the default admin login were denied. |
| LAN listeners | A second machine reached Peter’s SSH on TCP 22. Portal, guacd, PostgreSQL, and Incus ports 8080, 4822, 5432, and 8443 were closed on Peter’s LAN address. |
| Reset | Replaced Team 1. Its test file disappeared, its SSH host key and portal password changed, its old password failed, and its new password worked. Team 2 kept its boot ID and test file. |
| Reboot recovery | Rebooted Peter. Its boot ID changed from `2951e282-ab40-403a-8c60-abacc6caa453` to `03ddaa12-c624-4af9-b88e-3da4eb3c5353`. Four VMs and the portal recovered automatically. The firewall became active before Docker and Incus. Repeated all browser and isolation checks successfully. |
| IPv6 | Verified IPv6 is disabled on every team bridge. From each guest, added a link-local address and a static neighbor entry for a management IPv6 probe. TCP connection attempts remained blocked. |
| Resource ceiling | Attempted to create a fifth VM. Incus rejected it at the project VM-count limit and created no extra instance. |
| Teardown | Ran destroy twice. Verified zero team VMs, disks, bridges, event state, portal users, or connections. Reusable images and healthy infrastructure services remained. |
| Installer and configuration | Re-ran `install.sh` successfully. Validated Python compilation, shell syntax, Docker Compose configuration, systemd unit syntax, and nftables syntax. Verified root-only runtime secrets and a noninteractive CLI subprocess regression check. |

The original local acceptance tests ran before Cloudflare publication.

## Public hostname

On November 11, Cloudflare published `workshop.computerhardwareclub.org` through the healthy `peter-workshop` tunnel. Public DNS resolved, and Peter's enabled `cloudflared.service` received the route to `http://127.0.0.1:8080` with Access token validation. Unauthenticated HTTPS requests to the portal, login API, and WebSocket endpoint each redirected to Cloudflare Access. The Access page offered an email code, and the application's policy allows `@oregonstate.edu` addresses. An authenticated terminal through the public hostname remains to be verified with an OSU mailbox.

## One-terminal limit

On November 11, a disposable two-team event admitted the first Team 1 Guacamole WebSocket, rejected a second Team 1 connection, and admitted Team 2 concurrently. Closing Team 1's first terminal freed its slot for a new connection.

## Officer dashboard and Debian

On November 11, tested the deployed dashboard on Peter over LAN TLS and through the SSH forward. Verified officer authentication, cross-origin and CSRF rejection, and the desktop and mobile layouts in Chrome. Launched Debian 13 from `test-vm`, opened a Guacamole terminal, and saw a command and its output in the dashboard before disconnecting. Added and removed a second team while the first stayed connected. A stale team selection was rejected. Reset the first VM, verified its boot ID changed, reconnected using the same credentials, and confirmed the previous transcript remained available. A disposable guest with a default route could not reach the dashboard. Ending the event removed the test VMs, logins, and recordings. SMTP construction and TLS submission were checked with a test client. Peter has no production SMTP configuration.

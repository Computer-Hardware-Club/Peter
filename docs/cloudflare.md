# Cloudflare configuration and recovery

The portal is on Peter at `http://127.0.0.1:8080/`. Peter runs Cloudflare's dashboard-installed `cloudflared.service` for the `peter-workshop` tunnel. Check it with `sudo systemctl status cloudflared.service` and `sudo journalctl -u cloudflared.service -b`. The instructions below describe how to recreate the Cloudflare configuration or install a connector on a replacement host.

1. In Cloudflare Zero Trust, create a **Self-hosted** Access application for `workshop.computerhardwareclub.org`, with the path blank so the policy covers the entire origin. Enable **One-time PIN** and select it as the application's login method. Add an **Allow** policy with the **Emails ending in** rule set to `@oregonstate.edu`. Save the application and note its Application Audience (AUD) tag.
2. Use the **remotely managed Cloudflared tunnel** named `peter-workshop`. On a replacement host, follow the dashboard's service installation instructions or use the repository's `workshop-tunnel.service` with the prompt below. The prompt reads the token without terminal echo and stores it in a root-only file for systemd. Run one connector service per host.

   ```sh
   sudo bash -c '
       set -eu
       umask 077
       file=$(mktemp /etc/workshop/.tunnel-token-XXXXXXXX)
       trap "rm -f -- \"$file\"" EXIT
       IFS= read -rs -p "Tunnel token: " token
       printf "\n" >&2
       test -n "$token"
       printf "%s\n" "$token" > "$file"
       mv -f -- "$file" /etc/workshop/tunnel-token
   '
   sudo systemctl enable --now workshop-tunnel.service
   sudo systemctl status workshop-tunnel.service
   ```

3. In the tunnel’s **Published application routes**, add this route.

   | Setting | Value |
   | --- | --- |
   | Subdomain | `workshop` |
   | Domain | `computerhardwareclub.org` |
   | Path | Leave blank |
   | Service type | **HTTP** |
   | Service URL | `127.0.0.1:8080` |
   | Additional application settings → Access | **Protect with Access** enabled |
   | Access organization and application | Your Zero Trust team and the workshop app’s AUD tag |

   Confirm the resulting proxied CNAME for `workshop` points to `<tunnel-uuid>.cfargotunnel.com`. The dashboard normally creates it when saving the route. Resolve any existing record conflict in the zone before replacing it. Publish only this HTTP origin.
4. Enable WebSockets for the zone. If an existing cache rule matches this hostname, give the workshop hostname a cache bypass so authentication and tunnel requests stay dynamic.
5. In a private browser, verify that an unapproved identity cannot reach Guacamole. With an approved identity and a disposable team login, verify the HTTPS login page and a working browser terminal. Then destroy the disposable event.

For token rotation on Peter, follow the dashboard instructions for the installed connector. To take the hostname offline from Peter, run `sudo systemctl stop cloudflared.service`. Start it again with `sudo systemctl start cloudflared.service`. If a replacement host uses the repository unit, replace its token file using the same hidden prompt and restart `workshop-tunnel.service`.

[Cloudflare Access and origin validation](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/) · [Cloudflare Tunnel setup](https://developers.cloudflare.com/tunnel/get-started/) · [Tunnel token-file reference](https://developers.cloudflare.com/tunnel/reference/run-parameters/#token-file)

# Cloudflare administrator handoff

The portal is on Peter at `http://127.0.0.1:8080/`. The connector package and the disabled `workshop-tunnel.service` are installed. Configure Access before publishing the hostname.

1. In Cloudflare Zero Trust, create a **Self-hosted** Access application for the full hostname `workshop.computerhardwareclub.org`, with the path blank so the policy covers the entire origin. Add an **Allow** policy for the approved workshop participants and officers using their exact emails or a club-specific identity provider group. Select the intended login method, such as the configured OSU identity provider or One-time PIN with an exact email roster. Leave all other identities subject to the default deny. Save the application and note its Application Audience (AUD) tag.
2. Create a **remotely managed Cloudflared tunnel** named `peter-workshop`. Obtain its connector token using the dashboard. On Peter, enter it into the prompt below. The token is read without terminal echo and stored root-only. The systemd unit loads it from the file at runtime.

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

For token rotation, replace the file using the same hidden prompt, then run `sudo systemctl restart workshop-tunnel.service`. To take the hostname offline from Peter, run `sudo systemctl disable --now workshop-tunnel.service`.

[Cloudflare Access and origin validation](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/) · [Cloudflare Tunnel setup](https://developers.cloudflare.com/tunnel/get-started/) · [Tunnel token-file reference](https://developers.cloudflare.com/tunnel/reference/run-parameters/#token-file)

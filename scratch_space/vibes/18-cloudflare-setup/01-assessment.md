# Assessment - current state of `pmn-14g4` (2026-06-25)

Read-only probe of the box and the domain before any change. No system modifications were made.

## Box

- Host: `pmn-14g4`, Ubuntu 26.04 LTS.
- Reached over Tailscale (`100.126.229.25`); Tailscale SSH is the access path.
- `sudo` requires a TTY -> privileged commands must be run by the user in-session.

## Component inventory

| Component | State | Evidence / notes |
| --- | --- | --- |
| Domain + Cloudflare account | **Done (prior)** | `pitrified.qzz.io` NS = `devin/kate.ns.cloudflare.com`; resolves to `188.114.97.7 / 188.114.96.7` (Cloudflare proxy). |
| Root DNS record | **Live** | Root resolves through Cloudflare's proxy - almost certainly a CNAME to the **old** box's tunnel. Repointing this is intended (box replacement). |
| cloudflared | **Not installed** | No binary, no `/etc/cloudflared`, no `~/.cloudflared`, no `cloudflared.service`. github.com reachable, so the release binary downloads fine. |
| nginx | **Not installed** | Nothing on :8090. Landing page assets ready in repo (`sites/landing/index.html` 2.2K, `style.css` 4.7K). |
| Tailscale | **Up** | Working; this is the remote-access path. Keep as-is. |
| openssh-server | **Not installed** | Nothing on :22. Decision: drop the tunnel SSH route, keep Tailscale SSH. |
| App on :8000 (`entries`) | **Not running** | Old config's `entries.pitrified.qzz.io` route has no backend here yet. |
| ufw | Present, status unread | `ufw` binary exists; `ufw status` needs sudo (TTY), not captured. |
| Repo configs | **Ready** | `configs/nginx/hub`, `configs/sysctl/99-hardening.conf`, `configs/cloudflared/config.yml` tracked and ready to symlink. |

## Guide phases vs reality

Mapping [`docs/01_box_setup.md`](../../docs/01_box_setup.md) to this box:

- **Phase 1 - hardening**: partial. unattended-upgrades / ufw / sysctl / fail2ban still apply.
  The `sshd_config` hardening is moot (no openssh; Tailscale SSH instead). Scope TBD.
- **Phase 2 - domain + Cloudflare**: **already complete** from the prior box. Reused, no work.
- **Phase 3 - nginx landing page**: to do. Install nginx, symlink `/var/www/hub` and the site config, serve on :8090.
- **Phase 4 - cloudflared tunnel**: to do, and the core of this effort.
  On `g7`: `tunnel login`, `tunnel create` (new UUID + creds), `route dns --overwrite-dns`.
  On the box: install binary, `scp` the `<UUID>.json` into `/etc/cloudflared/`, update
  `config.yml` (new UUID on both lines), symlink it, install the service.
- **Phase 5 - Zero Trust**: to do. Google-auth Access app over the subdomains + root.
- **Phase 6 - SSH over tunnel**: **dropped** (Tailscale SSH stays; openssh not installed).
- **Phase 7 - Telegram webhook**: only if a bot is deployed here. Deferred.

## Wrinkles to handle during execution

1. **Fresh tunnel = new UUID.** `config.yml` still has the old `68aa8138...` on `tunnel:` and
   `credentials-file:`. Both lines must be rewritten after `tunnel create`. The creds JSON is a
   secret - it goes to `/etc/cloudflared/<UUID>.json`, root-owned `chmod 600`, never committed.
2. **Root DNS repoint.** `route dns ... pitrified.qzz.io` repoints the old box's root CNAME,
   which now points at a dead tunnel (old box already gone). No cutover risk - the domain is
   already down - so the repoint just restores service. Still bring nginx up before the repoint
   so the root serves the landing page the moment traffic arrives.
   Catch: `cloudflared tunnel route dns` refuses a hostname that already has a record (errors
   `record already exists`), and the stale CNAME to `68aa8138....cfargotunnel.com` is exactly
   that. Run it as `cloudflared tunnel route dns --overwrite-dns <tunnel> pitrified.qzz.io`
   (or delete the stale record in the dashboard first). Same for every subdomain that carries a
   leftover record.
3. **Management runs on `g7`, not the box.** `tunnel login` / `create` / `route dns` run on the
   laptop `g7`, where `cert.pem` already lives in `~/.cloudflared/` and a browser is available.
   Only the resulting `<UUID>.json` is `scp`'d to this box over Tailscale. `cert.pem` never
   touches `pmn-14g4`.
4. **Drop the `ssh.*` ingress rule** from `config.yml` as part of the Phase 4 edit.
5. **HSTS.** HSTS is a zone-level Cloudflare edge setting, so the prior setup may already have it
   enabled - check the dashboard first. If it is on, disable it before the repoint: while HTTPS is
   down mid-transition, an active HSTS policy makes browsers hard-fail instead of falling back.
   Re-enable it only after Phase 4, once the root loads over HTTPS end-to-end
   (guide Phase 2 step 4 / Phase 4 step 6). If it was never enabled, just enable it last as before.
   (If it was ever enabled with `preload`, the domain is on the browser preload list and HTTP stays
   refused regardless of the toggle - keep the transition HTTPS-only rather than relying on fallback.)
6. **`config.yml` is symlinked, not copied.** The guide's Phase 4 step 5 does
   `cp ~/.cloudflared/config.yml /etc/cloudflared/`. This box tracks it instead:
   `scripts/setup-symlinks.sh` links `/etc/cloudflared/config.yml` -> `configs/cloudflared/config.yml`
   in the repo. Edit the repo file, run the symlink script, do **not** `cp`. Only `<UUID>.json` is a
   real file under `/etc/cloudflared/`; `cert.pem` is not copied at all (management runs on `g7`).
7. **Clean up stale DNS for dropped hostnames.** The old box likely left proxied CNAMEs for
   `ssh.pitrified.qzz.io` and `entries.pitrified.qzz.io`. We are not re-routing those (ssh dropped;
   `entries` backend pending). Delete the records we won't serve in the Cloudflare dashboard so they
   don't dangle at a dead tunnel.
8. **Bot Fight Mode / WAF vs Telegram webhook.** Phase 2 (done previously) enables Bot Fight Mode and
   the managed WAF ruleset; both can challenge or block Telegram's servers when a webhook is
   registered. If a bot is deployed here (Phase 7), add the Access bypass for the exact webhook path
   (guide Phase 7) and confirm Bot Fight Mode does not intercept it. Deferred with Phase 7.

## Suggested execution order

Check HSTS state (disable it if already on) -> Phase 3 (nginx + landing) ->
Phase 4 (cloudflared + fresh tunnel via `g7` + DNS repoint) -> verify root over HTTPS ->
Phase 5 (Zero Trust) -> re-enable HSTS -> optional Phase 1 hardening.
Phase 6 dropped; Phase 7 deferred.

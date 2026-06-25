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
  Install binary, `tunnel login` (browser), `tunnel create` (new UUID + creds),
  update `config.yml` (new UUID on both lines), `route dns`, install service.
- **Phase 5 - Zero Trust**: to do. Google-auth Access app over the subdomains + root.
- **Phase 6 - SSH over tunnel**: **dropped** (Tailscale SSH stays; openssh not installed).
- **Phase 7 - Telegram webhook**: only if a bot is deployed here. Deferred.

## Wrinkles to handle during execution

1. **Fresh tunnel = new UUID.** `config.yml` still has the old `68aa8138...` on `tunnel:` and
   `credentials-file:`. Both lines must be rewritten after `tunnel create`. The creds JSON is a
   secret - it goes to `/etc/cloudflared/<UUID>.json`, root-owned `chmod 600`, never committed.
2. **Root DNS repoint.** `route dns ... pitrified.qzz.io` overwrites the old box's root CNAME.
   Intended (replacement), but it cuts the old box over the moment it runs - sequence nginx first
   so the landing page is live when traffic arrives.
3. **`tunnel login` needs a browser.** On a headless box, copy the printed URL to a browser on
   another machine and complete auth there; the resulting `cert.pem` lands in `~/.cloudflared/`.
4. **Drop the `ssh.*` ingress rule** from `config.yml` as part of the Phase 4 edit.
5. **HSTS last.** Enable HSTS at the Cloudflare edge only after the root domain loads over HTTPS
   end-to-end (guide Phase 2 step 4 / Phase 4 step 6).

## Suggested execution order

Phase 3 (nginx + landing) -> Phase 4 (cloudflared + fresh tunnel + DNS repoint) -> verify root over HTTPS
-> Phase 5 (Zero Trust) -> enable HSTS -> optional Phase 1 hardening. Phase 6 dropped; Phase 7 deferred.

---
status: done
---

# Phase 3 - nginx landing page

## Overview

Serve `sites/landing/` on loopback `:8090` so the root domain has content the moment
Phase 4 repoints DNS. Guide Phase 3 with two audit-driven changes already in the repo:
the hub config binds `127.0.0.1:8090` (never the LAN) and carries security headers +
a `default-src 'self'` CSP (fonts are self-hosted, no external requests).
Context: [`00-start.md`](00-start.md); depends on [`03-phase1-hardening.md`](03-phase1-hardening.md)
(ufw as backstop, deploy script already exercised).

## Goals

1. nginx installed, hub site enabled, landing page served on `127.0.0.1:8090`.
2. Page unreachable from LAN/tailnet directly (loopback bind + ufw).

## Plan

1. Install (user): `! sudo apt install nginx -y`.
2. Deploy configs (user): `! sudo bash scripts/deploy-configs.sh`
   - copies `configs/nginx/hub` to `/etc/nginx/sites-available/hub`,
     links `/var/www/hub -> <repo>/sites/landing`, runs `nginx -t`.
3. Enable the site (user):
   - `! sudo ln -sf /etc/nginx/sites-available/hub /etc/nginx/sites-enabled/hub`
   - Leave the distro `default` site (port 80) as is for now, or remove it:
     `! sudo rm -f /etc/nginx/sites-enabled/default` - decide in-session; it binds :80
     which is deny-by-default at ufw anyway.
   - `! sudo nginx -t && sudo systemctl restart nginx`
   - `! sudo systemctl enable nginx`
4. Verify (Claude, unprivileged):
   - `curl -s http://127.0.0.1:8090` returns the landing page HTML, fonts load
     (`curl -sI http://127.0.0.1:8090/fonts/ibm-plex-mono-400.woff2` is 200).
   - Headers present: `curl -sI http://127.0.0.1:8090` shows `X-Content-Type-Options`,
     `Content-Security-Policy`, no `Server:` version.
   - `ss -tlnp | grep 8090` shows the listener on `127.0.0.1:8090`, not `0.0.0.0`.
   - Negative test from `g7`: `curl -m 3 http://<tailscale-ip>:8090` fails (user runs on g7).

## Out of scope

- Any tunnel/DNS work - Phase 4.
- Editing the landing page content (`app1`/`app2` placeholder cards stay until real
  services exist; per-subdomain ingress decisions are a Phase 4 open question).

## Done when

- `curl http://127.0.0.1:8090` returns the landing page with the security headers.
- Listener is loopback-only and the tailnet-side negative test fails.
- nginx is enabled at boot.
- Log entry appended to [`tracking.md`](tracking.md).

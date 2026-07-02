---
status: planned
---

# Phase 4 - cloudflared, fresh tunnel, DNS repoint

## Overview

The core of the migration: create a fresh tunnel from `g7`, install cloudflared on the
box from Cloudflare's apt repo, and repoint `pitrified.qzz.io` at the new tunnel.
Management (`login`/`create`/`route dns`/`delete`) runs on `g7` where `cert.pem` lives;
only the per-tunnel `<UUID>.json` ever touches the box.
Context: [`00-start.md`](00-start.md), pitfalls in [`01-assessment.md`](01-assessment.md);
depends on [`04-phase3-nginx.md`](04-phase3-nginx.md) (landing page must be up before
the repoint so the root serves content the moment traffic arrives).

## Goals

1. Fresh tunnel created; creds JSON on the box at `/etc/cloudflared/<UUID>.json`, root:600.
2. cloudflared installed via apt (auto-updated) and running as a service with the tracked config.
3. Root DNS repointed to the new tunnel; `https://pitrified.qzz.io` serves the landing page.
4. Old tunnel deleted (creds revoked), stale DNS records removed, backups rotated.

## Plan

### Pre-flight

1. **HSTS check** (user, Cloudflare dashboard): SSL/TLS -> Edge Certificates -> HSTS.
   If enabled, disable it before the repoint; re-enable in Phase 5. If it was ever
   enabled with `preload`, keep the transition HTTPS-only (browsers will refuse HTTP regardless).

### On `g7` (user)

2. `cloudflared tunnel login` if `~/.cloudflared/cert.pem` is missing or stale.
3. `cloudflared tunnel create pmn-14g4` - note the new UUID; creds JSON lands in `~/.cloudflared/`.
4. Copy creds to the box over Tailscale: `scp ~/.cloudflared/<UUID>.json pmn-14g4:/tmp/`.
5. Back up the new `<UUID>.json` to the password manager.

### On the box

6. Install cloudflared from the apt repo (user; commands in guide Phase 4.1 - keyring,
   sources list, `apt install cloudflared`).
7. Secure the creds (user):
   - `! sudo mkdir -p /etc/cloudflared`
   - `! sudo mv /tmp/<UUID>.json /etc/cloudflared/`
   - `! sudo chown root:root /etc/cloudflared/<UUID>.json && sudo chmod 600 /etc/cloudflared/<UUID>.json`
8. **Edit the tracked config first** (Claude): in `configs/cloudflared/config.yml`
   set the new UUID on both the `tunnel:` and `credentials-file:` lines.
   Ingress stays root-only (`pitrified.qzz.io -> http://localhost:8090` + 404 catch-all);
   the `ssh.*` rule is already removed, `entries.*` stays out until a backend exists
   (open question in [`00-start.md`](00-start.md)). Commit the edit.
9. Deploy (user): `! sudo bash scripts/deploy-configs.sh` - diff shows the UUID change;
   `cloudflared tunnel ingress validate` now passes.
10. Install the service (user):
    - `! sudo cloudflared service install`
    - `! sudo systemctl enable --now cloudflared`
    - Verify: `systemctl is-active cloudflared`; `journalctl -u cloudflared -n 20 --no-pager`
      shows edge connections registered (Claude can read journal if permitted, else user).

### DNS repoint (on `g7`, user)

11. `cloudflared tunnel route dns --overwrite-dns pmn-14g4 pitrified.qzz.io`
    (`--overwrite-dns` required: the stale CNAME to `68aa8138....cfargotunnel.com` exists).
12. Verify end-to-end: `https://pitrified.qzz.io` loads the landing page in a browser.

### Decommission the old tunnel (on `g7`, user)

13. `cloudflared tunnel delete 68aa8138-1812-446c-9faf-3760c42058d4` - revokes the old creds.
14. Dashboard: delete stale `ssh.pitrified.qzz.io` and `entries.pitrified.qzz.io` CNAMEs.
15. Remove the old tunnel's JSON from the password manager; wipe the old box's disk if it
    still exists.

## Out of scope

- Access policies and HSTS re-enable - Phase 5 (run it **immediately after** this phase;
  until then the root is publicly reachable with no auth, acceptable only for the static
  landing page).
- Any app backend (`entries` or other subdomains) - per-subdomain decisions deferred.

## Done when

- `https://pitrified.qzz.io` serves the landing page over HTTPS from the new tunnel.
- `cloudflared tunnel list` on `g7` shows only the new tunnel; the old UUID is gone.
- On the box: service active and enabled; `/etc/cloudflared/<UUID>.json` root:600;
  `/etc/cloudflared/config.yml` is a root-owned copy matching the repo.
- Stale `ssh.*`/`entries.*` DNS records deleted; password-manager backup rotated.
- Log entry appended to [`tracking.md`](tracking.md), including the new tunnel name/UUID.

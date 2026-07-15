# Guide deltas - `docs/01_box_setup.md`

The guide stays **generic** for now. This file records every point where this box's
setup diverges from it, so the guide can be updated later from a checklist rather than
re-derived. Two kinds of entry:

- **box-specific** - true only for `pmn-14g4` / this migration; probably should *not* go
  into the generic guide, or only as an aside.
- **guide-gap** - a general improvement the guide should absorb once confirmed.

Source decisions: [`00-start.md`](00-start.md); pitfalls: [`01-assessment.md`](01-assessment.md).

## Deltas

| # | Guide location | What the guide says | This box does | Kind | Fold into guide? |
| - | -------------- | ------------------- | ------------- | ---- | ---------------- |
| 1 | Phase 4.2 (`tunnel login` / `create`) | Run on the box | Run management (`login` / `create` / `route dns`) on the trusted laptop `g7`; `cert.pem` never lands on the box; only `<UUID>.json` is `scp`'d over Tailscale | box-specific | As an optional "management from a separate trusted machine" note; keep the on-box path as default |
| 2 | Phase 4.3 (secure creds) | `mv ~/.cloudflared/*.json` from the box's own login | JSON arrives via `scp` from `g7`, then same `chmod 600` / `chown root:root` | box-specific | Aside only |
| 3 | Phase 4.5 (route DNS) | `cloudflared tunnel route dns <t> <host>` | Needs `--overwrite-dns` (or dashboard pre-delete) because prior records exist | guide-gap | **Done 2026-07-15** - `--overwrite-dns` caveat added to Phase 4.5 |
| 4 | Phase 4.5 (copy config) | `cp ~/.cloudflared/config.yml /etc/cloudflared/config.yml` | `config.yml` is tracked and deployed via `scripts/deploy-configs.sh` (root-owned copy with diff) | guide-gap | **Done 2026-07-02** - guide Phase 4.5 and the tracking section now both use the deploy script |
| 5 | Phase 4.5 (copy cert) | `cp ~/.cloudflared/cert.pem /etc/cloudflared/cert.pem` | Skipped entirely - `tunnel run` never reads `cert.pem` | guide-gap | **Done 2026-07-02** - copy step removed from the guide; management-only note added |
| 6 | Phase 1.3 / 1.4 (sshd + ufw ssh) | Harden `sshd_config`, `ufw allow ssh` | No openssh; Tailscale SSH instead. sshd steps moot; no ufw ssh rule | box-specific | Aside: "if you use Tailscale SSH, skip the sshd/ufw-ssh steps" |
| 7 | Phase 6 (SSH over tunnel) | Whole phase | Dropped (Tailscale SSH) | box-specific | Keep phase; note it's optional/alternative to Tailscale |
| 8 | Phase 2.4 (HSTS "enable last") | Enable after HTTPS confirmed | On a **re-used zone** HSTS may already be on; disable before repoint, re-enable after. `preload` makes HTTP refusal sticky | guide-gap | **Done 2026-07-15** - re-use/migration note + suggested settings added to Phase 2.4 |
| 9 | Phase 2.4 (Bot Fight Mode + WAF) | Enable both | Can block the Telegram webhook (Phase 7); needs Access bypass + BFM check | guide-gap | **Done 2026-07-15** - webhook caveat added under the BFM/WAF bullet |
| 10 | Whole guide | Runs commands directly | `sudo` needs a TTY here; privileged steps handed over as `! <command>` | box-specific | No |
| 11 | Phase 3 (`/var/www/hub` symlink into the repo) | Symlink and serve | Ubuntu 26.04 creates homes `750`, so `www-data` cannot traverse `/home/<user>` and nginx 404s with `stat() ... Permission denied`; fixed with a scoped ACL: `setfacl -m u:www-data:--x /home/<user>` (undo: `setfacl -x u:www-data /home/<user>`) | guide-gap | **Done 2026-07-15** - home-perms ACL block added to Phase 3.2 |
| 12 | Phase 4.1 (apt repo, `$(lsb_release -cs)`) | Use the box's codename | Ubuntu 26.04 `resolute` is not published on pkg.cloudflare.com (Release 404); fall back to `noble` - the package is a static binary, dist name is nominal | guide-gap | **Done 2026-07-15** - codename-404 fallback note added to Phase 4.1 |

## Guide edits already applied (2026-07-02, from the security audit)

The security assessment ([`../19-security-audit/00-assessment.md`](../19-security-audit/00-assessment.md))
drove a batch of direct guide + repo edits, outside this table's fold-later flow:

- `configs/nginx/hub` and guide Phase 3: `listen 127.0.0.1:8090` (loopback only), plus the rule
  that every tunnelled backend binds `127.0.0.1`, never `0.0.0.0`.
- Guide Phase 4.1: install `cloudflared` from Cloudflare's apt repo (auto-updated, signed),
  not the hand-downloaded binary.
- `scripts/setup-symlinks.sh` replaced by `scripts/deploy-configs.sh`: `/etc` configs are now
  root-owned copies with a diff gate, not symlinks into the user checkout; guide tracking
  section rewritten accordingly (closes deltas 4 and 5).
- Guide Phase 7: webhook registered with `secret_token`; bot token read from file, not pasted.
- New guide section "Decommissioning a Box or Tunnel": `tunnel delete` revokes the old creds;
  stale DNS + backups cleanup; disk wipe.
- Guide Phase 1: `unattended-upgrades` verification commands; obsolete `Protocol 2` dropped.
- Guide Phase 5: standing rule that no ingress hostname exists without Access coverage.
- `configs/cloudflared/config.yml`: `ssh.*` ingress removed (delta already decided; UUID rewrite
  still pending Phase 4).

## When updating the guide

All guide-gap rows are folded in (3, 8, 9, 11, 12 done 2026-07-15; 4, 5 done 2026-07-02).
Leave **box-specific** rows as optional notes or omit. Re-check each row against the box's
actual execution before editing the guide; mark a row done here when its guide edit lands.

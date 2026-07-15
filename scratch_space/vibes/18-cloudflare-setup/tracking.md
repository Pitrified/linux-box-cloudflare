# Cloudflare setup tracking

Standing up the Cloudflare-tunnel stack on the fresh box `pmn-14g4` (Ubuntu 26.04),
**replacing the old box** as the live target for `pitrified.qzz.io`.
Recap and decisions in [`00-start.md`](00-start.md); current-state probe in [`01-assessment.md`](01-assessment.md);
guide divergences to fold back later in [`02-guide-deltas.md`](02-guide-deltas.md).

## Key decisions

- Same domain + Cloudflare account `pitrified.qzz.io` (already on Cloudflare; Phase 2 reused).
- **Fresh tunnel** via `cloudflared tunnel create` on `g7` -> new UUID + creds; `scp` `<UUID>.json` to the box, rewrite both lines in `configs/cloudflared/config.yml` (old `68aa8138...` is stale).
- **This box replaces the old one** (old box already gone); `route dns --overwrite-dns` repoints the domain onto the new tunnel over the stale records.
- **Drop openssh / SSH-over-tunnel (Phase 6)**; keep Tailscale SSH. Remove the `ssh.*` ingress rule; delete the stale `ssh.*` DNS record.
- Privileged steps handed to the user as `! <command>` (`sudo` needs a TTY here).
- **HSTS:** check whether it is already enabled at the edge; if so disable before the repoint and re-enable after Phase 4 (once HTTPS works end-to-end).
- **Credentials (box = low-secret):** account `cert.pem` **never lands on the box** - all management (`login`/`create`/`route dns`) runs on the trusted laptop `g7`, and only the resulting `<UUID>.json` is `scp`'d over. That JSON lives at `/etc/cloudflared/`, `root:600`, never committed; revocable. `config.yml` is symlinked from the repo (not copied); skip the guide's `cert.pem` copy. Details in [`00-start.md`](00-start.md).

- **Security audit fold-in (2026-07-02,** [`../19-security-audit/00-assessment.md`](../19-security-audit/00-assessment.md)**):**
  Phase 1 (unattended-upgrades + ufw, skip fail2ban) runs **before** the Phase 4 DNS repoint, not after.
  Phase 5 (Access) runs **immediately** after Phase 4 - no ingress hostname without Access coverage.
  Phase 4 additions: edit `config.yml` (new UUID; `ssh.*` already removed) **before** running
  `deploy-configs.sh`; install cloudflared from the apt repo; after cutover, `cloudflared tunnel delete`
  the old tunnel `68aa8138...` from `g7` (revokes its creds), remove its password-manager backup,
  wipe the old disk if it still exists. All backends bind `127.0.0.1`.
  `/etc` configs are now deployed as root-owned copies via `scripts/deploy-configs.sh`
  (replaces `setup-symlinks.sh`); treat `git pull` + redeploy as a reviewed config change.

## Phases

| #  | Phase                              | Plan                  | Status   |
| -- | ---------------------------------- | --------------------- | -------- |
| 1  | Local hardening (partial)          | [`03-phase1-hardening.md`](03-phase1-hardening.md) | done     |
| 2  | Domain + Cloudflare                | n/a - done previously | done     |
| 3  | nginx landing page                 | [`04-phase3-nginx.md`](04-phase3-nginx.md) | done     |
| 4  | cloudflared + fresh tunnel + DNS   | [`05-phase4-tunnel.md`](05-phase4-tunnel.md) | in progress |
| 5  | Zero Trust (Google auth) + HSTS    | [`06-phase5-zero-trust.md`](06-phase5-zero-trust.md) | planned  |
| 6  | SSH over tunnel                    | n/a                   | discarded |
| 7  | Telegram webhook                   | [`07-phase7-telegram.md`](07-phase7-telegram.md) | draft    |

Status values: draft / planned / in progress / done / superseded / discarded.
Phase 6 discarded: box uses Tailscale SSH; openssh not installed (see [`00-start.md`](00-start.md)).
Per-phase sub-plans (`NN_feat_name.md`) are written just-in-time before each phase runs.

## Log

Append-only. Newest at the bottom.

- 2026-06-25 : probed box + domain read-only (no changes); wrote up findings in [`01-assessment.md`](01-assessment.md).
- 2026-06-25 : bootstrapped this plan folder (`00-start.md`, `01-assessment.md`, `tracking.md`); decisions locked (fresh tunnel, same domain, replace old box, drop openssh). Execution not started - assess-first per user.
- 2026-06-25 : added credentials-handling decision (low-secret box): account `cert.pem` never persisted on box (user-provided from password manager, management-only); per-tunnel JSON on box at `/etc/cloudflared` root:600; skip the cert.pem copy in Phase 4.
- 2026-07-01 : reconciled decisions after the old box was retired. cert.pem management fixed to run on the trusted laptop `g7` (never on box; only `<UUID>.json` `scp`'d over). DNS repoint needs `route dns --overwrite-dns` over the stale records. HSTS may be pre-enabled at the edge - disable before the repoint, re-enable after Phase 4. Recorded pitfalls in [`01-assessment.md`](01-assessment.md): `config.yml` is symlinked not copied; delete stale `ssh.*`/`entries.*` DNS records; Bot Fight Mode / WAF can block the Telegram webhook (Phase 7).
- 2026-07-01 : kept `docs/01_box_setup.md` generic; captured every box-vs-guide divergence in [`02-guide-deltas.md`](02-guide-deltas.md) so the guide can be updated later from a checklist. Guide-gap rows to fold back: `--overwrite-dns`, symlink-not-copy `config.yml`, `cert.pem` is management-only, HSTS re-use note, Bot Fight Mode/WAF vs webhook.
- 2026-07-02 : security audit of the repo ([`../19-security-audit/00-assessment.md`](../19-security-audit/00-assessment.md)); quick wins applied: nginx binds loopback, `ssh.*` ingress removed from `config.yml`, `setup-symlinks.sh` replaced by `deploy-configs.sh` (root-owned copies + diff gate), guide updated (apt-repo cloudflared install, webhook `secret_token`, decommission section, Access-coverage rule). Plan updated: hardening before repoint (fail2ban skipped), old tunnel deletion added to Phase 4, Phase 5 immediately after Phase 4. Deltas 4 and 5 closed.
- 2026-07-02 : wrote the Phase 1 sub-plan ([`03-phase1-hardening.md`](03-phase1-hardening.md)): unattended-upgrades + ufw (zero inbound rules, Tailscale lockout guard) + sysctl via `deploy-configs.sh`, all before the Phase 4 repoint; fail2ban and sshd hardening explicitly out of scope. Status planned, execution not started.
- 2026-07-02 : planned all remaining phases. Phase 3 ([`04-phase3-nginx.md`](04-phase3-nginx.md)): loopback-only nginx + negative test from g7. Phase 4 ([`05-phase4-tunnel.md`](05-phase4-tunnel.md)): apt-repo install, management on g7, config edit before deploy, `--overwrite-dns` repoint, old-tunnel delete + backup rotation. Phase 5 ([`06-phase5-zero-trust.md`](06-phase5-zero-trust.md)): Access over wildcard + apex, then HSTS re-enable, immediately after Phase 4. Phase 7 ([`07-phase7-telegram.md`](07-phase7-telegram.md)) stays `draft` until a bot backend is decided. Execution order: 1 -> 3 -> 4 -> 5; 7 deferred.
- 2026-07-15 : re-verified the assessment read-only before execution (new session on the box). Box unchanged (no cloudflared/nginx/openssh, ufw inactive, unattended-upgrades already active). Domain drift, both favourable: the whole zone already sits behind a live Cloudflare Access login (apex + `ssh.*` + `entries.*` all 302 to `pitrified.cloudflareaccess.com`), and no HSTS header is served (likely off - confirm in dashboard). Details appended to [`01-assessment.md`](01-assessment.md). `g7` offline on the tailnet at probe time - needed up for Phase 4.
- 2026-07-15 : Phase 1 executed (user ran sudo commands from an outside terminal, logs teed to `~/cf-setup-logs/`; the in-session `! sudo` route does not work - no TTY password prompt). Findings: box was already Pro-attached (esm-apps/infra + livepatch) so the attach step was a no-op; unattended-upgrades already enabled (`Periodic "1"`, service + timer active); the tailscale 1.98.8→1.98.9 upgrade dropped the SSH session mid-`apt upgrade` but apt completed (dpkg clean, 0 upgradable after). ufw enabled: default deny incoming / allow outgoing, zero inbound rules, fresh Tailscale SSH session verified. sysctl deployed via `deploy-configs.sh` (all three configs landed as new root-owned files; cloudflared/nginx validation skipped, not installed) and applied. AppArmor: enabled, 246 profiles, 20 confined processes (`aa-status --summarized` no longer exists; use `--count`). USB-storage disable skipped by decision (box at home, keep recovery path). Remaining: reboot (gnome-shell only, no kernel) + post-reboot verify of ufw and Tailscale SSH, then mark phase done.
- 2026-07-15 : reboot was inhibited by an orphaned, stopped (`T`) `apt upgrade -y` on a dead pts (session lost in the tailscale restart) plus the local GNOME session on tty2; cleared the apt zombie with `kill -CONT`/`-TERM`, rebooted via `systemctl reboot -i`. Post-reboot verified: ufw active (deny incoming, no rules), Tailscale SSH reconnects (same IP), unattended-upgrades active, reboot flag gone. **Phase 1 done.** Next: Phase 3 ([`04-phase3-nginx.md`](04-phase3-nginx.md)).
- 2026-07-15 : Phase 3 executed. nginx installed, hub site enabled, distro `default` site removed (decision: nothing should serve :80). Hit a new-OS snag: Ubuntu 26.04 homes are `750`, so `www-data` could not traverse `/home/pmn` to the symlinked `/var/www/hub` and nginx 404'd (`stat() Permission denied`); fixed with a scoped ACL `setfacl -m u:www-data:--x /home/pmn` (recorded as guide delta 11). Verified: landing page + fonts 200 on `127.0.0.1:8090`, security headers + CSP present, no `Server` version, loopback-only listener, negative test from the tailnet refused, nginx enabled at boot. **Phase 3 done.** Next: Phase 4 ([`05-phase4-tunnel.md`](05-phase4-tunnel.md)) - needs `g7` online; pre-flight is the HSTS dashboard check.

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
| 3 | Phase 4.5 (route DNS) | `cloudflared tunnel route dns <t> <host>` | Needs `--overwrite-dns` (or dashboard pre-delete) because prior records exist | guide-gap | Yes - add `--overwrite-dns` caveat for re-use / migration cases |
| 4 | Phase 4.5 (copy config) | `cp ~/.cloudflared/config.yml /etc/cloudflared/config.yml` | `config.yml` is a tracked **symlink** via `scripts/setup-symlinks.sh`; never `cp` | guide-gap | Yes - the guide's own "Config File Tracking" section already says symlink; Phase 4.5 contradicts it. Reconcile the two. |
| 5 | Phase 4.5 (copy cert) | `cp ~/.cloudflared/cert.pem /etc/cloudflared/cert.pem` | Skipped entirely - `tunnel run` never reads `cert.pem` | guide-gap | Yes - clarify `cert.pem` is management-only and not needed by the service |
| 6 | Phase 1.3 / 1.4 (sshd + ufw ssh) | Harden `sshd_config`, `ufw allow ssh` | No openssh; Tailscale SSH instead. sshd steps moot; no ufw ssh rule | box-specific | Aside: "if you use Tailscale SSH, skip the sshd/ufw-ssh steps" |
| 7 | Phase 6 (SSH over tunnel) | Whole phase | Dropped (Tailscale SSH) | box-specific | Keep phase; note it's optional/alternative to Tailscale |
| 8 | Phase 2.4 (HSTS "enable last") | Enable after HTTPS confirmed | On a **re-used zone** HSTS may already be on; disable before repoint, re-enable after. `preload` makes HTTP refusal sticky | guide-gap | Yes - add a re-use/migration note to the HSTS step |
| 9 | Phase 2.4 (Bot Fight Mode + WAF) | Enable both | Can block the Telegram webhook (Phase 7); needs Access bypass + BFM check | guide-gap | Yes - cross-reference Phase 7 from the BFM/WAF step |
| 10 | Whole guide | Runs commands directly | `sudo` needs a TTY here; privileged steps handed over as `! <command>` | box-specific | No |

## When updating the guide

Fold the **guide-gap** rows (3, 4, 5, 8, 9) first - they are general and confirmed by this run.
Leave **box-specific** rows as optional notes or omit. Re-check each row against the box's
actual execution before editing the guide; mark a row done here when its guide edit lands.

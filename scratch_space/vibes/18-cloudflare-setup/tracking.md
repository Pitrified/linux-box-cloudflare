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

## Phases

| #  | Phase                              | Plan                  | Status   |
| -- | ---------------------------------- | --------------------- | -------- |
| 1  | Local hardening (partial)          | _sub-plan TBD_        | planned  |
| 2  | Domain + Cloudflare                | n/a - done previously | done     |
| 3  | nginx landing page                 | _sub-plan TBD_        | planned  |
| 4  | cloudflared + fresh tunnel + DNS   | _sub-plan TBD_        | planned  |
| 5  | Zero Trust (Google auth) + HSTS    | _sub-plan TBD_        | planned  |
| 6  | SSH over tunnel                    | n/a                   | discarded |
| 7  | Telegram webhook                   | _sub-plan TBD_        | planned  |

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

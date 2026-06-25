# Cloudflare setup tracking

Standing up the Cloudflare-tunnel stack on the fresh box `pmn-14g4` (Ubuntu 26.04),
**replacing the old box** as the live target for `pitrified.qzz.io`.
Recap and decisions in [`00-start.md`](00-start.md); current-state probe in [`01-assessment.md`](01-assessment.md).

## Key decisions

- Same domain + Cloudflare account `pitrified.qzz.io` (already on Cloudflare; Phase 2 reused).
- **Fresh tunnel** via `cloudflared tunnel create` -> new UUID + creds; rewrite both lines in `configs/cloudflared/config.yml` (old `68aa8138...` is stale).
- **This box replaces the old one**; routing DNS to the new tunnel repoints the domain intentionally.
- **Drop openssh / SSH-over-tunnel (Phase 6)**; keep Tailscale SSH. Remove the `ssh.*` ingress rule.
- Privileged steps handed to the user as `! <command>` (`sudo` needs a TTY here).
- Enable HSTS only after HTTPS works end-to-end.
- **Credentials (box = low-secret):** account `cert.pem` is **never persisted on box** - user provides it from their password manager at setup, used for management only, then removed (or management runs from a trusted machine). Per-tunnel `<UUID>.json` lives at `/etc/cloudflared/`, `root:600`, never committed; revocable. Skip the guide's `cert.pem` copy into `/etc/cloudflared/`. Details in [`00-start.md`](00-start.md).

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

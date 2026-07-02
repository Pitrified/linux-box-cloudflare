---
status: draft
---

# Phase 7 - Telegram bot webhook

## Overview

Deferred until a bot actually runs on this box (open question in
[`00-start.md`](00-start.md): which services beyond the landing page live here).
Draft only - firm up when the bot backend and its port are decided.
Depends on [`06-phase5-zero-trust.md`](06-phase5-zero-trust.md) (Access must exist
before punching a bypass through it).

## Goals

1. Telegram's servers can deliver webhook updates to the bot; nothing else can invoke it
   without either passing Access or knowing the webhook secret.

## Plan (to firm up)

1. Bot service running on `127.0.0.1:<port>` (loopback only, like every backend).
2. Ingress: add `bot.pitrified.qzz.io -> http://localhost:<port>` to
   `configs/cloudflared/config.yml`, commit, `! sudo bash scripts/deploy-configs.sh`,
   restart cloudflared. **Access first** (next step) before routing DNS - standing rule.
3. Access: bypass application scoped to the exact webhook path only
   (subdomain `bot`, path `webhook`), action **Bypass**, include Telegram's published
   IP ranges (`149.154.160.0/20`, `91.108.4.0/22` - re-check the official list at
   execution time).
4. DNS: `cloudflared tunnel route dns --overwrite-dns pmn-14g4 bot.pitrified.qzz.io`
   (a stale `bot.*` record may or may not exist).
5. Register the webhook **with `secret_token`** (guide Phase 7.2, audit M3): token and
   secret read from files, never pasted on the command line; bot rejects requests whose
   `X-Telegram-Bot-Api-Secret-Token` header does not match.
6. Verify: `getWebhookInfo` shows the URL and no last-error; a test message reaches the
   bot; a curl to the webhook path without the secret header is rejected by the bot,
   and to any other bot path is blocked by Access.
7. **Bot Fight Mode / WAF check** (pitfall 8 in [`01-assessment.md`](01-assessment.md)):
   both can challenge Telegram's servers. If `getWebhookInfo` reports failures, add a
   WAF skip rule for the exact webhook path rather than disabling BFM globally.

## Out of scope

- The bot application itself (lives in its own repo, e.g. `tg-central-hub-bot`).

## Done when

- A Telegram message triggers the bot end-to-end; `getWebhookInfo` clean.
- Bypass covers only the webhook path; secret-token rejection verified.
- Log entry appended to [`tracking.md`](tracking.md).

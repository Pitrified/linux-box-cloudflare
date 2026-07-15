---
status: done
---

# Phase 5 - Zero Trust Access + HSTS re-enable

## Overview

Put Google-auth Access in front of the domain and re-enable HSTS now that HTTPS works
end-to-end. Run this **immediately after** Phase 4 - every hour in between is an hour
any future ingress would be exposed with no auth (audit M2; standing rule now in guide
Phase 5). All dashboard work, done by the user; Claude assists with verification.
Context: [`00-start.md`](00-start.md); depends on [`05-phase4-tunnel.md`](05-phase4-tunnel.md).

## Goals

1. Access application covering `*.pitrified.qzz.io` **and** the apex, with an
   email-allowlist policy.
2. HSTS re-enabled at the edge.
3. Tunnel-health notifications configured.

## Plan

1. **Access application** (user, Zero Trust dashboard -> Access -> Applications ->
   Add -> Self-hosted):
   - Domains: `*.pitrified.qzz.io` **plus** `pitrified.qzz.io` added to the same app -
     the wildcard does not cover the apex.
   - Policy: Allow, Include -> Emails -> the authorised Gmail addresses.
   - Decision to make in-session: protect the root too (default per
     [`01-assessment.md`](01-assessment.md): yes, "subdomains + root") or leave the
     landing page public as a portal. Record the choice in the log.
2. **Verify the challenge** :
   - Private-browser visit to `https://pitrified.qzz.io` -> Google auth screen
     (if the root was included), authorised account gets through, an
     unauthorised account is denied.
   - `curl -sI https://pitrified.qzz.io` returns a 302 to the Access login, not the page.
3. **Re-enable HSTS** (user, dashboard): SSL/TLS -> Edge Certificates -> HSTS, only after
   step 2 confirms HTTPS + auth work end-to-end. Leave `preload` off unless deliberately
   chosen (it is effectively irreversible).
4. **Notifications** (user, dashboard): alert on tunnel health (down/degraded).
5. Optional: session duration for the Access app (default 24h is fine).

## Decisions taken in-session (2026-07-15)

- The prior setup's Access apps survive and cover everything: "Home Portal" (apex) +
  "Internal Apps" (`*.pitrified.qzz.io`), both with the "Allow Friends" email-allowlist
  policy. Nothing rebuilt; root protection = yes (inherited).
- **Login method: One-time PIN (email OTP), kept** - auth handled entirely by Cloudflare,
  no third-party IdP. Future option: Cloudflare Access supports adding Google as an OAuth
  identity provider (Zero Trust -> Settings -> Authentication -> Login methods); could be
  added alongside OTP later for phishing-resistance. Not done now.
- Negative-test note: for a non-allowlisted email, Access still shows "Enter your code"
  but sends no code - intentional anti-enumeration; the deny is the code never arriving.

## Out of scope

- Backend validation of `Cf-Access-Jwt-Assertion` (audit M2 defense-in-depth) - future
  `fastapi-tools` work, matters once real app backends exist.
- Device posture checks (guide Phase 5.3) - single-user setup, skip.
- The Telegram webhook bypass - Phase 7, only when a bot backend exists.

## Done when

- Unauthenticated request to the protected hostnames gets the Access challenge;
  an allowlisted account passes; a non-allowlisted account is denied.
- HSTS enabled and `curl -sI` on the root shows `strict-transport-security` once logged in
  (or on the Access login page itself).
- Tunnel-health notification exists.
- Log entry appended to [`tracking.md`](tracking.md), recording the root-protection choice.

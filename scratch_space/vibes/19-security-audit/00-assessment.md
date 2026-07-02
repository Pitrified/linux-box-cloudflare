# Security assessment - linux box setup (2026-07-02)

Deep review of the `linux-box-cloudflare` repo only: the general box stack
(`docs/01_box_setup.md`, `docs/always-on-server.md`, `configs/`, `scripts/`, `sites/`)
and the new-box plan (`scratch_space/vibes/18-cloudflare-setup/`).
No live system was probed; everything below is derived from tracked files.
Findings are sorted by priority. The earlier audit
([`02-security-audit.md`](../02-security-audit.md)) is not repeated;
its accepted findings (tunnel UUID public, port map public) still hold and are reaffirmed at the end.

## Threat model recap

- Repo is **public** (`github.com/Pitrified/linux-box-cloudflare`).
- Box sits behind CGNAT; all internet exposure is via an outbound Cloudflare Tunnel plus Zero Trust Access.
- Remote admin access is Tailscale SSH (new box: no openssh, nothing on :22).
- The one on-box secret is the per-tunnel credentials JSON at `/etc/cloudflared/<UUID>.json` (root:600, untracked).

The interesting attack surfaces are therefore:
(a) the trust chain from the public git repo into root-consumed `/etc` configs,
(b) anything that lets traffic reach backends without passing Cloudflare Access,
(c) the long-lived `cloudflared` daemon itself,
and (d) leftovers from the retired old box.

---

## P1 - High priority

### H1. Root-consumed configs are symlinks into a user-writable public-repo checkout

`scripts/setup-symlinks.sh` links `/etc/cloudflared/config.yml`, `/etc/nginx/sites-available/hub`,
`/etc/sysctl.d/99-hardening.conf`, and `/var/www/hub` to files under `~/repos/linux-box-cloudflare`,
owned by the unprivileged user.

Consequences:

- Anything that can write as the normal user (a compromised process, a malicious dependency,
  an agent session in bypass mode) can silently change kernel sysctl settings,
  the nginx config loaded by the root master process,
  and the tunnel ingress map (e.g. re-add an `ssh://` or arbitrary TCP ingress).
  That is a user-to-root-config escalation and persistence channel with no privilege boundary.
- `git pull` on this repo is effectively a privileged operation:
  whoever can push to `main` (a compromised GitHub account, a leaked token on any other machine)
  can stage config that takes effect at the next service restart or `sysctl --system` (every boot).
- The changes take effect without any review gate on the box; there is no diff step between
  "repo changed" and "root service consumes it".

This is a deliberate design (git-backed configs) and the convenience is real,
but it deserves an explicit decision and at least one mitigation:

- Cheapest: replace symlinks with a **copy-with-diff** deploy step in the script
  (`diff /etc/... repo-file` shown to the user, then `install -o root -g root -m 644`).
  Root then owns the live file; changing it requires sudo, restoring the privilege boundary.
  The repo stays the source of truth; the script becomes the deploy gate.
- Alternative if symlinks stay: enable GitHub branch protection on `main`,
  require signed commits, and treat `git pull` on the box as a privileged action
  (review the diff before pulling). Document this in `docs/01_box_setup.md`'s
  "Config File Tracking" section, which currently presents the symlink as a pure convenience.
- Either way: `sysctl.d` is the sharpest edge (applied as root at every boot with no service restart);
  consider copying at least that one.

### H2. nginx binds all interfaces, so backends are reachable without Cloudflare Access

`configs/nginx/hub` has `listen 8090;`, which binds `0.0.0.0:8090`.
Anyone on the LAN, and any peer on the tailnet, reaches the site directly,
bypassing the Cloudflare edge entirely (WAF, Bot Fight Mode, and any Zero Trust policy).

For the static landing page the impact is small, but the pattern is the problem:
the same guide wires app backends (`localhost:8000`, `:8080`, `:3000`, `:5000`) whose
whole auth story is Cloudflare Access in front. If any of those also bind `0.0.0.0`
(uvicorn's `--host 0.0.0.0` is a common copy-paste), Access is bypassed from the local network.

Fix:

- Change the tracked config to `listen 127.0.0.1:8090;` and note in the guide that
  **every tunnelled backend must bind loopback only** (`127.0.0.1`), since the tunnel
  connects from localhost anyway.
- Keep ufw default-deny as the backstop (see H3): with it enabled, a stray `0.0.0.0`
  bind is not reachable from outside, which is exactly why the two layers should both exist.

### H3. New-box hardening is sequenced last and partially undecided

`18-cloudflare-setup/01-assessment.md` puts "optional Phase 1 hardening" at the **end** of the
execution order, and `00-start.md` leaves "how much of Phase 1 to apply" as an open question,
while `docs/01_box_setup.md` Phase 1 itself says these steps "should be done before the box
is reachable from the internet". The plan contradicts the guide it follows.

The ufw state on `pmn-14g4` is also unknown ("status unread" in the assessment).

Recommended answer to the open question, and ordering:

- **Before the DNS repoint (Phase 4):** `apt update && apt upgrade`, `unattended-upgrades`
  (verify it is actually enabled: `systemctl status unattended-upgrades` and
  `apt-config dump APT::Periodic::Unattended-Upgrade`), and
  `ufw default deny incoming` + `enable`. With no openssh there is no inbound rule to add at all;
  the box can run with **zero open inbound ports** from day one
  (Tailscale traffic arrives over the `tailscale0` interface; verify a Tailscale SSH session
  survives `ufw enable` before closing the session that ran it).
- **Any time:** the sysctl file (subject to H1), Ubuntu Pro attach.
- **Skip on this box:** fail2ban. It watches auth logs of daemons facing inbound traffic;
  with no sshd and all web traffic arriving from the tunnel (source = localhost),
  it has nothing meaningful to ban. One less package and jail config to maintain.
  Note this in the plan so the open question is closed deliberately.
- The sshd_config block is already correctly declared moot.

### H4. cloudflared binary: no integrity check and, more importantly, no update path

Guide Phase 4.1 installs by `curl`ing the latest GitHub release to `/usr/local/bin`.
Two problems:

- No checksum or signature verification of the download (a one-time tampering risk, minor).
- No ongoing updates (the ongoing risk). A hand-placed binary in `/usr/local/bin` is invisible
  to `unattended-upgrades`. `cloudflared` is the single internet-facing, long-lived daemon
  on the box and has a regular CVE cadence; it will silently age.

Fix: install from Cloudflare's apt repository (`pkg.cloudflare.com`) instead,
so `unattended-upgrades` covers it, and update the guide accordingly.
If the standalone binary is kept, add a scheduled update mechanism
(`cloudflared update` via systemd timer) and verify the release checksum on install.
Do this on the new box now, before the service is installed; retrofitting is more annoying.

---

## P2 - Medium priority

### M1. Old tunnel is not explicitly revoked

The plan creates a fresh tunnel and repoints DNS, but nowhere says to **delete the old tunnel**
(`68aa8138-1812-446c-9faf-3760c42058d4`). Its credentials JSON presumably still exists on the
retired box's disk (and possibly in the password-manager backup). While DNS no longer points at it,
a live credential for a dead tunnel is exactly the kind of leftover that resurfaces:
anyone with that JSON can run the tunnel and serve traffic for any hostname still CNAMEd to it.

Fix: after the new tunnel is live, run `cloudflared tunnel delete <old-UUID>` from `g7`
(revokes the credential server-side), and wipe or destroy the old box's disk if it still exists.
Add this as an explicit step in the Phase 4 sub-plan. The planned stale-DNS cleanup
(`ssh.*`, `entries.*`) covers the DNS half; this covers the credential half.

### M2. Backends trust the tunnel blindly - no Access JWT validation, no coverage checklist

All application auth is Cloudflare Access at the edge. Two gaps behind that:

- **Coverage is by convention.** Every hostname added to `config.yml` ingress must also be
  covered by an Access application. Nothing enforces this; a new `foo.pitrified.qzz.io` ingress
  plus `route dns` is publicly reachable with **no auth** the moment it exists, and the wildcard
  Access app only helps if it was configured (Phase 5 is still `planned`).
  Sequence Phase 5 immediately after Phase 4, and add a rule to the guide:
  "no new ingress hostname without confirming Access coverage".
  Note the root-domain gap the guide already flags (the wildcard does not cover the apex).
- **No defense in depth.** If Access is misconfigured (or a Bypass rule is broader than intended),
  backends accept anything. Cloudflare forwards a `Cf-Access-Jwt-Assertion` header;
  validating it in the FastAPI apps (a small shared dependency, e.g. in `fastapi-tools`) makes
  Access enforcement fail-closed instead of fail-open. Worth doing for any backend that
  handles personal data; optional for the static landing page.

### M3. Telegram webhook: IP-range bypass is the only gate

Guide Phase 7 exempts the webhook path from Access for Telegram's IP ranges.
Reasonable, but the webhook then has no application-level authentication:
anything Cloudflare believes originates from those ranges reaches the bot unauthenticated,
and IP trust at the edge is weaker than a shared secret.

Fixes (both cheap, do when Phase 7 happens):

- Register the webhook with Telegram's `secret_token` parameter and have the bot reject
  requests whose `X-Telegram-Bot-Api-Secret-Token` header does not match.
  This is the Telegram-recommended control and turns the IP bypass into a mere rate-limiter.
- The guide's `curl ... /bot<YOUR_BOT_TOKEN>/setWebhook` puts the bot token into shell history
  and process listings. Read it from the credentials file instead
  (`"https://api.telegram.org/bot$(cat ~/cred/...)/setWebhook"` or a small script).
  Same note applies to `sudo pro attach <TOKEN>` in Phase 1.

### M4. "No secrets on this box" assumption drifts once tunnel creds land

`configs/claude/rules/local-box.md` describes the box as a "disposable sandbox: no secrets stored"
and documents that Claude runs with **bypass permissions**. The new-box plan classifies `pmn-14g4`
as "low-secret" and puts `/etc/cloudflared/<UUID>.json` on it. Those two documents describe
the same class of machine with different trust levels.

The mitigations are real: the JSON is root:600, Claude runs unprivileged, and sudo needs a TTY,
so an agent session cannot read the credential. But the rules file is what future sessions load,
and it currently tells agents the box holds nothing sensitive.
If `setup-disposable-box.sh` is (or gets) run on `pmn-14g4`, update `local-box.md` first
(or fork a `low-secret-box.md` variant) so the stated model matches reality:
"one revocable secret at /etc/cloudflared, root-only; user account compromise = rotate the tunnel".
Note that H1 interacts here: with config symlinks in place, an unprivileged agent *can* alter
root-consumed configs even without reading any secret.

### M5. Tracked `config.yml` is stale and the symlink script deploys it as-is

`configs/cloudflared/config.yml` still carries the old tunnel UUID on both lines and the
`ssh.pitrified.qzz.io -> ssh://localhost:22` ingress the plan explicitly drops.
`setup-symlinks.sh` links it into `/etc/cloudflared/` unconditionally and only validates afterwards.
Running the script on the new box before the Phase 4 edit would install a config pointing at a
dead tunnel with a dangling SSH ingress. The plan knows about the UUID; make the config edit a
**precondition** of running the symlink script in the Phase 4 sub-plan, and remove the `ssh.*`
block in the same edit.

Script-level nits while in there:

- It never creates `/etc/cloudflared/`; on a fresh box `ln -sf` into a missing directory fails.
  Add a root-owned `mkdir -p /etc/cloudflared`.
- `cloudflared tunnel ingress validate` on a fresh box also fails before the creds JSON exists;
  `set -e` then aborts after the links are already made. Order: creds first, or tolerate
  validation failure with a clear message.
- One stray `sudo mkdir` inside a script documented to run under sudo; harmless, but make it plain `mkdir`.

---

## P3 - Low priority

### L1. Public repo exposes architecture and operational detail (reaffirmed, slightly grown)

The prior audit accepted the tunnel UUID and port map being public. Since then the public
surface has grown: `scratch_space/vibes/` now documents the new box's hostname (`pmn-14g4`),
its Tailscale IP (`100.126.229.25`), the admin workflow ("sudo needs a TTY"), the management
laptop's name, and the full migration plan. None of it is directly exploitable
(Tailscale IPs are unreachable outside the tailnet), but it is a complete recon dossier.
Re-accept this consciously or start pruning operational detail from committed scratch notes.
The `.gitignore` correctly excludes the creds JSON and `repos.state.json`; a history scan
found nothing secret-shaped committed.

### L2. GitHub Actions pinned by tag, not SHA

`deploy-site-overview.yml` uses `actions/checkout@v4` etc. Mutable tags are a mild supply-chain
exposure; the workflow's permissions are already minimal (`contents: read`, `pages: write`,
`id-token: write`), which caps the blast radius to defacing the Pages site.
Pin to commit SHAs to close it; acceptable as-is for a static-site deploy.

### L3. nginx and landing-page hardening niceties

- Add `server_tokens off;` and basic headers (`X-Content-Type-Options: nosniff`,
  a minimal CSP) to the hub config; Cloudflare fronts it, but headers are free.
- The landing page loads Google Fonts from `fonts.googleapis.com`: an external dependency
  and a visitor-privacy leak on an otherwise self-contained stack. Self-host the two fonts;
  that also lets a strict CSP be `default-src 'self'`.

### L4. Guide corrections (fold into the existing `02-guide-deltas.md` flow)

- Phase 1 sshd block: `Protocol 2` is obsolete (ignored by modern OpenSSH); drop it to keep
  the block credible. The rest of the block is good.
- Phase 4.5's `cp config.yml` / `cp cert.pem` contradicts the guide's own symlink section;
  already captured as deltas 4 and 5. The `cert.pem` copy should be deleted from the guide,
  not just annotated: the service never reads it, and copying an account-scoped credential
  onto the serving box is strictly worse (the new plan gets this right).
- Phase 1 `unattended-upgrades`: add the verification command; installing the package
  does not prove the periodic job is enabled.

### L5. Password-manager backup of the tunnel JSON

Fine as designed (the credential is tunnel-scoped and revocable). Just ensure the backup is
updated or deleted when M1's old-tunnel deletion happens, so the vault does not accumulate
credentials for tunnels that no longer exist.

---

## What is already good

Worth keeping and not diluting:

- `cert.pem` (account-scoped) never lands on the serving box; management runs on `g7`.
  This is the single best decision in the plan.
- Tunnel creds JSON: root:600, gitignored, revocable, with a deliberate sensitivity write-up.
- Zero open inbound ports as the target state; SSH via Tailscale instead of exposing sshd.
- HSTS sequencing (disable before repoint, re-enable after end-to-end HTTPS), including
  the `preload` caveat.
- Edge settings: Full (Strict) TLS, min TLS 1.2, managed WAF, Bot Fight Mode,
  with the BFM-vs-webhook interaction already flagged.
- The sysctl set itself is appropriate for a headless non-router.
- Prior audit discipline: the `noTLSVerify` artefact was caught and removed before push.

## Suggested action order

1. Before any new-box execution: decide H1 (symlink vs copy-with-diff); fix `listen 127.0.0.1:8090` (H2); switch the cloudflared install step to the apt repo (H4).
2. Fold H3 into the Phase 1 sub-plan: unattended-upgrades + ufw before the DNS repoint; skip fail2ban deliberately.
3. In the Phase 4 sub-plan: config edit before symlink script (M5); add `tunnel delete <old-UUID>` + old-disk wipe as explicit steps (M1); schedule Phase 5 immediately after (M2).
4. When Phase 7 happens: `secret_token` on the webhook, token out of shell history (M3).
5. Housekeeping when convenient: local-box.md trust-level update (M4), L1-L5.

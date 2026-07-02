# Cloudflare setup on new box - recap

## The goal

Stand up the full Cloudflare-tunnel stack on a fresh box (`pmn-14g4`, Ubuntu 26.04 LTS)
so the box is reachable from the internet over `pitrified.qzz.io`, behind Cloudflare's edge,
**replacing the previous box** as the live target for that domain.

This box becomes the new home for the landing page and the tunnelled services.
The work follows the repo's own guide, [`docs/01_box_setup.md`](../../docs/01_box_setup.md),
which lays out the same stack in 7 phases.

## Settled decisions (and why)

- **Same domain + Cloudflare account: `pitrified.qzz.io`.**
  The domain is already on Cloudflare (NS `devin/kate.ns.cloudflare.com`) from the prior setup.
  Phase 2 of the guide (domain registration, nameservers, edge settings) is already done; we reuse it.

- **Fresh tunnel, not the old one.**
  Run `cloudflared tunnel create` on `g7` (see credentials handling below) to get a new UUID +
  credentials JSON, rather than migrating the old tunnel's creds.
  Cleanest for a new box; a tunnel should only be run from one box at a time.
  Consequence: `configs/cloudflared/config.yml` must be updated - the tracked file still carries the
  old UUID `68aa8138-1812-446c-9faf-3760c42058d4` on both the `tunnel:` and `credentials-file:` lines.

- **This box replaces the old one.**
  Routing DNS for the root and subdomains to the new tunnel intentionally repoints
  `pitrified.qzz.io` away from the old box. That is the intent - the old box is being retired.
  No dual-run; only one box owns each hostname.

- **Drop openssh / the SSH-over-tunnel route; keep Tailscale SSH.**
  The box is reached over Tailscale SSH (built into `tailscaled`, nothing on port 22),
  and openssh-server is not installed.
  So Phase 6 (`ssh://localhost:22` ingress, `ssh.pitrified.qzz.io`) is dropped:
  the `ssh.*` ingress rule comes out of `config.yml`, and the guide's `sshd_config` hardening is moot.
  Remote access stays on Tailscale, which already works.

- **Privileged steps are handed to the user.**
  `sudo` on this box needs a TTY, so Claude cannot run privileged commands non-interactively.
  apt installs, `/etc` symlinks, `cloudflared service install`, and ufw are handed over as
  `! <command>` for the user to run in-session; non-privileged work Claude does directly.

- **Credentials handling (box classified low-secret).**
  Three distinct Cloudflare credentials, treated by sensitivity:
  - **`cert.pem` (account/zone-scoped, most sensitive)** - created by `cloudflared tunnel login`.
    Needed **only at management time** (`tunnel create` / `route dns` / `delete` / `list`),
    **never** read by `tunnel run`. **Decision: it never lands on this box.**
    Run every management command (`login`, `create`, `route dns`) from the trusted machine
    (laptop, `g7`), where `cert.pem` lives in `~/.cloudflared/`, then copy only the resulting
    `<UUID>.json` to this box over Tailscale SSH (`scp`). The guide must state, per command,
    which box it runs on (`g7` for management, `pmn-14g4` for install/service/config).
  - **`<UUID>.json` (per-tunnel, revocable)** - created by `tunnel create`, read by the service on
    every boot, so it must live on the box: `/etc/cloudflared/<UUID>.json`, `root:root`, `chmod 600`,
    **never committed**. Acceptable on a low-secret box because it is scoped to this one tunnel - if
    the box is compromised, delete/rotate the tunnel; no domain-wide exposure. A copy may be kept in
    the password manager as backup. (Token-model / dashboard-managed tunnels were considered but
    rejected: they trade our tracked `config.yml` workflow for dashboard-managed ingress.)
  - **API token** - not used; the CLI path needs no Terraform/REST token.
  - Consequence for Phase 4: `cert.pem` stays on `g7` and is never copied to this box.
    `tunnel login` / `create` / `route dns` all run on `g7`; only `<UUID>.json` is `scp`'d to
    `pmn-14g4`. **Skip the guide's copy of `cert.pem` into `/etc/cloudflared/`** - the running
    service needs only the JSON + `config.yml`.

## Scope for now

The user asked to **assess first** ("slow and steady"), then set up this tracked plan.
Execution is not started. This folder is the durable plan; phases are listed in
[`tracking.md`](tracking.md) as `planned`. Detailed per-phase sub-plans are written
just-in-time before each phase runs.

## Open questions

- Which services beyond the nginx landing page will this box actually run?
  The old `config.yml` referenced `entries.pitrified.qzz.io` -> `http://localhost:8000`.
  Decide per-subdomain ingress when we reach Phase 4. (ANS: pending)
- How much of Phase 1 hardening (unattended-upgrades, ufw, sysctl, fail2ban) to apply,
  given SSH hardening is moot without openssh.
  (ANS 2026-07-02, from the security audit: apt upgrade + unattended-upgrades (verified enabled)
  and `ufw default deny incoming` + `enable` go **before** the Phase 4 DNS repoint - with no
  openssh there is no inbound rule needed at all; verify a Tailscale SSH session survives
  `ufw enable` before closing the one that ran it. sysctl file any time via `deploy-configs.sh`.
  **Skip fail2ban**: no sshd and all web traffic arrives from the tunnel as localhost, so it
  has nothing to ban.)

## Pointers

- Guide the stack mirrors: [`docs/01_box_setup.md`](../../docs/01_box_setup.md)
- Tracked config files: `configs/cloudflared/config.yml`, `configs/nginx/hub`, `configs/sysctl/99-hardening.conf`
- Config deploy helper: [`scripts/deploy-configs.sh`](../../scripts/deploy-configs.sh)
  (replaced `setup-symlinks.sh` on 2026-07-02: root-owned copies with a diff gate, not symlinks)
- Full current-state assessment: [`01-assessment.md`](01-assessment.md)

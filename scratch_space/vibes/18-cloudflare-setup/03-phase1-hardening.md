---
status: planned
---

# Phase 1 - local hardening on `pmn-14g4`

## Overview

Partial Phase 1 of [`docs/01_box_setup.md`](../../docs/01_box_setup.md), scoped by the
decisions in [`00-start.md`](00-start.md) and the security audit
([`../19-security-audit/00-assessment.md`](../19-security-audit/00-assessment.md), H3):
automatic updates and a default-deny firewall go in **before** the Phase 4 DNS repoint
makes the box the live target. SSH hardening is moot (no openssh; Tailscale SSH) and
fail2ban is deliberately skipped.

`sudo` needs a TTY on this box, so every privileged command below is handed to the user
as `! <command>` in-session; Claude runs only the unprivileged checks.

## Goals

1. Automatic security updates installed and verified running.
2. ufw active with default deny incoming, zero inbound allow rules, Tailscale SSH still working.
3. Hardening sysctl settings deployed (root-owned copy) and applied.
4. Baseline checks recorded: AppArmor active, thermald active (lid-closed laptop).

## Plan

Ordered; each step notes who runs it.

1. **System update + unattended-upgrades** (user):
   - `! sudo apt update && sudo apt upgrade -y`
   - `! sudo apt install unattended-upgrades -y`
   - Verify (Claude, unprivileged):
     `systemctl status unattended-upgrades --no-pager` is active, and
     `apt-config dump APT::Periodic::Unattended-Upgrade` prints `"1"`.
     If not `"1"`: `! sudo dpkg-reconfigure -plow unattended-upgrades`.
2. **Ubuntu Pro attach** (user, optional but free): token from the Pro dashboard,
   typed by the user in-session (`! sudo pro attach <TOKEN>`), never stored in the repo.
   Verify with `pro status` (unprivileged).
3. **ufw** (user). No inbound rule at all - there is no openssh, and web traffic arrives
   via the outbound tunnel:
   - `! sudo ufw default deny incoming`
   - `! sudo ufw default allow outgoing`
   - `! sudo ufw enable`
   - **Lockout guard:** keep the current Tailscale SSH session open, then open a *second*
     session to confirm access still works before ending the first. Tailscale traffic
     arrives on `tailscale0`; if the second session fails, revert with
     `! sudo ufw disable` from the surviving session and investigate
     (fallback allow rule: `! sudo ufw allow in on tailscale0`).
   - Verify: `! sudo ufw status verbose` shows active, deny incoming, no allow rules.
4. **sysctl** (user): deploy the tracked file as a root-owned copy and apply:
   - `! sudo bash scripts/deploy-configs.sh`
     (also copies the cloudflared and nginx configs; harmless now - cloudflared and nginx
     are not installed yet, the script skips their validation, and Phase 3/4 redeploy after
     the real edits. The `config.yml` copy still carries the old UUID until Phase 4.)
   - `! sudo sysctl --system`
   - Verify (Claude): spot-check `sysctl kernel.kptr_restrict net.ipv4.conf.all.accept_redirects`
     against [`configs/sysctl/99-hardening.conf`](../../configs/sysctl/99-hardening.conf).
5. **Baseline checks** (user for the sudo ones):
   - `! sudo aa-status --summarized` - AppArmor enforcing.
   - `systemctl is-active thermald` (unprivileged) - thermal management on the lid-closed laptop.
   - Optional, physical-surface: disable USB storage per the guide
     (`install usb-storage /bin/false` modprobe drop-in). Decide in-session; skip is fine
     for a box at home.

## Out of scope

- sshd_config hardening - no openssh on this box (guide Phase 1.3 moot; Tailscale SSH).
- fail2ban - deliberately skipped: no sshd, and tunnel traffic reaches services as
  localhost, so there is nothing for it to ban (audit H3).
- nginx / cloudflared installs and config edits - Phases 3 and 4.
- Cloudflare edge settings - done previously (Phase 2) or handled in Phases 4/5.

## Done when

- `apt-config dump APT::Periodic::Unattended-Upgrade` prints `"1"` and the
  unattended-upgrades service is active.
- `sudo ufw status verbose`: active, default deny incoming, **no** inbound allow rules,
  and a fresh Tailscale SSH session connects with ufw enabled.
- `sysctl kernel.kptr_restrict` returns `2` and `/etc/sysctl.d/99-hardening.conf` is a
  root-owned regular file (not a symlink) matching the repo.
- AppArmor reports enforcing profiles; thermald is active.
- Log entry appended to [`tracking.md`](tracking.md) with anything that surprised.

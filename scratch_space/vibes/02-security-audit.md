# Security audit

## Context

We just made a commit tracking three `/etc` config files in a public GitHub repo
(`github.com/Pitrified/linux-box-cloudflare`, visibility: **public**).

The commit is **not yet pushed** (`origin/main` is one commit behind `HEAD`).
That gives us a clean window to act before anything lands on GitHub.

---

## What is in the commit

| File | Content |
| --- | --- |
| `configs/cloudflared/config.yml` | Tunnel UUID, credentials-file path, all ingress hostnames and internal ports |
| `configs/nginx/hub` | Internal port 8090, document root `/var/www/hub` |
| `configs/sysctl/99-hardening.conf` | Exact sysctl hardening settings applied |
| `scripts/setup-symlinks.sh` | Repo path, symlink targets (no secrets) |
| `.gitignore` | Excludes credentials JSON |

---

## Finding 1 - Tunnel UUID is in a public repo (ACCEPTED)

`configs/cloudflared/config.yml` contains the real tunnel UUID:

```
tunnel: 68aa8138-1812-446c-9faf-3760c42058d4
```

**Is this a secret?** No. The UUID appears as the left-hand side of a DNS CNAME record
(`<UUID>.cfargotunnel.com`) and is discoverable by anyone who runs `dig` or `nslookup` on any
of the tunnelled hostnames. It is not a credential.

**What an attacker can do with just the UUID:** nothing. The credentials JSON
(`/etc/cloudflared/<UUID>.json`) is the actual secret that authorises tunnel management.
That file is correctly excluded from git via `.gitignore`.

**Decision:** Accepted. The UUID is already public via DNS. Tracking the real `config.yml`
in the repo is acceptable.

---

## Finding 2 - Full internal architecture is documented publicly (MEDIUM)

The committed `config.yml` maps every hostname to an internal port:

```
pitrified.qzz.io        → localhost:8090  (nginx landing page)
entries.pitrified.qzz.io → localhost:8000  (entries app)
ssh.pitrified.qzz.io    → localhost:22    (SSH)
```

None of these ports are reachable from the internet - they are behind the Cloudflare Tunnel and
(for everything except the SSH host key) protected by Zero Trust auth. So an external attacker
cannot use this port map to directly attack services.

However, this information is useful for:
- Lateral movement if an attacker ever gains a foothold on the local network.
- Targeted social engineering (e.g. phishing that references the real service at `entries.pitrified.qzz.io`).
- Enumeration of what services exist, to prioritise attacks.

The SSH hostname (`ssh.pitrified.qzz.io`) is worth noting specifically. An attacker now knows
the exact endpoint to try. SSH is protected by key auth and the Zero Trust challenge, so this is
not a direct vulnerability - but removing security through obscurity is a minor weakening.

**Verdict:** Medium. Acceptable if the repo is private; more of a concern for a public repo.

---

## Finding 3 - `noTLSVerify: true` on the SSH ingress (RESOLVED)

`noTLSVerify` is not applicable to `ssh://` services - cloudflared passes SSH as a raw TCP proxy
and TLS verification has no meaning in that context. The flag was a copy-paste artefact.

**Action taken:** removed from `configs/cloudflared/config.yml`. The SSH ingress now reads:

```yaml
  - hostname: ssh.pitrified.qzz.io
    service: ssh://localhost:22
```

---

## Finding 4 - sysctl hardening config reveals gaps (RESOLVED)

The original `99-hardening.conf` was missing several parameters. The file has been expanded to
cover the full set of recommended settings for a headless non-routing server:

```ini
# Kernel hardening
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1

# TCP SYN flood protection
net.ipv4.tcp_syncookies = 1

# Reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Bogus ICMP error suppression
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Disable ICMP redirect acceptance
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Disable ICMP redirect sending
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable IP forwarding (not a router)
net.ipv4.ip_forward = 0

# Disable TCP timestamps (reduces uptime fingerprinting)
net.ipv4.tcp_timestamps = 0

# Log martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
```

Apply live (settings take effect on next boot automatically via symlink in `/etc/sysctl.d/`):

```bash
sudo sysctl -p /etc/sysctl.d/99-hardening.conf
```

Live kernel check showed most values were already at the hardened default
(`ip_forward=0`, `tcp_timestamps=0`, `log_martians=1`, `send_redirects=0`).
The main gap was `accept_redirects=1` which the updated file now explicitly sets to `0`.

---

## Finding 5 - nginx config reveals internal structure (LOW)

`configs/nginx/hub` reveals port 8090 and document root `/var/www/hub`. Neither is reachable
from outside. No real risk beyond the general architecture-exposure concern in Finding 2.

**Verdict:** Low.

---

## Finding 6 - Repo is public but commit is not yet pushed (KEY MITIGATOR)

The commit exists only locally. `origin/main` is one commit behind `HEAD`.
**Nothing has reached GitHub yet.** This is the critical fact - we have a clean window
to decide what goes public before it gets indexed.

---

## Summary table

| Finding | Sensitivity | Exploitable? | Status |
| --- | --- | --- | --- |
| Tunnel UUID public | Low | No (no credentials, already in DNS) | Accepted |
| Full service/port map public | Medium | No (behind Zero Trust) | Accepted |
| `noTLSVerify: true` documented | Very Low | No | Resolved - removed |
| sysctl gaps revealed | Low | No (no inbound ports) | Resolved - file expanded |
| nginx internals revealed | Low | No | Accepted |
| Commit not pushed yet | - | - | Window still open |

---

## Decisions and actions taken

| Item | Decision | Action |
| --- | --- | --- |
| Tunnel UUID in public repo | Accepted - UUID is already in public DNS CNAME records | None |
| Service/port map public | Accepted - all services are behind Zero Trust auth | None |
| `noTLSVerify: true` | Removed - meaningless for `ssh://` services | Removed from `config.yml` |
| sysctl gaps | Hardened | `99-hardening.conf` expanded with full parameter set |
| nginx config public | Accepted - port 8090 not reachable externally | None |
| Credentials JSON | Never tracked | Excluded via `.gitignore` |

The commit is ready to push.

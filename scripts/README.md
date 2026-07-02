# scripts/

Shell scripts for setting up and maintaining the linux box.

## setup-always-on.sh

Configures the laptop to keep running lid-closed while on AC power, adds a logind backstop,
and installs `lm-sensors` for thermal visibility. See
[`docs/always-on-server.md`](../docs/always-on-server.md) for the rationale.

Run as your **normal user** (not with sudo): the GNOME lid setting is per-user, and the
script elevates with `sudo` internally for the logind and apt steps.

**Usage:**

```bash
bash scripts/setup-always-on.sh
```

Battery behaviour is left at OS defaults (suspend on idle / low battery); only the AC case
is changed.

## deploy-configs.sh

Deploys the tracked config files to `/etc` as root-owned **copies**, showing a diff of
every pending change before installing. Run after cloning and after any config edit.

Replaces the old `setup-symlinks.sh`. Copies instead of symlinks on purpose:
symlinks into a user-writable checkout let any user-level compromise (or a bad
`git pull`) silently change root-consumed config. With copies, changing live config
requires sudo through this script, and the diff step is the review gate.

**Usage:**

```bash
sudo bash scripts/deploy-configs.sh
```

**What it does:**

| Target | Source in repo | Mode |
| --- | --- | --- |
| `/etc/cloudflared/config.yml` | `configs/cloudflared/config.yml` | copy (root:root 644) |
| `/etc/nginx/sites-available/hub` | `configs/nginx/hub` | copy (root:root 644) |
| `/etc/sysctl.d/99-hardening.conf` | `configs/sysctl/99-hardening.conf` | copy (root:root 644) |
| `/var/www/hub` | `sites/landing/` | symlink (site content, not config) |

After deploying, the script validates the cloudflared ingress config and runs `nginx -t`
(both skipped gracefully if the tool is not installed yet).

**Re-running is safe** - unchanged files are skipped, changed files show a diff and are
overwritten. Old symlinks from `setup-symlinks.sh` are replaced with real files.

**Restart services after running:**

```bash
sudo systemctl restart cloudflared
sudo systemctl restart nginx
sudo sysctl --system   # for sysctl changes
```

## setup-disposable-box.sh

Box-specific setup, kept separate from `deploy-configs.sh`.

`deploy-configs.sh` wires up the `/etc` service configs every box in the ecosystem needs.
This script instead installs the Claude rules that describe a **disposable, no-secret
sandbox** box (`configs/claude/rules/local-box.md`). That assumption does not hold for
boxes that store secrets, so it is opt-in and lives in its own script.

Run as your **normal user** (not with sudo): the symlink lands in `$HOME/.claude`.

**Usage:**

```bash
bash scripts/setup-disposable-box.sh
```

**What it does:**

| Target | Source in repo |
| --- | --- |
| `~/.claude/rules/local-box.md` | `configs/claude/rules/local-box.md` |

**Re-running is safe** - `ln -sf` overwrites the existing symlink without prompting.

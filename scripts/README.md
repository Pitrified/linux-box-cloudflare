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

## setup-symlinks.sh

Creates symlinks from `/etc` (and `/var/www`) pointing at the tracked config and site
files in this repo. Run once after cloning, and again whenever config file paths change.

**Usage:**

```bash
sudo bash scripts/setup-symlinks.sh
```

**What it does:**

| Target | Source in repo |
| --- | --- |
| `/etc/cloudflared/config.yml` | `configs/cloudflared/config.yml` |
| `/etc/nginx/sites-available/hub` | `configs/nginx/hub` |
| `/var/www/hub` | `sites/landing/` |

After running, the script validates the cloudflared ingress config and runs `nginx -t`.

**Re-running is safe** - `ln -sf` / `ln -sfn` overwrites existing symlinks without
prompting.

**Restart services after running:**

```bash
sudo systemctl restart cloudflared
sudo systemctl restart nginx
```

## setup-disposable-box.sh

Box-specific setup, kept separate from `setup-symlinks.sh`.

`setup-symlinks.sh` wires up the `/etc` service configs every box in the ecosystem needs.
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

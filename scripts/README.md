# scripts/

Shell scripts for setting up and maintaining the linux box.

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

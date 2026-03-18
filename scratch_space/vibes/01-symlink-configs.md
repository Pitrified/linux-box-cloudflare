# Symlink configs to this repo

## Overview

Following the guide in
`docs/01_box_setup.md`
we have set up the linux box.

however some config files are manually written in the box,
and are not tracked in git;
mostly `/etc/cloudflared/config.yml`, but maybe other files.

is there a way to symlink these files to this repo, so that they can be tracked in git and easily updated from the repo?

## Plan

Yes - symlinking system config files into the repo is a clean approach.
The idea is to store the canonical file in the repo and point the system path at it with a symlink.
`cloudflared` (and nginx, sysctl, etc.) will read the symlink transparently.

### Files to track

| System path | Repo path |
| --- | --- |
| `/etc/cloudflared/config.yml` | `configs/cloudflared/config.yml` |
| `/etc/nginx/sites-available/hub` | `configs/nginx/hub` |
| `/etc/sysctl.d/99-hardening.conf` | `configs/sysctl/99-hardening.conf` |

`/etc/modprobe.d/disable-usb-storage.conf` was not created on this machine (USB storage was not disabled), so it is not tracked.

Do not store the tunnel credentials JSON (`/etc/cloudflared/<UUID>.json`) in git - it is a secret.
It is listed in `.gitignore`.

### One-time migration (per file)

1. Copy the live file into the repo:

```bash
sudo cp /etc/cloudflared/config.yml \
    /home/pmn/repos/linux-box-cloudflare/configs/cloudflared/config.yml
sudo chown pmn:pmn /home/pmn/repos/linux-box-cloudflare/configs/cloudflared/config.yml
```

2. Replace the system file with a symlink pointing back to the repo:

```bash
sudo ln -sf /home/pmn/repos/linux-box-cloudflare/configs/cloudflared/config.yml \
    /etc/cloudflared/config.yml
```

3. Verify the link and that the service still reads it:

```bash
ls -la /etc/cloudflared/config.yml
sudo cloudflared tunnel ingress validate
sudo systemctl status cloudflared
```

4. Commit the new file:

```bash
cd /home/pmn/repos/linux-box-cloudflare
git add configs/cloudflared/config.yml
git commit -m "track /etc/cloudflared/config.yml in repo"
```

### Repeat for other files

Same four steps for nginx and sysctl configs.
For nginx, test with `sudo nginx -t` after creating the symlink.

### Updating a config going forward

Edit the file directly in the repo (it is a plain file, the symlink is transparent):

```bash
nano configs/cloudflared/config.yml
# test, then restart the service
sudo systemctl restart cloudflared
# commit
git add configs/cloudflared/config.yml && git commit -m "update tunnel ingress"
```

### Caveats

- `/etc/cloudflared/config.yml` is owned by root in the Phase 4 setup.
  After symlinking, `cloudflared` (running as root via systemd) can still read the file
  as long as the repo directory and the file itself are world-readable (`chmod 644`).
  Confirm with `sudo cloudflared tunnel ingress validate` after each change.
- The symlink target must be an absolute path so it resolves correctly regardless of cwd.
- If the repo is ever moved or cloned to a different path, all symlinks must be recreated.
  Run `sudo bash scripts/setup-symlinks.sh` to recreate them automatically.
  The expected repo path is documented in `docs/01_box_setup.md`.
- `/etc/cloudflared/<UUID>.json` is intentionally not tracked - it is listed in `.gitignore`.

### Status

Implemented. Three symlinks are live and both `cloudflared` and `nginx` validated successfully.
See `scripts/setup-symlinks.sh` for the automation script and `docs/01_box_setup.md` for the
"Config File Tracking" section.

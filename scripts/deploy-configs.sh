#!/usr/bin/env bash
# scripts/deploy-configs.sh
#
# Deploys the tracked config files in this repo to their /etc locations as
# root-owned COPIES (not symlinks). The repo stays the source of truth; this
# script is the deploy gate: it shows a diff of every pending change before
# installing, so nothing lands in /etc without being seen.
#
# Why copies: /etc symlinks into a user-writable checkout let any user-level
# compromise (or a bad `git pull`) silently change root-consumed config
# (sysctl, nginx, tunnel ingress). Root-owned copies restore the privilege
# boundary - changing live config requires sudo through this script.
#
# The landing page stays a symlink: it is site content read by nginx workers,
# not root-consumed config, and live-editing it is the point.
#
# Usage:
#   sudo bash scripts/deploy-configs.sh
#
# Replaces the old setup-symlinks.sh. On a box that still has the old
# symlinks, this script overwrites them with real files.

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Run with sudo: sudo bash scripts/deploy-configs.sh" >&2
    exit 1
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Repo root: $REPO"

deploy() {
    local src="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && ! [ -L "$dest" ] && diff -q "$dest" "$src" >/dev/null 2>&1; then
        echo "  unchanged $dest"
        return
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        echo "  diff for $dest (live vs repo):"
        diff -u "$dest" "$src" | sed 's/^/    /' || true
    else
        echo "  new file $dest"
    fi
    # install removes a pre-existing symlink and writes a real root-owned file
    rm -f "$dest"
    install -o root -g root -m 644 "$src" "$dest"
    echo "  installed $dest"
}

echo ""
echo "=== cloudflared ==="
deploy "$REPO/configs/cloudflared/config.yml" /etc/cloudflared/config.yml

echo ""
echo "=== nginx ==="
deploy "$REPO/configs/nginx/hub" /etc/nginx/sites-available/hub
deploy "$REPO/configs/nginx/cc-kb" /etc/nginx/sites-available/cc-kb
# sites-enabled is a plain symlink into sites-available (hub was linked by hand;
# doing it here keeps a fresh box complete)
ln -sfn /etc/nginx/sites-available/cc-kb /etc/nginx/sites-enabled/cc-kb
echo "  enabled  /etc/nginx/sites-enabled/cc-kb"

echo ""
echo "=== sysctl ==="
deploy "$REPO/configs/sysctl/99-hardening.conf" /etc/sysctl.d/99-hardening.conf

echo ""
echo "=== sites (symlink, content not config) ==="
mkdir -p /var/www
ln -sfn "$REPO/sites/landing" /var/www/hub
echo "  linked /var/www/hub -> $REPO/sites/landing"
# cc-kb serves the mkdocs build from the sibling repo; Access verified on the
# canary 2026-07-16 (controcanto plan 15, step D). sites/cc-kb-canary stays in
# the repo for the next <prefix>-kb rollout.
ln -sfn "$REPO/../controcanto/site" /var/www/cc-kb
echo "  linked /var/www/cc-kb -> $REPO/../controcanto/site"

echo ""
echo "=== Validation ==="
if command -v cloudflared >/dev/null 2>&1; then
    if cloudflared tunnel ingress validate; then
        echo "cloudflared: OK"
    else
        echo "cloudflared: validation failed (expected on a fresh box before the credentials JSON exists)"
    fi
else
    echo "cloudflared: not installed, skipping validation"
fi
if command -v nginx >/dev/null 2>&1; then
    nginx -t && echo "nginx: OK"
else
    echo "nginx: not installed, skipping validation"
fi

echo ""
echo "Configs deployed."
echo "Restart services to pick up changes:"
echo "  sudo systemctl restart cloudflared"
echo "  sudo systemctl restart nginx"
echo "  sudo sysctl --system   # for sysctl changes"

#!/usr/bin/env bash
# scripts/setup-symlinks.sh
#
# Creates /etc symlinks pointing at the tracked config files in this repo.
# Run with sudo from anywhere - the repo path is resolved from this script's location.
#
# Usage:
#   sudo bash scripts/setup-symlinks.sh

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Repo root: $REPO"

link() {
    local src="$1"
    local dest="$2"
    ln -sf "$src" "$dest"
    echo "  linked $dest -> $src"
}

echo ""
echo "=== cloudflared ==="
link "$REPO/configs/cloudflared/config.yml" /etc/cloudflared/config.yml

echo ""
echo "=== nginx ==="
link "$REPO/configs/nginx/hub" /etc/nginx/sites-available/hub

echo ""
echo "=== sysctl ==="
link "$REPO/configs/sysctl/99-hardening.conf" /etc/sysctl.d/99-hardening.conf

echo ""
echo "=== Validation ==="
cloudflared tunnel ingress validate && echo "cloudflared: OK"
nginx -t && echo "nginx: OK"

echo ""
echo "All symlinks created and validated."
echo "Restart services if needed:"
echo "  sudo systemctl restart cloudflared"
echo "  sudo systemctl restart nginx"

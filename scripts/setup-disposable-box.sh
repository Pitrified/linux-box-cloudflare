#!/usr/bin/env bash
# scripts/setup-disposable-box.sh
#
# Box-specific setup, separate from setup-symlinks.sh.
#
# setup-symlinks.sh wires up the /etc service configs that any linux box in
# this ecosystem needs. This script instead installs the Claude rules that
# describe a *disposable, no-secret sandbox* box (configs/claude/rules/local-box.md).
# That assumption does not hold for boxes that store secrets,
# so it lives in its own script and is opt-in.
#
# Runs as the normal user (no sudo) - the symlink lands in $HOME/.claude.
#
# Usage:
#   bash scripts/setup-disposable-box.sh

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Repo root: $REPO"

echo ""
echo "=== claude rules (disposable box) ==="
mkdir -p "$HOME/.claude/rules"
ln -sf "$REPO/configs/claude/rules/local-box.md" "$HOME/.claude/rules/local-box.md"
echo "  linked $HOME/.claude/rules/local-box.md -> $REPO/configs/claude/rules/local-box.md"

echo ""
echo "Done."

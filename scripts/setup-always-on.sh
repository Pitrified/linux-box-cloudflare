#!/usr/bin/env bash
# scripts/setup-always-on.sh
#
# Configures the laptop to stay running lid-closed while on AC power, and installs
# thermal-monitoring visibility. See docs/always-on-server.md for the full rationale.
#
# Run as your NORMAL user (not with sudo): the GNOME lid setting is per-user, while the
# logind drop-in and lm-sensors install are elevated with sudo internally (it will prompt
# for your password once).
#
# Usage:
#   bash scripts/setup-always-on.sh

set -euo pipefail

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "Run this as your normal user, not with sudo." >&2
    echo "The GNOME lid setting is per-user; the script elevates with sudo where needed." >&2
    exit 1
fi

# gsettings needs the user session bus, which may be unset over SSH.
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

echo "=== 1. GNOME: do nothing on lid close while on AC ==="
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'
echo "  lid-close-ac-action = $(gsettings get org.gnome.settings-daemon.plugins.power lid-close-ac-action)"
echo "  lid-close-battery-action = $(gsettings get org.gnome.settings-daemon.plugins.power lid-close-battery-action) (left as default)"

echo ""
echo "=== 2. logind backstop: ignore lid on AC for non-GNOME states ==="
sudo install -d /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/keep-awake.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
echo "  wrote /etc/systemd/logind.conf.d/keep-awake.conf"
sudo systemctl daemon-reload
sudo systemctl restart systemd-logind
echo "  reloaded and restarted systemd-logind"

echo ""
echo "=== 3. Thermal visibility: lm-sensors ==="
if command -v sensors >/dev/null 2>&1; then
    echo "  lm-sensors already installed"
else
    sudo apt update && sudo apt install -y lm-sensors
    sudo sensors-detect --auto
fi

echo ""
echo "=== Done. Verification ==="
echo "  lid-close-ac-action: $(gsettings get org.gnome.settings-daemon.plugins.power lid-close-ac-action)"
echo "  logind drop-in:"
sed 's/^/    /' /etc/systemd/logind.conf.d/keep-awake.conf
echo "  sensors:"
sensors 2>/dev/null | sed 's/^/    /' || echo "    (run 'sensors' after a reboot if modules were just loaded)"
echo ""
echo "Battery behaviour is left at OS defaults on purpose (suspend on idle / low battery)."
echo "Close the lid on AC: screen powers off, the box keeps running and stays reachable."

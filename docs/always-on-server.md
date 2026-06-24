# Always-On Server: Running a Laptop Lid-Closed 24/7

This guide turns a laptop into an always-on server that keeps running with the lid shut while on AC power,
stays reachable over Tailscale SSH,
and still behaves like a normal laptop when unplugged.
It complements the box hardening in [`01_box_setup.md`](01_box_setup.md):
that guide secures and exposes the box, this one keeps it awake and reachable.

Tested on Ubuntu 26.04 with GNOME, reached over Tailscale SSH.
The same logic applies to any systemd + logind machine; the GNOME step is desktop-specific.

## Quick setup

To apply everything in this guide at once, run the helper script as your **normal user**
(not with sudo - the GNOME lid setting is per-user; the script elevates internally for the
logind and apt steps):

```bash
bash scripts/setup-always-on.sh
```

The rest of this guide explains what it does and why, and how to do it by hand.

## Goal

- **On AC:** lid closed, screen off, system stays running and reachable. Never suspends.
- **On battery:** behave like a regular laptop.
  Suspend on idle and on low battery using the OS defaults.
  There is no custom "AC is failing" detection -
  unplugging just hands control back to the normal laptop power behaviour.

## Why keep it awake instead of letting it sleep

A suspended laptop is **not reachable**.
During suspend (S3 / s2idle) the CPU halts, `tailscaled` stops running, the network drops,
and wake-on-LAN over Wi-Fi does not bring it back.
Remote access only works while the box is awake,
so "always on while on AC" is what makes the box a usable server.
Letting it sleep on AC would cost you remote access until you physically open the lid.

## How remote access survives a headless box

Access is via **Tailscale SSH**, enabled once with:

```bash
sudo tailscale up --ssh
```

This runs an SSH server inside `tailscaled` rather than a separate `openssh-server`
(nothing listens on port 22).
The key properties:

- `tailscaled` is a **system service** (`WantedBy=multi-user.target`),
  started at boot and independent of any graphical login.
- Its preferences persist (`RunSSH: true`, `WantRunning: true`),
  so the SSH server comes back automatically after a reboot with no command to re-run.

Because access does not depend on the GNOME session,
the box stays reachable in every awake state:
the login screen, a crashed or logged-out session, or fully headless.

Verify the prefs:

```bash
sudo tailscale debug prefs | grep -E 'RunSSH|WantRunning'
```

## Step 1: Lid close behaviour (AC = stay on, battery = suspend)

Two layers control the lid.
GNOME owns it while a desktop session is active;
logind owns it otherwise (login screen, no session).
Set both so the behaviour is consistent.

**1. GNOME (the active-session handler)**

GNOME exposes the lid action directly.
Disable suspend-on-lid only for AC; leave battery alone:

```bash
# AC: do nothing on lid close
gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing'

# battery: leave the default 'suspend' (no command needed)
```

**2. logind (the backstop for non-GNOME states)**

Drop-ins live in `/etc/systemd/logind.conf.d/` so the change survives package upgrades.

```bash
sudo install -d /etc/systemd/logind.conf.d
sudo tee /etc/systemd/logind.conf.d/keep-awake.conf <<'EOF'
[Login]
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF

sudo systemctl restart systemd-logind   # or reboot to avoid disturbing a local GUI session
```

`HandleLidSwitchExternalPower` covers AC; `HandleLidSwitch` (battery) is left at its default `suspend`.
`IdleAction` is intentionally not set - idle is handled by GNOME below.

> **Note:** restarting `systemd-logind` over SSH is safe
> (your session is a `pts` session, not seat-bound)
> but can briefly disturb a local GNOME session on the physical display.
> Reboot instead if you want zero disturbance.

## Step 2: Idle and low-battery behaviour (mostly already correct)

The defaults already match the goal; confirm them rather than change them.

| Concern | Setting | Wanted value |
| --- | --- | --- |
| Idle suspend on AC | `sleep-inactive-ac-type` | `'nothing'` |
| Idle suspend on battery | `sleep-inactive-battery-type` | `'suspend'` (default) |
| Critical battery action | UPower `CriticalPowerAction` | `HybridSleep` (default) |

```bash
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type      # 'nothing'
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type # 'suspend'
```

`sleep-inactive-ac-type 'nothing'` keeps the box awake while plugged in.
On battery the default idle suspend and `HybridSleep` at critical level mean that,
if AC is lost and the battery runs low,
the box saves state to disk (8 GB swap present) and suspends before the battery empties -
all stock behaviour, no custom logic.

> **Do not mask the sleep targets.**
> `systemctl mask sleep.target suspend.target ...` would block the wanted battery suspend
> and the critical-battery save.
> The lid and idle settings above already give "awake on AC" without disabling suspend globally.

## Step 3: Thermal management

A laptop run lid-closed 24/7 has worse airflow, so heat is the main physical risk.
Keep it ventilated, ideally on a stand or slightly open.

`thermald` provides proactive Intel thermal throttling and is enabled by default on Ubuntu;
confirm it is running:

```bash
systemctl status thermald --no-pager | grep -E 'Loaded|Active'
```

For visibility, install `lm-sensors`:

```bash
sudo apt update && sudo apt install -y lm-sensors
sudo sensors-detect --auto     # probe hardware, write /etc/modules-load.d
sensors                        # read temperatures
```

The kernel also has hard critical trip points that force a shutdown as a last resort,
so `thermald` + `lm-sensors` covers prevention and visibility.

### Optional thermal monitoring (not set up by default)

If you want active alerting on a closed-lid box, these build on the above:

- A `systemd` timer plus a script polling `x86_pkg_temp`, warning above a threshold (~85 °C).
- Routing that warning to a Telegram bot so the box cannot overheat silently.
- A soft auto-shutdown safety net at a high threshold (~92 °C), above `thermald`.

## Verification

```bash
# lid: AC action is 'nothing', logind drop-in present
gsettings get org.gnome.settings-daemon.plugins.power lid-close-ac-action   # 'nothing'
grep . /etc/systemd/logind.conf.d/keep-awake.conf

# remote access server is on and persistent
sudo tailscale debug prefs | grep -E 'RunSSH|WantRunning'

# thermal
systemctl is-active thermald
sensors
```

Then close the lid while on AC:
the internal panel powers off, the system keeps running,
and an SSH session over Tailscale stays connected.

## Reverting

```bash
# lid behaviour
gsettings reset org.gnome.settings-daemon.plugins.power lid-close-ac-action
sudo rm -f /etc/systemd/logind.conf.d/keep-awake.conf
sudo systemctl restart systemd-logind
```

`thermald` and `lm-sensors` are non-invasive and can be left in place.

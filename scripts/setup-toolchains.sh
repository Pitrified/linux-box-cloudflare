#!/usr/bin/env bash
# scripts/setup-toolchains.sh
#
# Flutter stable, the Android SDK, the emulator and one AVD, user-level only.
# Needs the box packages first (git-lfs, openjdk-17-jdk-headless, unzip, curl):
# see docs/01_box_setup.md, "Box packages and services".
#
# Re-running is safe: every step skips what is already in place, except the
# SDK install and the AVD, which are refreshed.
#
# Usage:
#   bash scripts/setup-toolchains.sh

set -euo pipefail
echo "start $(date -Is)"

git lfs install

# PATH block above the interactivity guard in ~/.bashrc: non-interactive shells
# (ssh commands, Claude sessions) need it too, and .bashrc returns at the guard.
# Not ~/.profile: only login shells read it.
# shellcheck disable=SC2016  # the literal text of the line, not its expansion
if ! grep -q 'ANDROID_HOME="$HOME/android-sdk"' ~/.bashrc; then
    cp ~/.bashrc ~/.bashrc.bak-before-flutter
    python3 - <<'EOF'
import pathlib
p = pathlib.Path.home() / ".bashrc"
s = p.read_text()
block = '''# Flutter + Android SDK (linux-box-cloudflare scripts/setup-toolchains.sh).
# Above the interactivity guard on purpose: non-interactive shells need it too, and .bashrc
# returns below.
export ANDROID_HOME="$HOME/android-sdk"
case ":$PATH:" in
  *":$HOME/flutter/bin:"*) ;;
  *) export PATH="$HOME/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH" ;;
esac

'''
anchor = "# If not running interactively"
assert anchor in s, "interactivity guard not found in ~/.bashrc"
p.write_text(s.replace(anchor, block + anchor, 1))
EOF
    echo "bashrc PATH block added"
fi
export ANDROID_HOME="$HOME/android-sdk"
export PATH="$HOME/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# Flutter stable
[ -d ~/flutter ] || git clone --quiet https://github.com/flutter/flutter.git -b stable ~/flutter

# Android command-line tools
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/clt.zip" https://dl.google.com/android/repository/commandlinetools-linux-14742923_latest.zip
    unzip -q "$tmp/clt.zip" -d "$tmp"
    mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -rf "$tmp"
fi

# `yes` gets SIGPIPE when the reader exits, which fails the pipe under pipefail
yes | sdkmanager --licenses >/dev/null || true
# large downloads: on a flaky connection a `Connection reset` here needs a rerun
sdkmanager --install "platform-tools" "build-tools;36.0.0" "platforms;android-36" \
    "emulator" "system-images;android-36;default;x86_64" >/dev/null
echo "sdk packages installed"

yes | flutter doctor --android-licenses >/dev/null || true
flutter config --no-enable-ios --no-enable-web --no-enable-linux-desktop
flutter doctor -v

# the emulator needs /dev/kvm: no kvm group, a `user:<you>:rw-` ACL from the
# desktop login grants it (check with `getfacl /dev/kvm`); without it the
# x86_64 image runs unaccelerated
avdmanager create avd -n fala_api36 -k "system-images;android-36;default;x86_64" -d pixel_6 --force </dev/null
echo "avd created"

echo "end $(date -Is)"

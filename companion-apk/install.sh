#!/usr/bin/env bash
# Sideloads and configures the companion boot-fixer APK on the Fire TV.
#   ADB_SERIAL=<tv-ip>:5555 ./install.sh          # build, install, grant, opt-in
#   ADB_SERIAL=<tv-ip>:5555 ./install.sh --undo   # remove app and opt-in marker
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

PKG="io.github.vladislavekimtcov.firetvfixer"
MARKER_DIR="/sdcard/Android/media/$PKG"
TV=${ADB_SERIAL:-}
[[ -n $TV ]] || { echo "error: set ADB_SERIAL=<tv-ip>:5555" >&2; exit 1; }

ADB=${ADB:-adb}

if [[ ${1:-} == "--undo" ]]; then
  echo "Removing companion fixer from $TV..."
  "$ADB" -s "$TV" shell "rm -rf $MARKER_DIR" || true
  "$ADB" -s "$TV" uninstall "$PKG" || true
  echo "Removed $PKG and opt-in marker."
  exit 0
fi

if [[ ! -f build/firetv-adb-fixer.apk ]]; then
  ./build.sh
fi

echo "Installing $PKG onto $TV..."
"$ADB" -s "$TV" install -r build/firetv-adb-fixer.apk

echo "Granting WRITE_SECURE_SETTINGS..."
"$ADB" -s "$TV" shell pm grant "$PKG" android.permission.WRITE_SECURE_SETTINGS

echo "Creating opt-in marker ($MARKER_DIR/keep-adb-on)..."
"$ADB" -s "$TV" shell "mkdir -p $MARKER_DIR && touch $MARKER_DIR/keep-adb-on"

echo "Verifying via diagnostic broadcast (NowReceiver)..."
"$ADB" -s "$TV" shell am broadcast -n "$PKG/.NowReceiver" || true

echo "Success: Fire TV ADB Fixer is installed and active."

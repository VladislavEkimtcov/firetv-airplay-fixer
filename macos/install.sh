#!/usr/bin/env bash
# Installs or uninstalls the AirPlay sweeper as a macOS launchd agent.
# Usage:
#   ./macos/install.sh --tv <ip>:5555     # install or update
#   ./macos/install.sh --status           # check service status and logs
#   ./macos/install.sh --undo             # remove launchd agent
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

LABEL="io.github.vladislavekimtcov.firetv-airplay-fixer"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
LOG="$HOME/Library/Logs/firetv-airplay-fixer.log"
ERR="$HOME/Library/Logs/firetv-airplay-fixer.err"

TV=""
ACTION="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tv)
      TV="$2"
      shift 2
      ;;
    --undo)
      ACTION="undo"
      shift
      ;;
    --status)
      ACTION="status"
      shift
      ;;
    *)
      if [[ -z $TV && "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ ]]; then
        TV="$1"
        shift
      else
        echo "Unknown option: $1" >&2
        echo "Usage: $0 [--tv <tv-ip>:5555] [--status] [--undo]" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ $ACTION == "status" ]]; then
  echo "==> Service Status:"
  launchctl list | grep "$LABEL" || echo "Service not currently registered in $DOMAIN"
  echo ""
  echo "==> Recent Log Entries ($LOG):"
  if [[ -f $LOG ]]; then
    tail -n 20 "$LOG"
  else
    echo "No log file found."
  fi
  exit 0
fi

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [[ $ACTION == "undo" ]]; then
  rm -f "$PLIST"
  echo "Successfully removed launchd agent $LABEL"
  exit 0
fi

# Detect ADB
ADB=$(command -v adb || true)
if [[ -z $ADB ]]; then
  for cand in /opt/homebrew/bin/adb /usr/local/bin/adb "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [[ -x $cand ]]; then ADB=$cand; break; fi
  done
fi
[[ -n $ADB ]] || { echo "error: adb not found. Install Android platform tools: brew install android-platform-tools" >&2; exit 1; }

TV=${TV:-${ADB_SERIAL:-}}
[[ -n $TV ]] || { echo "error: missing TV address. Pass --tv <tv-ip>:5555 or set ADB_SERIAL." >&2; exit 1; }
[[ $TV == *:* ]] || TV="$TV:5555"

# Verify initial connection
echo "Connecting to $TV via ADB..."
"$ADB" connect "$TV" >/dev/null 2>&1 || true
STATE=$("$ADB" -s "$TV" get-state 2>/dev/null || echo "offline")
if [[ $STATE == "unauthorized" ]]; then
  echo "⚠️ TV reports 'unauthorized'. Check the TV screen and select 'Always allow from this computer'." >&2
  exit 1
elif [[ $STATE != "device" ]]; then
  echo "⚠️ TV currently unreachable at $TV ($STATE). Proceeding with install; the sweeper will auto-reconnect when the TV comes online."
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$PWD/sweep.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ADB</key><string>$ADB</string>
    <key>ADB_SERIAL</key><string>$TV</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Standard</string>
  <key>LowPriorityIO</key><true/>
  <key>StandardErrorPath</key><string>$ERR</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed and started $LABEL"
echo "Log: $LOG"

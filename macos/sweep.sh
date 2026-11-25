#!/usr/bin/env bash
# Event-driven clean-up and Bonjour proxy for the Fire TV AirPlay bug.
#
# Background:
# 1. Leaving an AirPlay session (with HOME or BACK) leaves the player task behind.
#    When low memory kills the background player process (seen ~1.7s after HOME on 2GB TVs),
#    the Mac's automatic reconnect ~10s later lands on that dead task. The player crashes,
#    leaving the Mac "sharing into nothing" until a 40s timeout occurs.
# 2. Memory pressure also causes com.amazon.airplaydaemon to drop Bonjour advertising
#    (_airplay._tcp.) while RTSP port 7000 remains open and healthy. Macs and iOS devices
#    lose mDNS discovery or fail connecting to stale cached IPs.
#
# Solution:
# - Monitors the TV event log over network ADB. When am_proc_died fires for the player,
#   safely purges leftover hidden tasks (only while no active player runs).
# - Probes RTSP port 7000. If open but native Bonjour advertising has dropped, launches
#   a local `dns-sd -P` proxy so Apple devices can discover and connect to the TV.
set -u

TV=${ADB_SERIAL:?set ADB_SERIAL=<tv-ip>:5555}
ADB=${ADB:-adb}
LOG=${LOG:-$HOME/Library/Logs/firetv-airplay-fixer.log}
PLAYER=com.apple.airplay.amazon.airplay

note() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }
# Non-blocking ADB wrapper with 15s alarm
run() { perl -e 'alarm shift; exec @ARGV' 15 "$ADB" -s "$TV" "$@"; }

connected() {
  [[ $(run get-state 2>/dev/null) == device ]] && return 0
  perl -e 'alarm 15; exec @ARGV' "$ADB" connect "$TV" >/dev/null 2>&1
  [[ $(run get-state 2>/dev/null) == device ]]
}

# Removes hidden AirPlay tasks when the player process has terminated
sweep() {
  local why=$1 list id
  if run shell pidof "$PLAYER" >/dev/null 2>&1; then return 0; fi
  list=$(run shell am stack list 2>/dev/null) || return 0
  for id in $(printf '%s\n' "$list" |
      sed -nE "s#^ *taskId=([0-9]+): ${PLAYER//./\\.}/[^ ]* .* visible=false( .*)?\$#\\1#p"); do
    run shell am stack remove "$id" >/dev/null 2>&1 && note "removed dead AirPlay task $id ($why)"
  done
}

BONJOUR_PID=
stop_bonjour() {
  if [[ -n ${BONJOUR_PID:-} ]] && kill -0 "$BONJOUR_PID" 2>/dev/null; then
    kill "$BONJOUR_PID" 2>/dev/null || true
    wait "$BONJOUR_PID" 2>/dev/null || true
    note "stopped Bonjour proxy (pid $BONJOUR_PID)"
    BONJOUR_PID=
  fi
}
trap 'stop_bonjour; exit 0' EXIT TERM INT

# On macOS, proxies Bonjour adverts if the TV drops mDNS while RTSP 7000 is listening.
check_bonjour() {
  command -v dns-sd >/dev/null 2>&1 || return 0
  local ip=${TV%:5555}
  if ! nc -z -G 2 "$ip" 7000 2>/dev/null; then
    stop_bonjour
    return 0
  fi
  if [[ -n ${BONJOUR_PID:-} ]] && kill -0 "$BONJOUR_PID" 2>/dev/null; then
    return 0
  fi
  local name
  name=$(run shell settings get global device_name 2>/dev/null | tr -d '\r')
  [[ -n $name ]] || name="Fire TV"
  if perl -e 'alarm 2; exec @ARGV' dns-sd -B _airplay._tcp local. 2>/dev/null | grep -q "$name"; then
    return 0
  fi
  local model mac serial host
  model=$(run shell getprop ro.product.model 2>/dev/null | tr -d '\r')
  [[ -n $model ]] || model="AFTHY7ABBA"
  mac=$(run shell 'cat /sys/class/net/wlan0/address 2>/dev/null || cat /sys/class/net/eth0/address 2>/dev/null' | tr -d '\r' | tr '[:lower:]' '[:upper:]')
  [[ -n $mac ]] || mac="00:00:00:00:00:00"
  serial=$(run shell getprop ro.serialno 2>/dev/null | tr -d '\r')
  host="${name//[^a-zA-Z0-9-]/_}.local"

  dns-sd -P "$name" _airplay._tcp local. 7000 "$host" "$ip" \
    "manufacturer=Amazon" "model=$model" "deviceid=$mac" "pi=$mac" \
    "features=0x7F8AD0,0x38BCF46" "flags=0x244" "srcvers=377.40.00" "protovers=1.1" \
    "acl=0" "rsf=0x3" ${serial:+"serialNumber=$serial"} >/dev/null 2>&1 &
  BONJOUR_PID=$!
  note "started Bonjour proxy for $name at $ip:7000 (pid $BONJOUR_PID)"
}

note "sweeper started for $TV"

while true; do
  if connected; then
    sweep "connect"
    check_bonjour
    # -T 1: start at the newest line, so old deaths are not replayed.
    "$ADB" -s "$TV" logcat -v brief -b events -T 1 2>/dev/null | while IFS= read -r line; do
      case $line in
        *am_proc_died*",$PLAYER,"*) sweep "player died" ;;
      esac
    done
  fi
  stop_bonjour
  sleep 10
done

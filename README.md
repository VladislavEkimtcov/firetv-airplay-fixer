# Fire TV AirPlay Fixer & Network ADB Restorer

Lightweight background utility and companion tool to resolve AirPlay screen mirroring failures, mDNS discovery drops, and boot-time ADB disablement on Amazon Fire TV devices (Fire OS 6, 7, and 8).

---

## Symptoms & Root Causes

Many Fire TV models (including Fire TV Stick 4K Max, Cube, Omni, and 4-Series) experience severe AirPlay unreliability:

1. **AirPlay Works Once, Then Fails on Reconnect**
   - **Symptom:** AirPlay screen mirroring connects cleanly on the first attempt. Subsequent connection attempts show a black screen, infinite loading spinner, or time out after 40 seconds.
   - **Cause:** When an AirPlay session ends, the Fire OS window manager retains the background player task. Due to low memory conditions on 1.5 GB–2 GB devices, the underlying process (`com.apple.airplay.amazon.airplay`) is terminated. When macOS or iOS reconnects, Fire OS attempts to restore the stale task instead of initializing a fresh activity stack.
   - **Fix:** The host sweeper tracks system event broadcasts via ADB and promptly removes obsolete player task IDs whenever process death is reported, ensuring future connections start with a clean stack.

2. **Fire TV Disappears from Screen Mirroring (Bonjour Drop)**
   - **Symptom:** The Fire TV vanishes from the macOS Control Center or iOS AirPlay menu, or connection attempts fail due to stale IP routing.
   - **Cause:** System memory pressure triggers an `onLowMemory` trim on `com.amazon.airplaydaemon`, causing it to drop local mDNS advertisements (`_airplay._tcp.`) while its RTSP server on port 7000 remains active.
   - **Fix:** On macOS, the utility validates TCP port 7000 reachability and automatically publishes a local Bonjour service record (`dns-sd -P`) if native mDNS broadcasts lapse.

3. **Network ADB Port 5555 Disabled on Boot (Fire OS 8.1.8.5+)**
   - **Symptom:** Remote ADB automations (such as Home Assistant or background management tools) lose connection whenever the TV restarts.
   - **Cause:** Fire OS resets `Settings.Global.ADB_ENABLED` to 0 during system initialization.
   - **Fix:** The optional companion APK (`Fire TV ADB Fixer`) listens for `BOOT_COMPLETED` and restores network ADB availability for opted-in users.

---

## Architecture

- **Host Sweeper (`macos/`, `windows/`):**
  - Runs in the background on a local computer.
  - Automatically reconnects over the local network via ADB (`<tv-ip>:5555`).
  - Purges dead player tasks without interfering with active streaming sessions.
  - Provides dynamic mDNS proxying on macOS.
- **Companion APK (`companion-apk/`):**
  - Standalone Android package (`io.github.vladislavekimtcov.firetvfixer`).
  - Requires `WRITE_SECURE_SETTINGS` (granted once via ADB).
  - Contains no network permissions and has zero runtime overhead.

---

## Quick Start

### macOS Installation

Prerequisite: Android platform tools (`brew install android-platform-tools`).

1. Enable **Developer Options > ADB debugging** on your Fire TV.
2. Allow USB/network debugging when prompted on screen.
3. Install the background agent:
   ```bash
   ./macos/install.sh --tv <tv-ip>:5555
   ```
4. Verify status:
   ```bash
   ./macos/install.sh --status
   ```
To uninstall:
```bash
./macos/install.sh --undo
```

### Windows Installation

Run from an elevated Administrator PowerShell prompt:

```powershell
powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Tv <tv-ip>:5555
```

To check status or uninstall:
```powershell
powershell -ExecutionPolicy Bypass -File windows\status.ps1
powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Undo
```

### Companion APK Installation (Optional, for Fire OS 8)

If your Fire TV disables network ADB across reboots:

```bash
cd companion-apk
ADB_SERIAL=<tv-ip>:5555 ./install.sh
```

---

## Security & Privacy Considerations

- **Opt-in Marker:** The companion APK only re-enables ADB if the filesystem marker file (`keep-adb-on`) is present in its external media storage.
- **Time Window:** The companion receiver only operates during the initial 120 seconds following a device boot; manual changes made in Developer Options thereafter remain untouched.
- **Network ADB Exposure:** Keeping port 5555 active allows network-level access for devices authorized via ADB keys. Run only on trusted private local networks.

---

## Credits & dumbtv Inspiration

This tool originated from diagnostics and pull request [#223](https://github.com/humblemuzzu/dumbtv/pull/223) contributed to the [dumbtv](https://github.com/humblemuzzu/dumbtv) project. While `dumbtv` focuses on lean application launchers and debloating without long-running daemons, **Fire TV AirPlay Fixer** is distributed as a completely standalone solution. It works on stock, unmodified Fire TV devices as well as customized setups without requiring any custom launcher or system modifications.

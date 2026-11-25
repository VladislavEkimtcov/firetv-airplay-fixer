package io.github.vladislavekimtcov.firetvfixer;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Log;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

/**
 * Keeps network ADB (port 5555) usable across reboots on Amazon Fire TV devices.
 *
 * Background:
 * On Fire OS 8.1.8.5+ (and certain Fire OS 7 builds), the system boot sequence sets
 * Settings.Global.ADB_ENABLED to 0, closing port 5555 even if "ADB debugging" is
 * enabled in Developer Options. This cuts off remote management, sweeper scripts,
 * and Home Assistant integrations until manually toggled in Developer Options.
 *
 * Sequence:
 * 1. At BOOT_COMPLETED, checks ADB status. If ADB is enabled, cycles it off and on
 *    to reopen port 5555. If ADB was reset to 0, re-enables it if opted in.
 * 2. Schedules exact alarms at +45s and +120s to ensure late-boot system overrides
 *    do not disable ADB again.
 *
 * Security:
 * - Only acts if the opt-in marker file (`keep-adb-on`) exists.
 * - Only runs during the first 2 minutes following boot. Manual toggles in Developer
 *   Options after that stick until the next reboot.
 * - Logs all actions to /sdcard/Android/media/io.github.vladislavekimtcov.firetvfixer/fixer.log.
 */
final class Fix {
    static final String TAG = "FireTvFixer";
    static final String MARKER = "keep-adb-on";
    static final String ACTION_RECHECK = "io.github.vladislavekimtcov.firetvfixer.action.RECHECK";
    private static final long[] RECHECK_MS = {45_000, 120_000};
    private static final long OFF_MS = 1500;

    private Fix() {}

    /** Fired at BOOT_COMPLETED. */
    static void onBoot(Context c) {
        reviveAdb(c, "boot", true);
        AlarmManager alarms = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
        for (int i = 0; i < RECHECK_MS.length; i++) {
            Intent intent = new Intent(ACTION_RECHECK).setClass(c, CheckReceiver.class);
            PendingIntent pi = PendingIntent.getBroadcast(c, i, intent, PendingIntent.FLAG_UPDATE_CURRENT);
            alarms.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + RECHECK_MS[i], pi);
        }
    }

    /**
     * @param toggleIfOn cycle ADB off and on even if currently reported as on.
     */
    static void reviveAdb(Context c, String why, boolean toggleIfOn) {
        boolean granted = c.checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS)
                == PackageManager.PERMISSION_GRANTED;
        int enabled = Settings.Global.getInt(c.getContentResolver(), Settings.Global.ADB_ENABLED, -1);
        boolean optedIn = marker(c).isFile();
        note(c, why + ": granted=" + granted + " adb_enabled=" + enabled + " keep-adb-on=" + optedIn
                + " persist.sys.adb.enable=" + prop("persist.sys.adb.enable")
                + " tcp.port=" + prop("service.adb.tcp.port")
                + " uptime=" + SystemClock.elapsedRealtime() / 1000 + "s");

        if (!granted) {
            note(c, why + ": WRITE_SECURE_SETTINGS not granted. Run: adb shell pm grant io.github.vladislavekimtcov.firetvfixer android.permission.WRITE_SECURE_SETTINGS");
            return;
        }

        if (enabled != 1) {
            if (!optedIn) {
                note(c, why + ": ADB is off and keep-adb-on marker is absent; leaving ADB off");
                return;
            }
            Settings.Global.putInt(c.getContentResolver(), Settings.Global.ADB_ENABLED, 1);
            SystemClock.sleep(1500);
            note(c, why + ": ADB was disabled at boot; re-enabled. tcp.port=" + prop("service.adb.tcp.port"));
            return;
        }

        if (!toggleIfOn) return;

        try {
            Settings.Global.putInt(c.getContentResolver(), Settings.Global.ADB_ENABLED, 0);
            SystemClock.sleep(OFF_MS);
        } finally {
            Settings.Global.putInt(c.getContentResolver(), Settings.Global.ADB_ENABLED, 1);
        }
        SystemClock.sleep(1500);
        note(c, why + ": cycled ADB off and on; port 5555 reopened. tcp.port=" + prop("service.adb.tcp.port"));
    }

    private static File mediaDir(Context c) {
        File[] dirs = c.getExternalMediaDirs();
        return dirs.length == 0 ? null : dirs[0];
    }

    private static File marker(Context c) {
        File dir = mediaDir(c);
        return new File(dir == null ? c.getFilesDir() : dir, MARKER);
    }

    private static String prop(String key) {
        try {
            Class<?> sp = Class.forName("android.os.SystemProperties");
            return (String) sp.getMethod("get", String.class).invoke(null, key);
        } catch (ReflectiveOperationException | RuntimeException e) {
            return "?";
        }
    }

    private static void note(Context c, String msg) {
        Log.i(TAG, msg);
        try {
            File dir = mediaDir(c);
            if (dir == null || (!dir.isDirectory() && !dir.mkdirs())) return;
            String line = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(new Date())
                    + " " + msg + "\n";
            try (FileOutputStream out = new FileOutputStream(new File(dir, "fixer.log"), true)) {
                out.write(line.getBytes(StandardCharsets.UTF_8));
            }
        } catch (Exception e) {
            Log.w(TAG, "could not write fixer.log", e);
        }
    }
}

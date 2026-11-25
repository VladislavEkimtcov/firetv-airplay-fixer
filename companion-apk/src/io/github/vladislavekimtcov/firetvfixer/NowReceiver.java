package io.github.vladislavekimtcov.firetvfixer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * On-demand diagnostic hook protected by android.permission.DUMP:
 *   adb shell am broadcast -n io.github.vladislavekimtcov.firetvfixer/.NowReceiver
 * Only adb shell holds DUMP, regular apps cannot trigger this.
 */
public final class NowReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Fix.reviveAdb(context, "on request", true);
    }
}

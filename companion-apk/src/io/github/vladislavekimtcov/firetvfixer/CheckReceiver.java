package io.github.vladislavekimtcov.firetvfixer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Scheduled re-checks after boot. Not exported: internal alarms only. */
public final class CheckReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Fix.ACTION_RECHECK.equals(intent.getAction())) return;
        Fix.reviveAdb(context, "recheck", false);
    }
}

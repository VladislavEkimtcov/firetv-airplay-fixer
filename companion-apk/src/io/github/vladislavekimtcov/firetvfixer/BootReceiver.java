package io.github.vladislavekimtcov.firetvfixer;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Handles BOOT_COMPLETED. The work runs directly inside onReceive on purpose: Android keeps
 * a process alive while running a broadcast receiver, avoiding the risk of process death
 * before the off/on cycle completes.
 */
public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        Fix.onBoot(context);
    }
}

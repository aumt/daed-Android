package io.github.aumt.daedtile;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.service.quicksettings.TileService;

/**
 * Registers the Quick-Settings tile. A system-installed tile app is rarely
 * launched by the user, so without an explicit request the tile never enters
 * SystemUI's tile set and cannot be added from the Quick-Settings edit list.
 * Requesting listening state on boot (and on package update) makes the tile
 * available.
 */
public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        try {
            TileService.requestListeningState(context,
                    new ComponentName(context, DaedTileService.class));
        } catch (Exception ignored) {
        }
    }
}

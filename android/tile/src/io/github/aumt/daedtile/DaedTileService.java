package io.github.aumt.daedtile;

import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * Quick Settings tile for daed:
 *   tap -> toggle the dae proxy on/off (the daed web UI keeps running)
 *
 * Long-press has no onLongClick hook in TileService: Android shows the
 * system's tile-detail sheet instead, which exposes a gear entry into the
 * QS_TILE_PREFERENCES activity (MainActivity) that opens the web UI.
 *
 * Installed as a system app from the Magisk module. The first tap prompts the
 * Magisk superuser grant dialog; allow it once and the tile works silently.
 */
public class DaedTileService extends TileService {

    private static final long RECHECK_DELAY_MS = 1500;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private boolean mBusy;

    @Override
    public void onStartListening() {
        refresh();
    }

    @Override
    public void onTileAdded() {
        refresh();
    }

    @Override
    public void onClick() {
        if (mBusy) {
            return;
        }
        mBusy = true;
        setTileState(Tile.STATE_UNAVAILABLE, R.string.tile_busy);
        // Root commands can block on the Magisk superuser dialog on first use,
        // so run off the main thread and post the result back.
        new Thread(() -> {
            final boolean ok;
            if (!Daedctl.isDaedRunning()) {
                ok = Daedctl.startDaemon();
            } else if (Daedctl.isProxyRunning()) {
                ok = Daedctl.stopProxy();
            } else {
                ok = Daedctl.startProxy();
            }
            mHandler.post(() -> {
                mBusy = false;
                if (ok) {
                    refresh(); // optimistic
                    // The proxy (or its marker) settles shortly after the
                    // signal lands; re-check once.
                    mHandler.postDelayed(this::refresh, RECHECK_DELAY_MS);
                } else {
                    setTileState(Tile.STATE_INACTIVE, R.string.tile_failed);
                }
            });
        }, "DaedToggle").start();
    }

    private void refresh() {
        setTileState(Daedctl.isProxyRunning() ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE,
                R.string.tile_label);
    }

    private void setTileState(int state, int labelRes) {
        Tile tile = getQsTile();
        if (tile == null) {
            return;
        }
        tile.setState(state);
        tile.setLabel(getString(labelRes));
        String cd;
        switch (state) {
            case Tile.STATE_ACTIVE:
                cd = getString(R.string.tile_running);
                break;
            case Tile.STATE_INACTIVE:
                cd = getString(R.string.tile_stopped);
                break;
            default:
                cd = getString(R.string.tile_busy);
                break;
        }
        tile.setContentDescription(cd);
        tile.updateTile();
    }
}

package io.github.aumt.daedtile;

import android.os.Handler;
import android.os.Looper;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * Quick Settings tile for daed:
 *   tap -> switch the daed daemon on/off
 *            on : start the daemon (dae proxy + web UI). A fresh start
 *                 re-detects the network interfaces, which repairs the
 *                 "panel healthy, proxy silently dead" state that appears
 *                 after Android re-creates the mobile-data interface.
 *            off: stop the daemon (proxy and web UI) and remember it, so
 *                 service.sh does not autostart it on the next boot.
 *          Special case: daemon already running but the proxy was stopped
 *          from the web UI -> tap starts the proxy again (SIGUSR2) instead of
 *          pointlessly restarting the daemon.
 *
 * The tile is lit while dae is proxying.
 *
 * Long-press has no onLongClick hook in TileService: Android shows the
 * system's tile-detail sheet instead, which exposes a gear entry into the
 * QS_TILE_PREFERENCES activity (MainActivity) that opens the web UI.
 *
 * Installed as a system app from the Magisk module. The first tap prompts the
 * Magisk superuser grant dialog; allow it once and the tile works silently.
 */
public class DaedTileService extends TileService {

    /**
     * Starting the daemon takes a few seconds (veth + eBPF + routing + web
     * UI), so re-check the state a bit later than for a plain signal toggle.
     */
    private static final long RECHECK_DELAY_MS = 4000;

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
        // and daed-start waits for the web UI, so run off the main thread and
        // post the result back.
        new Thread(() -> {
            final boolean ok;
            if (!Daedctl.isDaemonRunning()) {
                // Switched off (or died): start the whole daemon.
                ok = Daedctl.startDaemon();
            } else if (Daedctl.isProxyRunning()) {
                // Running: switch the daemon off.
                ok = Daedctl.stopDaemon();
            } else {
                // Daemon up but the proxy was stopped in the web UI.
                ok = Daedctl.startProxy();
            }
            mHandler.post(() -> {
                mBusy = false;
                if (ok) {
                    refresh(); // optimistic
                    // The proxy state (or the process) settles shortly after
                    // the command lands; re-check once.
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

package io.github.aumt.daedtile;

import android.util.Log;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * Root commands that start / stop / query the daed daemon and the dae proxy.
 *
 * The tile is a daemon switch: tap on = daed running (dae proxy up, web UI
 * reachable), tap off = the whole daemon is stopped. That is deliberate.
 * Android re-creates the mobile-data interface (rmnet_data4 -> rmnet_data3/5)
 * and moves the default route with it; dae resolves its WAN/LAN interface set
 * once per control-plane build, so its tc/eBPF hooks end up on interfaces
 * nothing flows through any more and the proxy silently dies while the panel
 * still looks healthy. A fresh daemon start re-detects the interfaces and
 * repairs exactly that.
 *
 * A proxy-only toggle can only go through a reload, which does not reliably
 * rebind, cuts in-flight connections, and can wedge the datapath
 * ("handleConn: failed to retrieve target info ... context canceled"). It is
 * therefore still available, but only for the state it is actually good for:
 * daemon up and the proxy stopped from the web UI (see {@link #isProxyRunning}
 * and {@link #startProxy()}).
 *
 * The work is delegated to the Magisk module's shell helpers so that boot
 * (service.sh), the tile and daed-watchdog share one implementation:
 *   daed-start -- start detached, wait for the web UI, ensure the proxy runs,
 *                 report whether the WAN binding matches the default routes
 *   daed-stop  -- SIGTERM (graceful, daed detaches its BPF hooks itself), then
 *                 SIGKILL as a fallback, and write the "switched off" marker
 *
 * daed mirrors its DB "running" flag into STOP_MARKER, so the marker doubles
 * as "proxy stopped" for the daemon-up case and as "daemon switched off" for
 * service.sh / daed-watchdog while the daemon is down.
 */
final class Daedctl {

    private static final String TAG = "Daedctl";

    /** Absolute path of the daed binary inside the Magisk module. */
    static final String DAED_BIN = "/data/adb/modules/daed/system/bin/daed";
    static final String DAED_DIR = "/data/adb/daed";
    static final String DAED_LOG = DAED_DIR + "/daed.log";
    /** Module helpers, shared with service.sh and daed-watchdog. */
    static final String DAED_START = "/data/adb/modules/daed/system/bin/daed-start";
    static final String DAED_STOP = "/data/adb/modules/daed/system/bin/daed-stop";
    /** Marker file: present while the dae proxy is stopped. */
    static final String STOP_MARKER = DAED_DIR + "/.dae-stopped";
    /** daed binds 0.0.0.0:2023; 127.0.0.1 is the reliable on-device URL. */
    static final String WEBUI_URL = "http://127.0.0.1:2023";

    /** daed-start waits for the web UI (up to ~40s); give it room. */
    private static final long START_TIMEOUT_S = 60;
    private static final long DEFAULT_TIMEOUT_S = 30;

    private Daedctl() {
    }

    /** True when the daed process (and thus the web UI) is running. */
    static boolean isDaemonRunning() {
        // -x (exact process-name match) instead of -f: this device's toybox
        // pgrep matches -f patterns as a substring, so the classic '[d]aed'
        // self-exclusion trick fails and the pattern also hits the calling
        // shell process. -x matches only the daed process name.
        return exec("pgrep -x daed >/dev/null 2>&1").code == 0;
    }

    /** True when dae is proxying: the daemon is up and the proxy is not stopped. */
    static boolean isProxyRunning() {
        return isDaemonRunning()
                && exec("test ! -f " + STOP_MARKER).code == 0;
    }

    /** Starts the daemon; also restores the proxy state kept in the database. */
    static boolean startDaemon() {
        return exec(DAED_START, START_TIMEOUT_S).code == 0;
    }

    /** Stops the daemon (proxy + web UI) and marks it as switched off. */
    static boolean stopDaemon() {
        return exec(DAED_STOP).code == 0;
    }

    /** Starts the dae proxy (SIGUSR2); keeps the daed web UI up. */
    static boolean startProxy() {
        // Numeric signals: this device's toybox pkill rejects signal NAMES
        // (-USR2 -> "pkill: bad -U 'SR2'"), so use SIGUSR1=10 / SIGUSR2=12.
        return exec("pkill -12 -x daed").code == 0;
    }

    /** Stops the dae proxy (SIGUSR1); keeps the daed web UI up. */
    static boolean stopProxy() {
        return exec("pkill -10 -x daed").code == 0;
    }

    static final class Result {
        final int code;
        final String output;

        Result(int code, String output) {
            this.code = code;
            this.output = output;
        }
    }

    private static Result exec(String cmd) {
        return exec(cmd, DEFAULT_TIMEOUT_S);
    }

    private static Result exec(String cmd, long timeoutSeconds) {
        Process p = null;
        try {
            p = new ProcessBuilder("su", "-c", cmd)
                    .redirectErrorStream(true)
                    .start();
            String out = readAll(p.getInputStream());
            if (!p.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
                // Give Magisk's superuser grant dialog time on first use, but
                // do not pretend a timeout was a success.
                p.destroyForcibly();
                Log.w(TAG, "timed out after " + timeoutSeconds + "s: " + cmd);
                return new Result(-1, out);
            }
            return new Result(p.exitValue(), out);
        } catch (IOException | InterruptedException e) {
            Log.e(TAG, "su failed for: " + cmd, e);
            return new Result(-1, String.valueOf(e));
        } finally {
            if (p != null) {
                p.destroy();
            }
        }
    }

    private static String readAll(InputStream in) throws IOException {
        BufferedReader r = new BufferedReader(
                new InputStreamReader(in, StandardCharsets.UTF_8));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = r.readLine()) != null) {
            sb.append(line).append('\n');
        }
        return sb.toString();
    }
}

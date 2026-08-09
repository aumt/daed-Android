package io.github.aumt.daedtile;

import android.util.Log;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * Root commands that start / stop / query dae and daed on the device.
 *
 * "Proxy on/off" only toggles the dae proxy: the daed process (which also
 * serves the web UI on :2023) keeps running, so the panel stays reachable
 * while the proxy is off. dae-wing is patched for Android to handle
 * SIGUSR1 (stop proxy) and SIGUSR2 (start proxy) by reusing the exact code
 * path of the web UI's start/stop buttons. Signals are sent with numeric
 * codes (-10/-12) because toybox pkill rejects signal names, and the daed
 * process is addressed by exact name (-x daed) because toybox's -f is a
 * substring match that would otherwise signal the calling shell itself and
 * leave a non-zero exit code (see isDaedRunning). The state is persisted by
 * daed in its DB "running" flag (honoured again at boot by service.sh) and
 * mirrored to a marker file that this class reads cheaply.
 */
final class Daedctl {

    private static final String TAG = "Daedctl";

    /** Absolute path of the daed binary inside the Magisk module. */
    static final String DAED_BIN = "/data/adb/modules/daed/system/bin/daed";
    static final String DAED_DIR = "/data/adb/daed";
    static final String DAED_LOG = DAED_DIR + "/daed.log";
    /** Marker file: present when the dae proxy is stopped (web UI still up). */
    static final String STOP_MARKER = DAED_DIR + "/.dae-stopped";
    /** daed binds 0.0.0.0:2023; 127.0.0.1 is the reliable on-device URL. */
    static final String WEBUI_URL = "http://127.0.0.1:2023";

    private Daedctl() {
    }

    /** True when the daed process (and thus the web UI) is running. */
    static boolean isDaedRunning() {
        // -x (exact process-name match) instead of -f: this device's toybox
        // pgrep matches -f patterns as a substring, so the classic '[d]aed'
        // self-exclusion trick fails and the pattern also hits the calling
        // shell process. -x matches only the daed process name.
        return exec("pgrep -x daed >/dev/null 2>&1").code == 0;
    }

    /** True when the dae proxy is actively running. */
    static boolean isProxyRunning() {
        return isDaedRunning()
                && exec("test ! -f " + STOP_MARKER).code == 0;
    }

    /** Starts the daed process (also restores the last proxy state). */
    static boolean startDaemon() {
        return exec("nohup '" + DAED_BIN + "' run -c " + DAED_DIR
                + " >> " + DAED_LOG + " 2>&1 &").code == 0;
    }

    /** Stops the dae proxy (SIGUSR1); keeps the daed web UI up. */
    static boolean stopProxy() {
        // Numeric signals: this device's toybox pkill rejects signal NAMES
        // (-USR1 -> "pkill: bad -U 'SR1'"), so use SIGUSR1=10 / SIGUSR2=12.
        // -f '[d]aed run' would self-match (substring match) and signal the
        // calling shell -> non-zero exit even though the proxy switched; -x
        // pins the daed process name so the command returns 0 on success.
        return exec("pkill -10 -x daed").code == 0;
    }

    /** Starts the dae proxy (SIGUSR2); keeps the daed web UI up. */
    static boolean startProxy() {
        return exec("pkill -12 -x daed").code == 0;
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
        Process p = null;
        try {
            p = new ProcessBuilder("su", "-c", cmd)
                    .redirectErrorStream(true)
                    .start();
            String out = readAll(p.getInputStream());
            if (!p.waitFor(30, TimeUnit.SECONDS)) {
                // Give Magisk's superuser grant dialog time on first use.
                p.destroyForcibly();
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

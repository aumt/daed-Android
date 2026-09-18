#!/system/bin/sh

# Magisk late_start service: auto-start daed on boot

# Fallback MODPATH for manual execution
MODPATH=${MODPATH:-/data/adb/modules/daed}
LOG_FILE="/data/adb/daed/daed.log"
GEO_DIR="/data/adb/daed"

# Geo data sources: the official v2fly releases, whose v2ray format dae-core
# decodes. Same sources as scripts/fetch-geo-data.sh, which stages the
# compressed copy bundled in the module.
GEOSITE_URL="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
GEOIP_URL="https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"

# The network is often not up yet when this runs, so a failed fetch is expected
# rather than exceptional: retry across a few minutes before giving up.
DOWNLOAD_ATTEMPTS=4
RETRY_DELAY=60

# --- Geo data -------------------------------------------------------------
#
# dae reads geosite.dat / geoip.dat for geosite:/geoip: routing rules, and
# looks for them in the config dir (-c /data/adb/daed). dae-wing passes that
# dir as externGeoDataDirs and dae-core searches it ahead of everything else,
# so a copy under the module directory would never be found.
#
# The module ships a gzip-compressed copy, expanded at install time by
# customize.sh. Everything below is the backstop for the cases that misses --
# a recovery flash, a config dir that was not writable at install time, or a
# user who deleted the files.
#
# All of it runs detached (see the --geo-refresh dispatch below), because the
# network fallback can wait minutes for WiFi and must not hold up daed.

# gunzip_to <src> <dst>: expand <src> into <dst>, trying the tools Android and
# Magisk actually provide. Leaves no partial file behind on failure.
#
# Helper variables carry a leading underscore: POSIX sh has no `local`, so a
# helper assigning a plain name silently overwrites that variable in its
# caller. `fetch_to` below used to do exactly that with `dst` -- the caller's
# loop variable -- and every retry then appended another ".tmp" to the
# destination, so no download could ever land.
gunzip_to() {
    _src="$1"
    _dst="$2"
    if command -v busybox >/dev/null 2>&1 && busybox gzip -dc "$_src" > "$_dst" 2>/dev/null && [ -s "$_dst" ]; then
        return 0
    fi
    if command -v gzip >/dev/null 2>&1 && gzip -dc "$_src" > "$_dst" 2>/dev/null && [ -s "$_dst" ]; then
        return 0
    fi
    rm -f "$_dst"
    return 1
}

# expand_bundled_geo_data: expand the module's geo/*.gz into GEO_DIR.
#
# Re-expands only when this build carries different data than what is already
# installed, so a reflash of the same build is a no-op instead of 25MB of
# pointless work -- and a copy the user refreshed by hand survives it.
expand_bundled_geo_data() {
    geo_src="$MODPATH/geo"
    [ -d "$geo_src" ] || return 0

    # Skip only when the marker matches *and* both files are present: a marker
    # without its data (a file deleted by hand, or an expansion torn by a
    # reboot) must be repaired from the bundled copy, not left to the network
    # fallback below.
    bundled_ver=$(cat "$geo_src/VERSION" 2>/dev/null)
    installed_ver=$(cat "$GEO_DIR/.geo-bundled-version" 2>/dev/null)
    if [ -n "$bundled_ver" ] && [ "$bundled_ver" = "$installed_ver" ] &&
        [ -s "$GEO_DIR/geosite.dat" ] && [ -s "$GEO_DIR/geoip.dat" ]; then
        return 0
    fi

    ok=1
    for name in geosite.dat geoip.dat; do
        src="$geo_src/$name.gz"
        if [ ! -f "$src" ]; then
            ok=0
            continue
        fi
        if gunzip_to "$src" "$GEO_DIR/$name.tmp"; then
            mv "$GEO_DIR/$name.tmp" "$GEO_DIR/$name"
            echo "$(date): expanded bundled $name (build ${bundled_ver:-unknown})" >> "$LOG_FILE"
        else
            ok=0
            echo "$(date): WARN: could not expand bundled $name" >> "$LOG_FILE"
        fi
    done

    # Record the version only when both files landed: a partial expansion has
    # to be retried, not remembered as complete.
    [ "$ok" = "1" ] && printf '%s\n' "$bundled_ver" > "$GEO_DIR/.geo-bundled-version"
    return 0
}

# fetch_to <url> <dst>: download <url> into <dst>.
#
# The output path is passed as an option (-o / -O) rather than as a trailing
# argument: curl and wget treat every bare argument as a URL, so the previous
# `curl <url> <path>` form made the path a second URL and failed with
# "URL malformat" -- writing nothing, while dumping the payload to stdout.
#
# Underscored names for the same reason gunzip_to above explains.
fetch_to() {
    _url="$1"
    _out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 15 --max-time 180 -o "$_out" "$_url"
    elif command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; then
        busybox wget -q -O "$_out" "$_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$_out" "$_url"
    else
        return 127
    fi
}

# ensure_geo_file <name> <url>: download <name> if it is not already usable.
ensure_geo_file() {
    name="$1"
    url="$2"
    dst="$GEO_DIR/$name"
    [ -s "$dst" ] && return 0

    attempt=1
    while [ "$attempt" -le "$DOWNLOAD_ATTEMPTS" ]; do
        echo "$(date): downloading $name (attempt $attempt/$DOWNLOAD_ATTEMPTS) ..." >> "$LOG_FILE"
        fetch_to "$url" "$dst.tmp" 2>>"$LOG_FILE"
        rc=$?
        if [ "$rc" -eq 0 ] && [ -s "$dst.tmp" ]; then
            mv "$dst.tmp" "$dst"
            echo "$(date): downloaded $name ($(wc -c < "$dst" | tr -d ' ') bytes)" >> "$LOG_FILE"
            return 0
        fi
        rm -f "$dst.tmp"
        # No downloader on the device at all: retrying cannot help.
        if [ "$rc" -eq 127 ]; then
            echo "$(date): WARN: no curl/wget available; cannot download $name" >> "$LOG_FILE"
            return 1
        fi
        # Sleep before the next try: at boot this is usually just waiting for
        # WiFi to associate.
        [ "$attempt" -lt "$DOWNLOAD_ATTEMPTS" ] && sleep "$RETRY_DELAY"
        attempt=$((attempt + 1))
    done

    echo "$(date): WARN: failed to download $name after $DOWNLOAD_ATTEMPTS attempts; place it at $dst manually if geosite/geoip rules fail" >> "$LOG_FILE"
    return 1
}

# ensure_geo_data: bring the geo files up to date, detached from the boot path.
ensure_geo_data() {
    mkdir -p "$GEO_DIR" 2>/dev/null || return 0

    # Serialize: a run waiting out a slow network must not overlap the next
    # one. A lock left behind by a killed run is reclaimed after 30 minutes.
    lock="$GEO_DIR/.geo-lock"
    if ! mkdir "$lock" 2>/dev/null; then
        if [ -n "$(find "$lock" -mmin +30 2>/dev/null)" ]; then
            rm -rf "$lock"
            mkdir "$lock" 2>/dev/null || return 0
        else
            return 0
        fi
    fi
    trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

    expand_bundled_geo_data
    ensure_geo_file geosite.dat "$GEOSITE_URL"
    ensure_geo_file geoip.dat "$GEOIP_URL"
}

# Detached geo-refresh mode: re-executed by the boot path below so the refresh
# runs in its own process, surviving this script and never blocking the boot.
if [ "$1" = "--geo-refresh" ]; then
    ensure_geo_data
    exit 0
fi

# --- Boot path ------------------------------------------------------------

# Wait for system/network to be ready
sleep 5

# Register the Quick-Settings tile app if it isn't already, so the dae tile
# shows up without a manual `pm install`. customize.sh already installs it
# during a Magisk-app flash; this covers recovery flashes and ROMs (e.g.
# ColorOS/OPPO) that ignore a Magisk-injected system/app APK until it is
# explicitly installed. Idempotent: if the package is registered, no-op.
TILE_PKG="io.github.aumt.daedtile"
TILE_APK="$MODPATH/system/app/DaedTile/DaedTile.apk"
if [ -f "$TILE_APK" ] && command -v pm >/dev/null 2>&1; then
    # Wait (bounded) for PackageManager to be up before querying it.
    i=0
    while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 120 ]; do
        sleep 2
        i=$((i+2))
    done
    if ! pm path "$TILE_PKG" >/dev/null 2>&1; then
        if pm install -r --user 0 "$TILE_APK" >/dev/null 2>&1; then
            echo "$(date): installed Quick-Settings tile app" >> "$LOG_FILE"
        else
            echo "$(date): WARN: could not install Quick-Settings tile app; run: pm install -r $TILE_APK" >> "$LOG_FILE"
        fi
    fi
fi

# Kernel version check: dae requires >= 5.17 (bpf_loop)
KMAJOR=$(uname -r | cut -d. -f1)
KMINOR=$(uname -r | cut -d. -f2)
if [ "$KMAJOR" -lt 5 ] 2>/dev/null || { [ "$KMAJOR" -eq 5 ] && [ "$KMINOR" -lt 17 ]; } 2>/dev/null; then
    echo "$(date): FATAL: kernel $(uname -r) is too old; dae requires >= 5.17 (bpf_loop support). Aborting." > "$LOG_FILE"
    exit 1
fi

# Locate the daed binary: prefer MODPATH, fall back to PATH
DAED_BIN="$MODPATH/system/bin/daed"
if [ ! -x "$DAED_BIN" ]; then
    DAED_BIN="daed"
fi

# Start the daemon through the module helper so boot, the Quick-Settings tile
# and daed-watchdog share one implementation. The helper starts daed detached,
# waits for the web UI and reports whether dae's WAN binding matches the
# interfaces that actually carry a default route.
#
# The marker left behind by the tile ("switched off") wins over the autostart:
# the user asked for the daemon to stay down.
DAED_HELPER_DIR="$MODPATH/system/bin"
if [ -f "/data/adb/daed/.dae-stopped" ]; then
    echo "$(date): daed switched off by the user (tile); not autostarting" >> "$LOG_FILE"
elif [ -x "$DAED_HELPER_DIR/daed-start" ]; then
    sh "$DAED_HELPER_DIR/daed-start" >> "$LOG_FILE" 2>&1
else
    # Fallback for a module zip that predates the helper scripts.
    nohup "$DAED_BIN" run -c /data/adb/daed >> "$LOG_FILE" 2>&1 &
fi

# Self-heal loop: repairs a dead daemon, and the stale-WAN-binding failure that
# kills the proxy silently (Android re-creates the mobile-data interface as
# rmnet_data<N>, dae keeps its tc/eBPF hooks on the old one, app traffic is no
# longer captured while the web UI still looks healthy). It no-ops while the
# daemon is switched off, so start it unconditionally.
if [ -x "$DAED_HELPER_DIR/daed-watchdog" ] && ! pgrep -f "daed-watchdog" >/dev/null 2>&1; then
    setsid "$DAED_HELPER_DIR/daed-watchdog" >> "$LOG_FILE" 2>&1 < /dev/null &
fi

# Repair/refresh the geo data in a detached process.
SELF="$MODPATH/service.sh"
if [ -f "$SELF" ]; then
    nohup sh "$SELF" --geo-refresh >> "$LOG_FILE" 2>&1 &
fi

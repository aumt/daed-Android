#!/system/bin/sh

# Magisk late_start service: auto-start daed on boot

# Fallback MODPATH for manual execution
MODPATH=${MODPATH:-/data/adb/modules/daed}
LOG_FILE="/data/adb/daed/daed.log"

# Wait for system/network to be ready
sleep 5

# Prevent duplicate instances
if pgrep -f 'daed run' >/dev/null 2>&1 || pidof daed >/dev/null 2>&1; then
    exit 0
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

# Ensure geosite/geoip data exists before starting dae.
#
# dae loads these files (geosite.dat / geoip.dat) for geosite:/geoip: routing
# rules, and on Android there is no bundled copy — the module does not ship
# them. dae looks them up in the config dir (-c /data/adb/daed), so download
# them there once if missing. This is best-effort: if the network is not up at
# boot, daed still starts and the data is fetched on a later boot (or can be
# placed manually at /data/adb/daed/geosite.dat and geoip.dat).
# Sources are the official v2fly releases, whose v2ray format dae-core decodes.
download_geo_data() {
    name="$1"
    url="$2"
    dst="/data/adb/daed/$name"
    [ -f "$dst" ] && return 0
    dl=""
    if command -v curl >/dev/null 2>&1; then
        dl="curl -fsSL --connect-timeout 15 --max-time 180"
    elif command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; then
        dl="busybox wget -q -O"
    else
        echo "$(date): WARN: no curl/wget available; cannot download $name" >> "$LOG_FILE"
        return 1
    fi
    echo "$(date): downloading $name ..." >> "$LOG_FILE"
    if $dl "$url" "$dst.tmp" 2>>"$LOG_FILE"; then
        mv "$dst.tmp" "$dst"
        echo "$(date): downloaded $name ($(wc -c < "$dst") bytes)" >> "$LOG_FILE"
    else
        rm -f "$dst.tmp"
        echo "$(date): WARN: failed to download $name; place it at $dst manually if geosite/geoip rules fail" >> "$LOG_FILE"
        return 1
    fi
}
download_geo_data geosite.dat "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
download_geo_data geoip.dat "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"

# Launch daed in background with logging
nohup "$DAED_BIN" run -c /data/adb/daed >> "$LOG_FILE" 2>&1 &

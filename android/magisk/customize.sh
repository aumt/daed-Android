#!/system/bin/sh

# Magisk installation script for daed module

ui_print "==============================="
ui_print "  daed Magisk Module"
ui_print "==============================="
ui_print "Installing daed for Android..."

# Kernel version check: dae requires >= 5.17 (bpf_loop)
KMAJOR=$(uname -r | cut -d. -f1)
KMINOR=$(uname -r | cut -d. -f2)
if [ "$KMAJOR" -lt 5 ] 2>/dev/null || { [ "$KMAJOR" -eq 5 ] && [ "$KMINOR" -lt 17 ]; } 2>/dev/null; then
    ui_print ""
    ui_print "!!! WARNING !!!"
    ui_print "Your kernel version is $(uname -r)"
    ui_print "dae requires kernel >= 5.17 (bpf_loop support)"
    ui_print "daed will NOT start on this device!"
    ui_print "Logs will be written to /data/adb/daed/daed.log"
    ui_print "!!! WARNING !!!"
else
    ui_print "Kernel $(uname -r) - OK (>= 5.17)"
fi

# Set executable permissions for binaries
# Magisk overlays system/ onto /system automatically, no manual copy needed
set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755

# Expand the bundled geo data into the config directory so a fresh install has
# working geosite:/geoip: rules right away, instead of depending on the
# boot-time download in service.sh (which runs in the late_start stage, often
# before WiFi associates).
#
# The files must land in /data/adb/daed: dae-wing passes the config dir as
# externGeoDataDirs and dae-core searches it ahead of everything else, so a
# copy under the module directory would never be found.
#
# Best-effort by design -- if the bundled data is missing or no gzip is
# available, service.sh fetches it on boot instead. Never fails the install.
#
# Helper variables carry a leading underscore: POSIX sh has no `local`, so a
# helper assigning a plain name silently overwrites that variable in its
# caller. (service.sh's copy of this function and its fetch_to sibling had
# exactly that bug -- see the note there.)
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

install_bundled_geo_data() {
    geo_src="$MODPATH/geo"
    geo_dst="/data/adb/daed"

    [ -d "$geo_src" ] || return 0
    mkdir -p "$geo_dst" 2>/dev/null || {
        ui_print "  geo data skipped (config dir not writable; service.sh retries)"
        return 0
    }

    # Re-expand only when this build carries different data. Besides sparing
    # ~25MB of pointless work on every reflash, the marker keeps a copy the
    # user refreshed by hand from being clobbered by the same build.
    #
    # Both files must also be present: a matching marker over missing data (a
    # file deleted by hand, an expansion torn by a reboot) means this build is
    # the cheapest way to repair it, not a reason to defer to the network.
    bundled_ver=$(cat "$geo_src/VERSION" 2>/dev/null)
    installed_ver=$(cat "$geo_dst/.geo-bundled-version" 2>/dev/null)
    if [ -n "$bundled_ver" ] && [ "$bundled_ver" = "$installed_ver" ] &&
        [ -s "$geo_dst/geosite.dat" ] && [ -s "$geo_dst/geoip.dat" ]; then
        return 0
    fi

    ok=1
    for name in geosite.dat geoip.dat; do
        src="$geo_src/$name.gz"
        if [ ! -f "$src" ]; then
            ok=0
            continue
        fi
        if gunzip_to "$src" "$geo_dst/$name.tmp"; then
            mv "$geo_dst/$name.tmp" "$geo_dst/$name"
        else
            ok=0
        fi
    done

    # Record the version only when both files landed: a partial expansion has
    # to be retried on the next boot, not remembered as complete.
    if [ "$ok" = "1" ]; then
        printf '%s\n' "$bundled_ver" > "$geo_dst/.geo-bundled-version"
        if [ -n "$bundled_ver" ]; then
            ui_print "  geo data installed (version $bundled_ver)"
        else
            ui_print "  geo data installed"
        fi
    else
        ui_print "  geo data deferred (service.sh will fetch it on boot)"
    fi
    return 0
}

install_bundled_geo_data

# Register the Quick-Settings tile app immediately so the dae tile shows up
# without a manual `pm install`. The APK ships under system/app/, which most
# ROMs register on boot, but some ROMs (e.g. ColorOS/OPPO) ignore a
# Magisk-injected system app until it is explicitly installed. When flashing
# from the Magisk app, pm is available right here; under recovery it is not,
# and service.sh retries the install on the next boot. Idempotent.
if command -v pm >/dev/null 2>&1; then
    ui_print "Registering Quick-Settings tile app..."
    if pm install -r --user 0 "$MODPATH/system/app/DaedTile/DaedTile.apk" >/dev/null 2>&1; then
        ui_print "  tile app installed"
    else
        ui_print "  tile app install deferred (service.sh retries on boot)"
    fi
fi

ui_print ""
ui_print "daed installed successfully!"
ui_print ""
ui_print "Quick access:"
ui_print "  Run 'daed-open' to open the web panel"
ui_print "  Panel URL: http://127.0.0.1:2023"
ui_print "  Logs: /data/adb/daed/daed.log"
ui_print ""
ui_print "Quick-Settings tile:"
ui_print "  QS edit (pencil) -> drag 'daed' in"
ui_print "  Tap = start/stop the daed daemon (proxy + web UI)"
ui_print "  Long-press = open web UI"
ui_print ""
ui_print "Installation completed."

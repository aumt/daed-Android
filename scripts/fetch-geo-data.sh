#!/bin/sh
#
# Stage the v2fly geosite/geoip data for bundling into the Android Magisk module.
#
# The module ships a gzip-compressed copy so that a fresh install has working
# geosite:/geoip: routing rules immediately, instead of depending on the
# boot-time download in service.sh (which runs in the late_start stage, often
# before WiFi associates). customize.sh expands this copy into /data/adb/daed/
# at install time -- see android/magisk/README.md.
#
# Usage: sh scripts/fetch-geo-data.sh <version>
#
#   <version>  Build version string. Recorded in geo/VERSION so the device can
#              tell whether its expanded copy is stale without hashing 25MB.

set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "usage: $0 <version>" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
GEO_DIR="$REPO_ROOT/android/magisk/geo"

# Same upstream sources as the boot-time download in service.sh, so the
# bundled data and a later refresh come from an identical format.
GEOSITE_URL="https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat"
GEOIP_URL="https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"

# Minimum plausible size: guards against a captive portal or an error page
# being served with HTTP 200 and staged as "geo data".
MIN_BYTES=1024

mkdir -p "$GEO_DIR"

# stage <url> <name>: download <name>, gzip -9 it to geo/<name>.gz, verify.
stage() {
    url="$1"
    name="$2"
    raw="$GEO_DIR/.$name.raw"
    gz="$GEO_DIR/$name.gz"

    rm -f "$raw" "$gz.tmp"

    echo "  downloading $name ..."
    if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 -o "$raw" "$url"; then
        rm -f "$raw"
        echo "ERROR: failed to download $url" >&2
        return 1
    fi

    raw_size=$(wc -c < "$raw" | tr -d ' ')
    if [ "$raw_size" -lt "$MIN_BYTES" ]; then
        rm -f "$raw"
        echo "ERROR: $url yielded only $raw_size bytes (expected >= $MIN_BYTES)" >&2
        return 1
    fi

    echo "  compressing $name ($raw_size bytes) ..."
    if ! gzip -9 -c "$raw" > "$gz.tmp"; then
        rm -f "$raw" "$gz.tmp"
        echo "ERROR: failed to compress $name" >&2
        return 1
    fi

    # Confirm the archive expands back to exactly the bytes we downloaded. A
    # truncated transfer can still yield a stream gzip accepts, so integrity
    # alone (gzip -t) is not enough to prove the data is complete.
    if ! gzip -dc "$gz.tmp" | cmp -s - "$raw"; then
        rm -f "$raw" "$gz.tmp"
        echo "ERROR: $name.gz does not round-trip to the downloaded data" >&2
        return 1
    fi

    mv "$gz.tmp" "$gz"
    rm -f "$raw"
    echo "  staged $name.gz ($(wc -c < "$gz" | tr -d ' ') bytes)"
}

echo "Staging bundled geo data for the Android Magisk module ..."
stage "$GEOSITE_URL" geosite.dat
stage "$GEOIP_URL" geoip.dat

# Written last: the device treats a missing VERSION as "re-expand me", so it
# must not appear unless both data files staged successfully.
printf '%s\n' "$VERSION" > "$GEO_DIR/VERSION"

echo "Bundled geo data staged (version $VERSION):"
ls -l "$GEO_DIR"

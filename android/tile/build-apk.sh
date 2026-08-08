#!/usr/bin/env bash
#
# Build the daed Quick-Settings tile APK using only Android SDK build-tools
# (no Gradle / AGP). Runs on the GitHub Actions runner (Android SDK is
# preinstalled) and in the droidspaces Debian container for local builds.
#
# Requirements: a JDK (javac/keytool/java) and an Android SDK with build-tools
# and a platform (android.jar). The SDK is located via ANDROID_SDK_ROOT /
# ANDROID_HOME, falling back to common install paths.
#
# Output: build/daed-tile.apk, signed with keystore/daed-tile.p12 so the
# signature stays stable across CI builds (a signed system-app upgrade must
# keep the same key).
set -euo pipefail
cd "$(dirname "$0")"

OUT=build
rm -rf "$OUT"
mkdir -p "$OUT/obj" "$OUT/gen"

# --- locate the Android SDK -------------------------------------------------
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  for p in /usr/local/lib/android/sdk "$HOME/Android/Sdk" "$HOME/android-sdk" /opt/android-sdk; do
    if [ -d "$p" ]; then SDK="$p"; break; fi
  done
fi
if [ ! -d "${SDK:-}" ]; then
  echo "ERROR: Android SDK not found. Set ANDROID_SDK_ROOT or ANDROID_HOME." >&2
  exit 1
fi

# Newest build-tools.
BT=""
for d in "$SDK"/build-tools/*/; do
  [ -d "$d" ] || continue
  if [ -z "$BT" ] || [ "$(basename "$d")" \> "$(basename "$BT")" ]; then
    BT="${d%/}"
  fi
done
# Newest platform.
PLAT=""
for d in "$SDK"/platforms/android-*/; do
  [ -d "$d" ] || continue
  if [ -z "$PLAT" ] || [ "$(basename "$d")" \> "$(basename "$PLAT")" ]; then
    PLAT="${d%/}"
  fi
done

resolve() { # resolve <path-without-extension> -> existing tool path
  [ -x "$1" ] && { echo "$1"; return; }
  [ -x "$1.exe" ] && { echo "$1.exe"; return; }
  echo "$1"
}
AAPT2="$(resolve "$BT/aapt2")"
ZIPALIGN="$(resolve "$BT/zipalign")"
ANDROID_JAR="$PLAT/android.jar"
D8_JAR="$BT/lib/d8.jar"
APKSIGNER_JAR="$BT/lib/apksigner.jar"

for t in "$AAPT2" "$ZIPALIGN" "$ANDROID_JAR" "$D8_JAR" "$APKSIGNER_JAR"; do
  [ -e "$t" ] || { echo "ERROR: missing $t" >&2; exit 1; }
done
for c in javac keytool java; do
  command -v "$c" >/dev/null || { echo "ERROR: '$c' not found (need a JDK)" >&2; exit 1; }
done

echo "SDK        = $SDK"
echo "build-tools= $BT"
echo "platform   = $PLAT"

# d8 / apksigner are invoked through their jars so the script works the same
# on Linux and Windows (build-tools ships a d8 / apksigner launcher per OS).
D8()        { java -cp "$D8_JAR" com.android.tools.r8.D8 "$@"; }
APKSIGNER() { java -cp "$APKSIGNER_JAR" com.android.apksigner.ApkSignerTool "$@"; }

# --- compile Java -----------------------------------------------------------
# -source/-target 8: javac >= 9 rejects -bootclasspath with a target > 8
# ("option --boot-class-path not allowed with target 11"), and compiling
# against android.jar as the boot class path is the only way to check Java
# APIs against what Android actually ships. The tile source is Java 8 syntax
# (lambdas / method references only); d8 desugars it for min-api 26.
find src -name '*.java' > "$OUT/sources.txt"
javac -source 8 -target 8 -nowarn \
  -bootclasspath "$ANDROID_JAR" \
  -d "$OUT/obj" @"$OUT/sources.txt"

# --- compile + link resources (aapt2) --------------------------------------
"$AAPT2" compile --dir res -o "$OUT/res.zip"
"$AAPT2" link -o "$OUT/unsigned.apk" \
  -I "$ANDROID_JAR" \
  --manifest AndroidManifest.xml \
  --java "$OUT/gen" \
  --min-sdk-version 26 \
  --target-sdk-version 34 \
  --auto-add-overlay \
  "$OUT/res.zip"

# Compile the R.java generated under gen/.
javac -source 8 -target 8 -nowarn \
  -bootclasspath "$ANDROID_JAR" \
  -d "$OUT/obj" $(find "$OUT/gen" -name 'R.java')

# --- dex --------------------------------------------------------------------
D8 --release --lib "$ANDROID_JAR" --min-api 26 \
  --output "$OUT/obj" $(find "$OUT/obj" -name '*.class')
# jar (from the JDK) avoids depending on the 'zip' package.
jar uf "$OUT/unsigned.apk" -C "$OUT/obj" classes.dex

# --- align + sign -----------------------------------------------------------
"$ZIPALIGN" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

KS="$OUT/daed-tile.p12"
if [ -f "keystore/daed-tile.p12" ]; then
  cp "keystore/daed-tile.p12" "$KS"
else
  # Throwaway key for ad-hoc local builds (system-app upgrades will then fail
  # the signature check; use the committed keystore for anything you ship).
  keytool -genkeypair -keystore "$KS" -storetype PKCS12 -storepass android \
    -keypass android -alias daed -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=daed tile" >/dev/null 2>&1
fi
APKSIGNER sign --ks "$KS" --ks-type PKCS12 --ks-pass pass:android \
  --key-pass pass:android --out "$OUT/daed-tile.apk" "$OUT/aligned.apk"
APKSIGNER verify "$OUT/daed-tile.apk"

echo "OK: $OUT/daed-tile.apk"

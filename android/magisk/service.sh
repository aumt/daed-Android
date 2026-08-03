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

# Launch daed in background with logging
nohup "$DAED_BIN" run -c /data/adb/daed >> "$LOG_FILE" 2>&1 &

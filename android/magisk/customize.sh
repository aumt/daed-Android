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
ui_print "  Tap = start/stop dae proxy (web UI keeps running)"
ui_print "  Long-press -> detail sheet -> gear = open web UI"
ui_print ""
ui_print "Installation completed."

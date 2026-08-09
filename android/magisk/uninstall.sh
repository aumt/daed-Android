#!/system/bin/sh

# Magisk uninstall script: stop daed and notify user

# Stop daed process
pkill -f 'daed run' >/dev/null 2>&1

# Remove the Quick-Settings tile app that customize.sh / service.sh may have
# installed as a user app (a pure system-app registration is untouched and
# disappears with the module itself). No-op if it is not installed.
pm uninstall io.github.aumt.daedtile >/dev/null 2>&1

ui_print "daed has been stopped."
ui_print "Config directory /data/adb/daed has been preserved."
ui_print "You may back it up or remove it manually if no longer needed."

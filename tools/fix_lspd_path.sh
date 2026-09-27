#!/usr/bin/env bash
# After every `adb install -r` the apk lands in a new /data/app/~~X/<pkg>-Y/
# dir, but LSPosed's modules_config.db keeps pointing at the OLD path and the
# module silently stops loading everywhere. This rewrites the modules table
# apk_path for com.islandbridge to the currently installed codePath.
set -e
PKG=com.islandbridge
TMP_PC='C:/Users/cy183/AppData/Local/Temp'
CODEPATH=$(adb shell "dumpsys package $PKG | grep codePath" | tr -d '\r' | cut -d= -f2-)
[ -n "$CODEPATH" ] || { echo "no codePath for $PKG"; exit 1; }
NEWAPK="$CODEPATH/base.apk"
echo "installed: $NEWAPK"

adb shell 'su -c "cp /data/adb/lspd/config/modules_config.db /data/local/tmp/fx.db && cp /data/adb/lspd/config/modules_config.db-wal /data/local/tmp/fx.db-wal 2>/dev/null; cp /data/adb/lspd/config/modules_config.db-shm /data/local/tmp/fx.db-shm 2>/dev/null; chmod 666 /data/local/tmp/fx.db*"'
MSYS_NO_PATHCONV=1 adb pull /data/local/tmp/fx.db "$TMP_PC/fx.db" >/dev/null
MSYS_NO_PATHCONV=1 adb pull /data/local/tmp/fx.db-wal "$TMP_PC/fx.db-wal" >/dev/null 2>&1 || true
MSYS_NO_PATHCONV=1 adb pull /data/local/tmp/fx.db-shm "$TMP_PC/fx.db-shm" >/dev/null 2>&1 || true

python - "$NEWAPK" <<'PY'
import sqlite3, sys
db = sqlite3.connect(r'C:/Users/cy183/AppData/Local/Temp/fx.db')
db.execute("update modules set apk_path=? where module_pkg_name='com.islandbridge'", (sys.argv[1],))
db.commit()
print('db now:', db.execute("select apk_path from modules where module_pkg_name='com.islandbridge'").fetchone()[0])
db.execute('pragma wal_checkpoint(truncate)')
db.close()
PY

MSYS_NO_PATHCONV=1 adb push "$TMP_PC/fx.db" /data/local/tmp/fx.db >/dev/null
adb shell 'su -c "cat /data/local/tmp/fx.db > /data/adb/lspd/config/modules_config.db && rm -f /data/adb/lspd/config/modules_config.db-wal /data/adb/lspd/config/modules_config.db-shm /data/local/tmp/fx.db*"'
echo "modules_config.db updated — reboot (or restart target app) to take effect"

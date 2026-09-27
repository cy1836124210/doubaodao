#!/usr/bin/env pwsh
# Reusable deploy: install APK, sync LSPosed's apk_path to the new location,
# install the root relay as a boot service, reboot, verify.
param(
  [switch]$NoReboot,
  [string]$Adb = "D:\tool\android-sdk\platform-tools\adb.exe",
  [string]$Apk = "D:\aiwork\doubaoni\android\app\build\outputs\apk\debug\app-debug.apk"
)
$ErrorActionPreference = "Continue"

Write-Host "=== install ==="
& $Adb install -r $Apk 2>&1 | Select-String "Success|Failure|Error"
$path = (& $Adb shell "pm path com.islandbridge" 2>$null | Select-String "package:" |
         ForEach-Object { $_.ToString().Replace("package:","").Trim() })
Write-Host "apk_path = $path"

Write-Host "=== sync LSPosed db ==="
& $Adb shell "su -c 'cp /data/adb/lspd/config/modules_config.db /data/local/tmp/m.db'" 2>$null
& $Adb pull /data/local/tmp/m.db "$env:TEMP\m2.db" 2>$null | Out-Null
python -c @"
import sqlite3
c=sqlite3.connect(r'$env:TEMP\m2.db')
old=c.execute('select apk_path from modules where module_pkg_name=?',('com.islandbridge',)).fetchone()
c.execute('update modules set apk_path=? where module_pkg_name=?',(r'$path','com.islandbridge'))
print('  old =', old[0] if old else None)
print('  new =', c.execute('select apk_path from modules where module_pkg_name=?',('com.islandbridge',)).fetchone()[0])
print('  state =', c.execute('select * from modules_state where module_pkg_name=?',('com.islandbridge',)).fetchall())
c.commit(); c.close()
"@
& $Adb push "$env:TEMP\m2.db" /data/local/tmp/m2.db 2>$null | Out-Null
& $Adb shell "su -c 'cd /data/adb/lspd/config && rm -f modules_config.db-wal modules_config.db-shm && cp /data/local/tmp/m2.db modules_config.db && chown system:system modules_config.db && chmod 600 modules_config.db'" 2>$null

Write-Host "=== install root runtime ==="
# NOTE: do NOT copy the relay into service.d — KernelSU executes EVERY .sh
# there. The launcher is the single entry point; workers live in
# /data/adb/islandbridge/. Use deploy_root.ps1 for the root runtime.
& $Adb push "D:\aiwork\doubaoni\dev\root\relay.sh"    /data/local/tmp/ib_relay.sh    2>$null | Out-Null
& $Adb push "D:\aiwork\doubaoni\dev\root\listen.sh"   /data/local/tmp/ib_listen.sh   2>$null | Out-Null
& $Adb push "D:\aiwork\doubaoni\dev\root\launcher.sh" /data/local/tmp/ib_launcher.sh 2>$null | Out-Null
& $Adb shell @"
su -c '
  mkdir -p /data/adb/islandbridge
  cp /data/local/tmp/ib_relay.sh    /data/adb/islandbridge/relay.sh
  cp /data/local/tmp/ib_listen.sh   /data/adb/islandbridge/listen.sh
  cp /data/local/tmp/ib_launcher.sh /data/adb/service.d/islandbridge.sh
  chmod 755 /data/adb/islandbridge/*.sh /data/adb/service.d/islandbridge.sh
  chown 0:0 /data/adb/islandbridge/*.sh /data/adb/service.d/islandbridge.sh
  rm -f /data/adb/service.d/islandbridge_relay.sh /data/adb/service.d/islandbridge_listen.sh /data/adb/service.d/zz_islandbridge.sh
  sh /data/adb/service.d/islandbridge.sh restart
  echo "--- service.d ---"; ls /data/adb/service.d/
'
"@ 2>$null

if ($NoReboot) { Write-Host "=== skipped reboot ==="; exit 0 }
Write-Host "=== reboot ==="
& $Adb reboot 2>$null
Start-Sleep -Seconds 70
& $Adb wait-for-device 2>$null
Start-Sleep -Seconds 40
Write-Host "boot_completed = $(& $Adb shell getprop sys.boot_completed 2>$null)"

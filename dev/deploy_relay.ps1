param([string]$Adb = "D:\tool\android-sdk\platform-tools\adb.exe")
$ErrorActionPreference = "Continue"
$src = "D:\aiwork\doubaoni\android\app\src\main\assets"

Write-Host "=== push helper scripts ==="
& $Adb push "$src\ib_relay.sh"  /data/local/tmp/islandbridge_relay.sh  2>$null | Out-Null
& $Adb push "$src\ib_listen.sh" /data/local/tmp/islandbridge_listen.sh 2>$null | Out-Null
& $Adb push "D:\aiwork\doubaoni\dev\service.d\zz_islandbridge.sh" /data/local/tmp/zz_islandbridge.sh 2>$null | Out-Null

& $Adb shell @"
su -c '
  mkdir -p /data/adb/service.d
  cp /data/local/tmp/islandbridge_relay.sh  /data/adb/service.d/islandbridge_relay.sh
  cp /data/local/tmp/islandbridge_listen.sh /data/adb/service.d/islandbridge_listen.sh
  cp /data/local/tmp/zz_islandbridge.sh     /data/adb/service.d/zz_islandbridge.sh
  chmod 755 /data/adb/service.d/islandbridge_*.sh /data/adb/service.d/zz_islandbridge.sh
  chown 0:0 /data/adb/service.d/islandbridge_*.sh /data/adb/service.d/zz_islandbridge.sh
  rm -f /data/adb/service.d/_marker_test.sh
  rm -f /data/local/tmp/marker.log /data/local/tmp/relay.log /data/local/tmp/islandbridge_relay.log
  ls -l /data/adb/service.d/
'
"@ 2>$null

Write-Host "=== reboot ==="
& $Adb reboot 2>$null
Start-Sleep -Seconds 70
& $Adb wait-for-device 2>$null
Start-Sleep -Seconds 45
Write-Host "boot_completed = $(& $Adb shell getprop sys.boot_completed 2>$null)"

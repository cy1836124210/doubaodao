param([string]$Adb = "D:\tool\android-sdk\platform-tools\adb.exe", [switch]$NoReboot)
$ErrorActionPreference = "Continue"
$R = "D:\aiwork\doubaoni\dev\root"

Write-Host "=== push root runtime ==="
& $Adb push "$R\relay.sh"    /data/local/tmp/ib_relay.sh    2>$null | Out-Null
& $Adb push "$R\listen.sh"   /data/local/tmp/ib_listen.sh   2>$null | Out-Null
& $Adb push "$R\launcher.sh" /data/local/tmp/ib_launcher.sh 2>$null | Out-Null

& $Adb shell @"
su -c '
  mkdir -p /data/adb/islandbridge
  cp /data/local/tmp/ib_relay.sh    /data/adb/islandbridge/relay.sh
  cp /data/local/tmp/ib_listen.sh   /data/adb/islandbridge/listen.sh
  cp /data/local/tmp/ib_launcher.sh /data/adb/service.d/islandbridge.sh
  chmod 755 /data/adb/islandbridge/*.sh /data/adb/service.d/islandbridge.sh
  chown 0:0 /data/adb/islandbridge/*.sh /data/adb/service.d/islandbridge.sh
  # service.d must contain exactly ONE script; workers live in islandbridge/
  rm -f /data/adb/service.d/islandbridge_relay.sh
  rm -f /data/adb/service.d/islandbridge_listen.sh
  rm -f /data/adb/service.d/zz_islandbridge.sh
  echo "--- service.d ---"; ls /data/adb/service.d/
  echo "--- islandbridge ---"; ls /data/adb/islandbridge/
'
"@ 2>$null

Write-Host "=== restart workers now ==="
& $Adb shell "su -c 'sh /data/adb/service.d/islandbridge.sh restart'" 2>$null

if ($NoReboot) { exit 0 }
Write-Host "=== reboot ==="
& $Adb reboot 2>$null
Start-Sleep -Seconds 70
& $Adb wait-for-device 2>$null
Start-Sleep -Seconds 45
Write-Host "boot_completed = $(& $Adb shell getprop sys.boot_completed 2>$null)"

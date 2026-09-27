@echo off
rem Build IslandBridgeDaemon.exe + IslandBridgeSetup.exe into dist\
cd /d %~dp0\..

pyinstaller --noconfirm --onefile --noconsole --name IslandBridgeDaemon ^
  --paths ..\tools --paths ..\pylibs ^
  --add-data "island_hook.js;." ^
  bridge_daemon.py || exit /b 1

pyinstaller --noconfirm --onefile --console --name IslandBridgeSetup ^
  --paths . ^
  installer\installer.py || exit /b 1

echo.
echo === dist\IslandBridgeDaemon.exe + dist\IslandBridgeSetup.exe ===
echo Ship both together; run IslandBridgeSetup.exe to install.

@echo off
rem 以 CDP 调试端口启动豆包桌面端（IslandBridge 抓取依赖此端口）
start "" "D:\aiwork\doubaoni\Doubao\app\Doubao.exe" --remote-debugging-port=9222

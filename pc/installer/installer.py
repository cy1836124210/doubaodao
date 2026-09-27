"""IslandBridgeSetup — 标准安装程序 (console).

Installs the IslandBridge daemon next to the user's profile and hooks it
into Doubao's launch entries so Doubao always starts with
--remote-debugging-port=9222 — coexistence, no DLL injection, no file
patches inside Doubao itself.

  IslandBridgeSetup.exe            install
  IslandBridgeSetup.exe --uninstall   remove

Layout:  %LOCALAPPDATA%\\IslandBridge\\
    IslandBridgeDaemon.exe   (the bridge)
    install.json             (doubao path + install time)
"""
import json
import os
import shutil
import subprocess
import sys
import time
import winreg
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import win_hook                       # noqa: E402

FROZEN = getattr(sys, "frozen", False)
HERE = Path(sys.executable).resolve().parent if FROZEN \
    else Path(__file__).resolve().parent
INSTALL_DIR = Path(os.path.expandvars(r"%LOCALAPPDATA%\IslandBridge"))
DAEMON_EXE = "IslandBridgeDaemon.exe"
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
RUN_NAME = "IslandBridgeDaemon"


def say(*a):
    print(*a, flush=True)


def find_daemon_payload():
    """The daemon exe must sit next to the setup exe (dist bundle)."""
    p = HERE / DAEMON_EXE
    return p if p.exists() else None


def locate_doubao():
    exe = win_hook.find_doubao_exe()
    if exe:
        return exe
    say("未自动找到豆包，请输入 Doubao.exe 完整路径（拖入窗口也可）:")
    s = input("> ").strip().strip('"')
    if s.lower().endswith("doubao.exe") and os.path.exists(s):
        return s
    return None


def install():
    say("=== 豆包岛桥 IslandBridge 安装 ===")
    doubao = locate_doubao()
    if not doubao:
        say("!! 找不到豆包安装路径，安装中止")
        return 1
    say(f"[i] 豆包: {doubao}")

    src = find_daemon_payload()
    if not src:
        say(f"!! 缺少 {DAEMON_EXE}（应与安装程序同目录）")
        return 1

    INSTALL_DIR.mkdir(parents=True, exist_ok=True)
    dst = INSTALL_DIR / DAEMON_EXE
    shutil.copy2(src, dst)
    say(f"[i] daemon -> {dst}")

    # hook Doubao's own launch entries
    r1 = win_hook.patch_run_key()
    r2 = win_hook.patch_shortcuts()
    say(f"[i] Run 启动项已注入 flag: {r1 or '(已含/无)'}")
    say(f"[i] 快捷方式已注入 flag: {r2 or '(已含/无)'}")

    # autostart our daemon
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0,
                        winreg.KEY_SET_VALUE) as k:
        winreg.SetValueEx(k, RUN_NAME, 0, winreg.REG_SZ, f'"{dst}"')
    say(f"[i] 开机自启: {RUN_NAME}")

    (INSTALL_DIR / "install.json").write_text(json.dumps({
        "doubao": doubao, "installed_at": time.time(),
        "flag": win_hook.FLAG}, ensure_ascii=False, indent=2),
        encoding="utf-8")

    # start daemon now
    subprocess.Popen([str(dst)], creationflags=subprocess.DETACHED_PROCESS
                     | subprocess.CREATE_NO_WINDOW, close_fds=True)
    say("[i] daemon 已启动（后台无窗口）")

    bad = win_hook.doubao_missing_flag()
    if bad:
        say("!! 当前运行的豆包未带调试端口 —— 下次重启豆包/开机后生效，"
            "或现在手动退出豆包重开")
    say(f"监控页: http://localhost:8787/  日志: {INSTALL_DIR}\\daemon.log")
    say("=== 完成 ===")
    return 0


def uninstall():
    say("=== 卸载 IslandBridge ===")
    subprocess.run(["taskkill", "/IM", DAEMON_EXE, "/F"],
                   capture_output=True)
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0,
                            winreg.KEY_SET_VALUE) as k:
            winreg.DeleteValue(k, RUN_NAME)
    except OSError:
        pass
    r1 = win_hook.unpatch_run_key()
    r2 = win_hook.unpatch_shortcuts()
    say(f"[i] 已从启动项移除 flag: {r1 or '(无)'} / 快捷方式: {r2 or '(无)'}")
    try:
        shutil.rmtree(INSTALL_DIR)
        say(f"[i] 已删除 {INSTALL_DIR}")
    except OSError as e:
        say(f"!! 删除目录失败: {e}")
    say("=== 完成 ===")
    return 0


def main():
    rc = uninstall() if "--uninstall" in sys.argv else install()
    if FROZEN and sys.stdout.isatty():
        input("按回车退出…")
    return rc


if __name__ == "__main__":
    sys.exit(main())

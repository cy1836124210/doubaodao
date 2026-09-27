"""Coexistence hook: make sure every Doubao launch entry carries
--remote-debugging-port=9222 so bridge_daemon can attach over CDP.

Covers the places Doubao can be started from:
  * HKCU\\...\\Run  (Doubao registers "doubao" = stub.exe --launch_from=auto_run)
  * .lnk shortcuts (Desktop, Start Menu, Pinned Taskbar)
The Doubao launcher stub (Doubao\\Doubao.exe) forwards args to
app\\Doubao.exe — verified — so patching its command line is enough.

All edits are additive and reversible (uninstall removes only our flag).
"""
import json
import os
import re
import subprocess
import winreg


def _run_ps(script, timeout=30, env=None):
    """Run a powershell -Command without ever flashing a console window.

    The daemon is a --noconsole exe; a bare subprocess.run("powershell")
    makes the child allocate its own console → visible window flash every
    watchdog tick. CREATE_NO_WINDOW + hidden STARTUPINFO keep it silent."""
    si = subprocess.STARTUPINFO()
    si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    si.wShowWindow = 0  # SW_HIDE
    return subprocess.run(
        ["powershell", "-NoProfile", "-Command", script],
        capture_output=True, text=True, timeout=timeout, env=env,
        creationflags=subprocess.CREATE_NO_WINDOW,
        startupinfo=si)

FLAG = "--remote-debugging-port=9222"
FLAG_RE = re.compile(r"--remote-debugging-port=\d+")

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
LNK_DIRS = [
    os.path.expandvars(r"%USERPROFILE%\Desktop"),
    os.path.expandvars(r"%PUBLIC%\Desktop"),
    os.path.expandvars(r"%APPDATA%\Microsoft\Windows\Start Menu\Programs"),
    os.path.expandvars(r"%PROGRAMDATA%\Microsoft\Windows\Start Menu\Programs"),
    os.path.expandvars(
        r"%APPDATA%\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"),
]

_EXE_RE = re.compile(r'^(?P<q>"?)(?P<exe>[^"\s]+\.exe)(?P=q)(?P<args>.*)$',
                     re.IGNORECASE)


def _exe_part(cmdline):
    """Split 'C:\\x\\Doubao.exe' --a --b into (exe, args)."""
    m = _EXE_RE.match(cmdline.strip())
    if not m:
        return None, None
    return m.group("exe"), m.group("args") or ""


def _is_doubao(exe):
    return exe and "doubao" in exe.lower()


def ensure_flag_in_cmdline(cmdline):
    """Return cmdline with our flag present (unchanged if already there)."""
    if FLAG_RE.search(cmdline):
        return cmdline
    exe, args = _exe_part(cmdline)
    if not exe:
        return cmdline
    return f'"{exe}" {FLAG} {args.strip()}'.rstrip()


def strip_flag_from_cmdline(cmdline):
    return FLAG_RE.sub("", cmdline).replace("  ", " ").rstrip()


# ---------- HKCU Run ----------
def _iter_run_values():
    try:
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0,
                           winreg.KEY_READ)
    except OSError:
        return
    with k:
        i = 0
        while True:
            try:
                name, val, _ = winreg.EnumValue(k, i)
            except OSError:
                break
            yield name, val
            i += 1


def _set_run_value(name, val):
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0,
                        winreg.KEY_SET_VALUE) as k:
        winreg.SetValueEx(k, name, 0, winreg.REG_SZ, val)


def patch_run_key():
    """Add the flag to every Run entry that launches Doubao."""
    changed = []
    for name, val in list(_iter_run_values()):
        if not isinstance(val, str):
            continue
        exe, _ = _exe_part(val)
        if not _is_doubao(exe):
            continue
        new = ensure_flag_in_cmdline(val)
        if new != val:
            _set_run_value(name, new)
            changed.append(name)
    return changed


def unpatch_run_key():
    changed = []
    for name, val in list(_iter_run_values()):
        if not isinstance(val, str) or not FLAG_RE.search(val):
            continue
        exe, _ = _exe_part(val)
        if not _is_doubao(exe):
            continue
        _set_run_value(name, strip_flag_from_cmdline(val))
        changed.append(name)
    return changed


# ---------- .lnk shortcuts (via WScript.Shell COM in PowerShell) ----------
_PS_ENUM = r"""
$ws = New-Object -ComObject WScript.Shell
Get-ChildItem -LiteralPath %s -Filter *.lnk -Recurse -ErrorAction SilentlyContinue |
  ForEach-Object {
    try {
      $s = $ws.CreateShortcut($_.FullName)
      if ($s.TargetPath -match 'doubao') {
        [pscustomobject]@{Path=$_.FullName; Args=$s.Arguments; Target=$s.TargetPath}
      }
    } catch {}
  } | ConvertTo-Json -Compress
"""


def _doubao_shortcuts():
    dirs = ",".join(f"'{d}'" for d in LNK_DIRS)
    ps = _PS_ENUM % f"@({dirs})"
    try:
        out = _run_ps(ps, timeout=30).stdout.strip()
    except Exception:
        return []
    if not out:
        return []
    try:
        data = json.loads(out)
    except Exception:
        return []
    return data if isinstance(data, list) else [data]


_PS_PATCH = r"""
$ws = New-Object -ComObject WScript.Shell
$s = $ws.CreateShortcut($env:IB_LNK)
$s.Arguments = $env:IB_ARGS
$s.Save()
"""


def _set_lnk_args(path, args):
    env = dict(os.environ, IB_LNK=path, IB_ARGS=args)
    _run_ps(_PS_PATCH, timeout=20, env=env)


def patch_shortcuts():
    changed = []
    for s in _doubao_shortcuts():
        args = s.get("Args") or ""
        if FLAG_RE.search(args):
            continue
        _set_lnk_args(s["Path"], f"{FLAG} {args}".strip())
        changed.append(s["Path"])
    return changed


def unpatch_shortcuts():
    changed = []
    for s in _doubao_shortcuts():
        args = s.get("Args") or ""
        if not FLAG_RE.search(args):
            continue
        _set_lnk_args(s["Path"], strip_flag_from_cmdline(args))
        changed.append(s["Path"])
    return changed


# ---------- Doubao discovery ----------
def find_doubao_exe():
    """Locate the Doubao launcher exe (stub) or inner app exe."""
    for _n, val in _iter_run_values():
        if isinstance(val, str):
            exe, _ = _exe_part(val)
            if _is_doubao(exe) and os.path.exists(exe):
                return exe
    # common install roots
    roots = [
        os.path.expandvars(r"%LOCALAPPDATA%\Doubao"),
        os.path.expandvars(r"%ProgramFiles%\Doubao"),
        os.path.expandvars(r"%ProgramFiles(x86)%\Doubao"),
        r"D:\aiwork\doubaoni\Doubao",
    ]
    for root in roots:
        for cand in (os.path.join(root, "Doubao.exe"),
                     os.path.join(root, "app", "Doubao.exe")):
            if os.path.exists(cand):
                return cand
    return None


def doubao_missing_flag():
    """List Doubao processes (main browser process only) started without
    the debug flag — capture impossible until restarted."""
    ps = ("Get-CimInstance Win32_Process -Filter \"Name='Doubao.exe'\" | "
          "Where-Object {$_.CommandLine -notmatch '--type='} | "
          "Select-Object -ExpandProperty CommandLine")
    try:
        out = _run_ps(ps, timeout=30).stdout
    except Exception:
        return []
    bad = []
    seg = re.compile(r"[\\/]doubao[\\/]", re.IGNORECASE)   # dir segment must be exactly "doubao"
    for line in out.splitlines():
        line = line.strip()
        if seg.search(line) and not FLAG_RE.search(line):
            bad.append(line)
    return bad


def ensure_all():
    """Apply every coexistence patch. Returns summary dict."""
    return {
        "run": patch_run_key(),
        "lnk": patch_shortcuts(),
        "missing_flag": doubao_missing_flag(),
    }

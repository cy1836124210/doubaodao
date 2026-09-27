"""IslandBridge CLI monitor — subscribe the SSE feed and pretty-print.

    python monitor.py [host] [port]        # default 127.0.0.1 8787
"""
import json
import sys
import urllib.request

KIND_COLOR = {"chat": "\033[94m", "plan": "\033[92m"}
RESET = "\033[0m"
DIM = "\033[90m"


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8787
    url = f"http://{host}:{port}/events"
    print(f"{DIM}subscribing {url} …{RESET}")
    req = urllib.request.Request(url, headers={"Accept": "text/event-stream"})
    with urllib.request.urlopen(req, timeout=None) as r:
        data = ""
        for raw in r:
            line = raw.decode("utf-8", "replace").rstrip("\r\n")
            if line.startswith(":"):
                continue
            if line.startswith("data:"):
                data += line[5:].lstrip()
                continue
            if line == "" and data:
                show(data)
                data = ""


def show(data):
    import time
    try:
        o = json.loads(data)
    except Exception:
        print(DIM + data + RESET)
        return
    t = o.get("t", "?")
    color = KIND_COLOR.get(t.split(".")[0], DIM)
    ts = time.strftime("%H:%M:%S")
    if t == "chat.delta":
        kind = o.get("kind", "")
        txt = (o.get("text") or "")[:80].replace("\n", " ")
        print(f"{ts} {color}♫ {kind:<5}{RESET} {txt}")
    elif t == "chat.reply":
        txt = (o.get("text") or "")[:200].replace("\n", " ")
        print(f"{ts} {color}◆ reply{RESET} {txt}")
    else:
        print(f"{ts} {color}{t}{RESET} "
              + json.dumps(o, ensure_ascii=False)[:160])


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass

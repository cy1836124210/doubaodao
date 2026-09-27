"""Tiny SSE test client: prints every event the daemon broadcasts.

    python test_client.py [host] [port]
"""
import sys
import urllib.request

host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8787

url = f"http://{host}:{port}/events"
print(f"connected {url} — waiting for events")
req = urllib.request.Request(url, headers={"Accept": "text/event-stream"})
with urllib.request.urlopen(req, timeout=None) as r:
    for raw in r:
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if line and not line.startswith(":"):
            print(line)

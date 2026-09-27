"""IslandBridge SSE server (stdlib only).

Serves the phone app over plain HTTP so clients subscribe with a normal
streaming GET — same shape as the 星岛通道 /tugou endpoints:

    GET /events  -> text/event-stream, each frame "data: {json}\n\n",
                    heartbeat ": hb" comment every HEARTBEAT_S seconds
    GET /health  -> {"ok":true,"clients":N,"proto":"islandbridge-sse/1"}
    POST /reply  -> {"text": "...", "cid": "..."} sends the text into the
                    Doubao desktop chat via CDP; returns {"ok":bool,...}

Usage:
    sse = SseServer(8787)
    sse.start()
    sse.broadcast({"t": "chat.delta", ...})
"""
import json
import queue
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HEARTBEAT_S = 15
PROTO = "islandbridge-sse/1"

MONITOR_HTML = """<!DOCTYPE html><html lang=zh><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>IslandBridge 监控</title><style>
body{background:#14161a;color:#e8eaf0;font:13px/1.6 Consolas,monospace;
margin:0;padding:10px}
h1{font:15px sans-serif;color:#9aa0ab;margin:0 0 8px}
h1 b{color:#4d7cfe}
#st{color:#3fce8a}
.ev{border-left:2px solid #2c3038;padding:2px 8px;margin:3px 0;
white-space:pre-wrap;word-break:break-all}
.chat{border-color:#4d7cfe}.plan{border-color:#3fce8a}
.sys{border-color:#9aa0ab;color:#9aa0ab}
</style></head><body>
<h1>IslandBridge 监控 — <b id=st>连接中…</b> <span id=nc></span></h1>
<div id=f></div><script>
const f=document.getElementById('f'),st=document.getElementById('st'),
nc=document.getElementById('nc');
const es=new EventSource('/events');
es.onopen=()=>{st.textContent='已连接'};
es.onerror=()=>{st.textContent='断开重连中…';st.style.color='#e06c75'};
es.onmessage=e=>{
 try{const o=JSON.parse(e.data);
  const d=document.createElement('div');
  d.className='ev '+(o.t||'').split('.')[0];
  d.textContent=new Date().toLocaleTimeString()+' '+e.data;
  f.appendChild(d);window.scrollTo(0,1e9);
  while(f.children.length>500)f.removeChild(f.firstChild);
 }catch(_){}
};
setInterval(()=>fetch('/health').then(r=>r.json()).then(h=>{
 st.textContent='已连接';st.style.color='#3fce8a';
 nc.textContent='订阅客户端:'+h.clients;}).catch(()=>{}),5000);
</script></body></html>"""


class SseServer:
    def __init__(self, port, on_client=None, on_reply=None):
        self.port = port
        self.on_client = on_client
        # on_reply(text, cid) -> (ok, detail); wired to the CDP injector
        self.on_reply = on_reply
        self._clients = []          # list[queue.Queue]
        self._lock = threading.Lock()
        self._http = None
        self._thread = None

    # ---------- public ----------
    def start(self):
        outer = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def _json(self, obj, code=200):
                body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                path = self.path.split("?")[0]
                if path == "/health":
                    self._json({"ok": True, "proto": PROTO,
                                "clients": outer.count()})
                elif path == "/events":
                    self._sse()
                elif path == "/" or path == "/monitor":
                    body = MONITOR_HTML.encode("utf-8")
                    self.send_response(200)
                    self.send_header("Content-Type",
                                     "text/html; charset=utf-8")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                else:
                    self._json({"error": "not found"}, 404)

            def do_POST(self):
                path = self.path.split("?")[0]
                if path != "/reply":
                    return self._json({"error": "not found"}, 404)
                try:
                    n = int(self.headers.get("Content-Length", 0))
                    body = json.loads(
                        self.rfile.read(n).decode("utf-8") or "{}")
                except Exception:
                    return self._json({"ok": False,
                                       "detail": "bad json"}, 400)
                text = (body.get("text") or "").strip()
                if not text:
                    return self._json({"ok": False,
                                       "detail": "empty text"}, 400)
                if outer.on_reply is None:
                    return self._json({"ok": False,
                                       "detail": "no reply handler"}, 503)
                try:
                    ok, detail = outer.on_reply(text, body.get("cid") or "")
                except Exception as e:
                    ok, detail = False, f"{type(e).__name__}: {e}"
                self._json({"ok": ok, "detail": detail},
                           200 if ok else 502)

            def _sse(self):
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "keep-alive")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()

                q = queue.Queue(maxsize=2048)
                outer._add(q)
                try:
                    self.wfile.write(b": hello\n\n")
                    self.wfile.flush()
                    while True:
                        try:
                            item = q.get(timeout=HEARTBEAT_S)
                            payload = ("data: " + item + "\n\n").encode("utf-8")
                        except queue.Empty:
                            payload = b": hb\n\n"
                        self.wfile.write(payload)
                        self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError, OSError):
                    pass
                finally:
                    outer._drop(q)

        class QuietServer(ThreadingHTTPServer):
            def handle_error(self, request, client_address):
                pass          # aborted clients are routine; don't spam log

        self._http = QuietServer(("0.0.0.0", self.port), Handler)
        self._thread = threading.Thread(target=self._http.serve_forever,
                                        daemon=True)
        self._thread.start()

    def broadcast(self, obj):
        line = json.dumps(obj, ensure_ascii=False)
        with self._lock:
            for q in self._clients:
                try:
                    q.put_nowait(line)
                except queue.Full:
                    pass          # slow client: drop rather than stall all

    def count(self):
        with self._lock:
            return len(self._clients)

    def stop(self):
        if self._http:
            self._http.shutdown()
            self._http = None

    # ---------- client registry ----------
    def _add(self, q):
        with self._lock:
            self._clients.append(q)
        if self.on_client:
            self.on_client(q, True)

    def _drop(self, q):
        with self._lock:
            if q in self._clients:
                self._clients.remove(q)
        if self.on_client:
            self.on_client(q, False)

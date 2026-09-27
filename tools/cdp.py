"""Minimal CDP client over websocket-client, with session support."""
import json, sys, threading, time
sys.path.insert(0, r'D:\aiwork\doubaoni\pylibs')
import websocket

class CDP:
    def __init__(self, ws_url, timeout=60):
        self.ws = websocket.create_connection(ws_url, timeout=timeout,
                                              max_size=256*1024*1024,
                                              suppress_origin=True,
                                              ping_interval=25,
                                              ping_timeout=15)
        self._id = 0
        self._lock = threading.Lock()
        self._pending = {}          # id -> queue-ish list
        self._events = []           # buffered events
        self._ev_lock = threading.Lock()
        self.on_event = None        # callable(msg)
        self.on_close = None        # callable() — fired once when reader dies
        self.dead = False
        self._closed = False
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _read_loop(self):
        try:
            while not self._closed:
                try:
                    data = self.ws.recv()
                except Exception:
                    break
                if not data:
                    break
                try:
                    msg = json.loads(data)
                except Exception:
                    continue
                if 'id' in msg:
                    with self._lock:
                        self._pending.setdefault(msg['id'], []).append(msg)
                else:
                    if self.on_event:
                        try:
                            self.on_event(msg)
                        except Exception:
                            pass
                    else:
                        with self._ev_lock:
                            self._events.append(msg)
        finally:
            self.dead = True
            cb = self.on_close
            if cb:
                try:
                    cb()
                except Exception:
                    pass

    def call(self, method, params=None, session_id=None, timeout=60):
        if self.dead:
            raise ConnectionError(f"{method}: cdp websocket closed")
        with self._lock:
            self._id += 1
            mid = self._id
            self._pending[mid] = []
        m = {'id': mid, 'method': method, 'params': params or {}}
        if session_id:
            m['sessionId'] = session_id
        self.ws.send(json.dumps(m))
        deadline = time.time() + timeout
        while time.time() < deadline:
            with self._lock:
                if self._pending.get(mid):
                    msg = self._pending.pop(mid).pop(0)
                    if 'error' in msg:
                        raise RuntimeError(f"{method}: {msg['error']}")
                    return msg.get('result', {})
            time.sleep(0.005)
        raise TimeoutError(method)

    def attach(self, target_id):
        r = self.call('Target.attachToTarget',
                      {'targetId': target_id, 'flatten': True})
        return r['sessionId']

    def close(self):
        self._closed = True
        try:
            self.ws.close()
        except Exception:
            pass


def browser_ws(port=9222):
    import urllib.request
    ver = json.load(urllib.request.urlopen(
        f'http://127.0.0.1:{port}/json/version', timeout=5))
    return ver['webSocketDebuggerUrl']


def find_target(port=9222, url_substr=None, type_=None):
    import urllib.request
    ts = json.load(urllib.request.urlopen(
        f'http://127.0.0.1:{port}/json', timeout=5))
    for t in ts:
        if url_substr and url_substr not in t.get('url', ''):
            continue
        if type_ and t.get('type') != type_:
            continue
        return t
    return None

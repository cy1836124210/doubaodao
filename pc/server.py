"""Minimal WebSocket broadcast server (stdlib only).

Phone app connects ws://<pc-ip>:<port>/island and receives one JSON text
frame per normalized event. No dependencies beyond the standard library.
"""
import base64
import hashlib
import json
import socket
import struct
import threading

_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def _accept_key(key):
    return base64.b64encode(
        hashlib.sha1((key + _GUID).encode()).digest()).decode()


def _send_frame(conn, payload):
    """Send one unmasked text frame."""
    data = payload if isinstance(payload, bytes) else payload.encode("utf-8")
    n = len(data)
    head = bytearray([0x81])
    if n < 126:
        head.append(n)
    elif n < 65536:
        head.append(126)
        head += struct.pack(">H", n)
    else:
        head.append(127)
        head += struct.pack(">Q", n)
    conn.sendall(bytes(head) + data)


class WsServer:
    def __init__(self, port=8787, on_client=None):
        self.port = port
        self.on_client = on_client or (lambda c, ok: None)
        self.clients = set()
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._srv = None

    # ---------- lifecycle ----------
    def start(self):
        self._srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._srv.bind(("0.0.0.0", self.port))
        self._srv.listen(8)
        self._srv.settimeout(1.0)
        threading.Thread(target=self._accept_loop, daemon=True).start()

    def stop(self):
        self._stop.set()
        try:
            self._srv.close()
        except Exception:
            pass
        with self._lock:
            for c in list(self.clients):
                try:
                    c.close()
                except Exception:
                    pass
            self.clients.clear()

    def count(self):
        with self._lock:
            return len(self.clients)

    # ---------- broadcast ----------
    def broadcast(self, obj):
        data = json.dumps(obj, ensure_ascii=False)
        dead = []
        with self._lock:
            for c in self.clients:
                try:
                    _send_frame(c, data)
                except Exception:
                    dead.append(c)
            for c in dead:
                self.clients.discard(c)

    # ---------- internals ----------
    def _accept_loop(self):
        while not self._stop.is_set():
            try:
                conn, _addr = self._srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=self._handshake, args=(conn,),
                             daemon=True).start()

    def _handshake(self, conn):
        try:
            conn.settimeout(10)
            req = b""
            while b"\r\n\r\n" not in req:
                chunk = conn.recv(4096)
                if not chunk:
                    conn.close()
                    return
                req += chunk
            headers = {}
            for line in req.decode("latin1").split("\r\n")[1:]:
                if ":" in line:
                    k, v = line.split(":", 1)
                    headers[k.strip().lower()] = v.strip()
            key = headers.get("sec-websocket-key")
            if not key:
                conn.close()
                return
            resp = ("HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {_accept_key(key)}\r\n\r\n")
            conn.sendall(resp.encode())
            with self._lock:
                self.clients.add(conn)
            self.on_client(conn, True)
            self._read_loop(conn)
        except Exception:
            pass
        self._drop(conn)

    def _read_loop(self, conn):
        """Drain client frames (ping/pong/close); payloads ignored."""
        conn.settimeout(60)
        buf = b""
        while not self._stop.is_set():
            try:
                chunk = conn.recv(65536)
            except socket.timeout:
                _send_frame(conn, b'{"t":"ping"}')
                continue
            if not chunk:
                break
            buf += chunk
            while len(buf) >= 2:
                fin_op = buf[0]
                opcode = fin_op & 0x0F
                masked = buf[1] & 0x80
                ln = buf[1] & 0x7F
                pos = 2
                if ln == 126:
                    if len(buf) < 4:
                        break
                    ln = struct.unpack(">H", buf[2:4])[0]
                    pos = 4
                elif ln == 127:
                    if len(buf) < 10:
                        break
                    ln = struct.unpack(">Q", buf[2:10])[0]
                    pos = 10
                mask = b""
                if masked:
                    if len(buf) < pos + 4:
                        break
                    mask = buf[pos:pos + 4]
                    pos += 4
                if len(buf) < pos + ln:
                    break
                payload = buf[pos:pos + ln]
                buf = buf[pos + ln:]
                if masked:
                    payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
                if opcode == 0x8:          # close
                    return
                if opcode == 0x9:          # ping -> pong
                    try:
                        conn.sendall(b"\x8a" + (b"\x00" if not payload else
                                     bytes([len(payload)]) + payload))
                    except Exception:
                        return

    def _drop(self, conn):
        with self._lock:
            self.clients.discard(conn)
        try:
            conn.close()
        except Exception:
            pass
        self.on_client(conn, False)


if __name__ == "__main__":
    import time
    s = WsServer(8787, lambda c, ok: print("client", "joined" if ok else "left"))
    s.start()
    print("listening on 0.0.0.0:8787 — ctrl-c to stop")
    try:
        while True:
            time.sleep(2)
            s.broadcast({"t": "ping"})
    except KeyboardInterrupt:
        s.stop()

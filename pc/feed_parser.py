"""IslandBridge event parser.

Takes raw __caplog records from island_hook.js and emits normalized events:
    chat.start   {t, mid, cid?, cname?}   new bot reply begins (STREAM_MSG_NOTIFY)
    chat.delta   {t, mid, kind, text, ...} appended text (kind=text|think|tool)
    chat.end     {t, mid, cid?, cname?}   SSE_REPLY_END
    chat.reply   {t, mid, text, cid?, cname?}  full reply text (not sent to island)
    chat.conv    {t, cid, cname}          conversation title learned (im/info)
    plan.start   {t, tid, title, kind}    complex_task_block / thread seen running
    plan.progress{t, tid, name, status, done, total}
    plan.end     {t, tid, success, text}  all tracked threads finished
"""
import base64
import json
from collections import deque


def _b64(s):
    try:
        return base64.b64decode(s)
    except Exception:
        return b""


# block_type -> human label for lyric/status line
def _block_line(btype, content):
    tb = content.get("thinking_block") or {}
    if btype == 10040 and tb:
        return tb.get("streaming_title") or tb.get("finish_title") or ""
    g = content.get("generic_tool_block") or {}
    if btype == 10024 and g:
        return "工具 " + (g.get("title") or g.get("tool_name") or "")
    s = content.get("search_query_result_block") or {}
    if btype == 10025 and s:
        return s.get("summary") or "搜索中"
    if btype == 10006:
        return "正在读取网页"
    if btype == 10019:
        return "文件操作"
    return ""


class FeedParser:
    def __init__(self, emit):
        self.emit = emit            # callable(dict)
        self.buffers = {}           # req_key -> {"text":..., "url":...}
        self.messages = {}          # message_id -> {"text":str,"live":bool}
        self.cid_by_mid = {}        # message_id -> conversation_id
        self.conv_names = {}        # conversation_id -> conversation title
        self.threads = {}           # thread_id -> {"name","status"}
        self.plan_started = False
        self.plan_ended = False
        self.order = []             # thread_id discovery order
        self._frames_seen = deque(maxlen=400)   # recent frame texts
        # (global deque — Doubao's signer issues the same request under two
        #  urls (unsigned + msToken-signed), each wrapper pumps the body)

    # ---------- raw record entry ----------
    def feed(self, rec):
        try:
            k = rec.get("k")
            ev = rec.get("ev")
            url = rec.get("url", "")
            key = (url, rec.get("t"))
            if ev == "chunk" and rec.get("data"):
                buf = self.buffers.setdefault(key, {"text": "", "url": url})
                buf["text"] += _b64(rec["data"]).decode("utf-8", "replace")
                self._drain_sse(key, buf)
            elif ev == "chunk" and rec.get("text"):        # xhr delta
                buf = self.buffers.setdefault(key, {"text": "", "url": url})
                buf["text"] += rec["text"]
                self._drain_sse(key, buf)
            elif ev in ("done", "err", "body"):
                if rec.get("data"):
                    text = _b64(rec["data"]).decode("utf-8", "replace")
                    if "event:" in text and "data:" in text:
                        # backstop full SSE body (Network.getResponseBody)
                        b = {"text": text + "\n\n", "url": url}
                        self._drain_sse(key, b)
                    else:
                        self._drain_json(key, url, text)
                buf = self.buffers.pop(key, None)
                if buf and buf["text"]:
                    self._drain_json(key, url, buf["text"])
        except Exception:
            pass

    # ---------- SSE ----------
    def _drain_sse(self, key, buf):
        text = buf["text"]
        while True:
            i = text.find("\n\n")
            j = text.find("\r\n\r\n")
            idxs = [x for x in (i, j) if x >= 0]
            if not idxs:
                break
            idx = min(idxs)
            sep = 2 if text[idx:idx + 2] == "\n\n" else 4
            frame, text = text[:idx], text[idx + sep:]
            self._sse_frame(key, frame)
        buf["text"] = text

    def _dup_frame(self, frame):
        """Stacked hooks may deliver the same SSE frame twice (each wrapper
        reads its own cloned body). Dedupe on the frame text itself."""
        if frame in self._frames_seen:
            return True
        self._frames_seen.append(frame)
        return False

    def _sse_frame(self, key, frame):
        if self._dup_frame(frame):
            return
        ev, data = "", None
        for line in frame.split("\n"):
            if line.startswith("event:"):
                ev = line[6:].strip()
            elif line.startswith("data:"):
                raw = line[5:].strip()
                try:
                    data = json.loads(raw) if raw else None
                except Exception:
                    data = None
        if not ev:
            return
        if ev == "CHUNK_DELTA" and data:
            # main reply stream for longer answers: {"text": "..."} —
            # no message_id, attach to the currently live message
            self._on_delta(data.get("text") or "")
        elif ev == "STREAM_CHUNK" and data:
            self._on_chunk(data)
        elif ev == "STREAM_MSG_NOTIFY" and data:
            self._on_msg_notify(data)
        elif ev == "ASYNC_CHUNK_SNAPSHOT" and data:
            for snap in data.get("message_snapshots", []):
                self._walk_blocks(snap.get("meta", {}).get("message_id", ""),
                                  (snap.get("content") or {}).get("content_block") or [])
        elif ev == "SSE_REPLY_END":
            self._on_reply_end(key)

    # ---------- message events ----------
    def _on_msg_notify(self, data):
        meta = data.get("meta") or {}
        mid = meta.get("message_id") or ""
        if not mid:
            return
        if meta.get("user_type") == 1:      # user echo, ignore
            return
        cid = str(meta.get("conversation_id")
                  or meta.get("local_conversation_id") or "")
        if cid:
            self.cid_by_mid[mid] = cid
        m = self.messages.setdefault(mid, {"text": "", "think": "", "live": True})
        if meta.get("thread_id"):
            self._thread_seen(meta["thread_id"],
                              (data.get("content") or {}).get("ext", {}).get("agent_name") or "子任务")
        self.emit({"t": "chat.start", "mid": mid, **self._conv(mid)})
        self._walk_blocks(mid, (data.get("content") or {}).get("content_block") or [])

    def _conv(self, mid):
        """Conversation fields to attach to a chat event."""
        cid = self.cid_by_mid.get(mid, "")
        out = {}
        if cid:
            out["cid"] = cid
            name = self.conv_names.get(cid)
            if name:
                out["cname"] = name
        return out

    def _on_delta(self, text):
        """CHUNK_DELTA frame: bare {"text": ...} reply increment."""
        if not text:
            return
        for mid in reversed(list(self.messages)):
            m = self.messages[mid]
            if m.get("live"):
                m["text"] += text
                self.emit({"t": "chat.delta", "mid": mid, "kind": "text",
                           "text": text, **self._conv(mid)})
                return

    def _on_chunk(self, data):
        mid = data.get("message_id") or ""
        if not mid:
            return
        self.messages.setdefault(mid, {"text": "", "think": "", "live": True})
        for op in data.get("patch_op") or []:
            pv = op.get("patch_value") or {}
            if op.get("patch_object") in (1, 3):
                self._walk_blocks(mid, pv.get("content_block") or [])
            elif op.get("patch_object") == 50:
                self._on_ext(mid, pv.get("ext") or {})
        fr = data.get("fin_reason") or {}
        if fr.get("async_task"):
            self.emit({"t": "chat.async", "mid": mid,
                       "task_id": fr["async_task"].get("id", ""),
                       **self._conv(mid)})

    def _walk_blocks(self, mid, blocks):
        m = self.messages.setdefault(mid, {"text": "", "think": "", "live": True})
        for b in blocks:
            bt = b.get("block_type")
            c = b.get("content") or {}
            # plan card
            ctb = c.get("complex_task_block")
            if ctb:
                self._thread_seen(ctb.get("thread_id") or "",
                                  (ctb.get("header") or {}).get("name")
                                  or ctb.get("title") or "子任务",
                                  ctb)
                continue
            # visible reply text
            tb = c.get("text_block") or {}
            delta = tb.get("text") or ""
            if delta:
                m["text"] += delta
                self.emit({"t": "chat.delta", "mid": mid, "kind": "text",
                           "text": delta, **self._conv(mid)})
            # thinking / tool status lines -> lyrics
            line = _block_line(bt, c) or tb.get("summary") or ""
            if line and line != m.get("last_line"):
                m["last_line"] = line
                m["think"] = line
                self.emit({"t": "chat.delta", "mid": mid, "kind": "think",
                           "text": line, **self._conv(mid)})

    def _on_ext(self, mid, ext):
        if ext.get("is_finish") == "1" or (ext.get("async_job") or "").find('"status":2') >= 0:
            self._on_reply_end_mid(mid)
        tid = ext.get("thread_id")
        if tid:
            self._thread_seen(tid, ext.get("agent_name") or "子任务")

    def _on_reply_end(self, key):
        # end the live message on this request stream (usually the newest)
        for mid in reversed(list(self.messages)):
            m = self.messages[mid]
            if m.get("live"):
                self._on_reply_end_mid(mid)
                return

    def _on_reply_end_mid(self, mid):
        m = self.messages.get(mid)
        if not m or not m.get("live"):
            return
        m["live"] = False
        self.emit({"t": "chat.end", "mid": mid, **self._conv(mid)})
        self.emit({"t": "chat.reply", "mid": mid, "text": m.get("text", ""),
                   **self._conv(mid)})

    # ---------- plan / threads ----------
    def _thread_seen(self, tid, name, ctb=None):
        if not tid:
            return
        new = tid not in self.threads
        st = self.threads.setdefault(tid, {"name": name or "子任务", "status": "running"})
        if name:
            st["name"] = name
        if new:
            self.order.append(tid)
        if ctb and ctb.get("status") in (2, "2", "completed"):
            st["status"] = "completed"
        if not self.plan_started:
            self.plan_started = True
            self.emit({"t": "plan.start", "tid": tid, "title": name or "计划任务",
                       "kind": (ctb or {}).get("display_type") or "thread"})
        self._emit_progress()

    def _on_thread_info(self, tid, name, status):
        if not tid:
            return
        st = self.threads.setdefault(tid, {"name": name or "子任务", "status": "running"})
        if tid not in self.order:
            self.order.append(tid)
        changed = status and status != st["status"]
        if name:
            st["name"] = name
        if changed:
            st["status"] = status
            if not self.plan_started:
                self.plan_started = True
                self.emit({"t": "plan.start", "tid": tid,
                           "title": name or "计划任务", "kind": "thread"})
            self._emit_progress()

    def _emit_progress(self):
        total = len(self.threads)
        done = sum(1 for s in self.threads.values() if s["status"] == "completed")
        cur = next((self.threads[t]["name"] for t in self.order
                    if self.threads[t]["status"] != "completed"), "")
        self.emit({"t": "plan.progress", "done": done, "total": total,
                   "name": cur})
        if total and done == total and not self.plan_ended:
            self.plan_ended = True
            self.emit({"t": "plan.end", "success": True, "text": "任务完成"})

    # ---------- non-SSE JSON bodies (IM envelope) ----------
    def _drain_json(self, key, url, text):
        if not text or not text.lstrip().startswith("{"):
            return
        try:
            obj = json.loads(text)
        except Exception:
            return
        self._scan_conv_names(obj)
        db = obj.get("downlink_body") or {}
        ti = (db.get("get_thread_info_downlink_body") or {}).get("thread_info") or {}
        if ti:
            ext = ti.get("ext") or {}
            if isinstance(ext, str):
                try:
                    ext = json.loads(ext)
                except Exception:
                    ext = {}
            self._on_thread_info(str(ti.get("thread_id") or ""),
                                 ti.get("thread_name") or "",
                                 ext.get("thread_status") or ti.get("thread_status") or "")

    def _scan_conv_names(self, node):
        """Walk a JSON body for objects that pair conversation_id with a
        title — e.g. /im/conversation/info returns
        {conversation_info: {conversation_id, name}}. Learned names are
        announced once via a chat.conv event."""
        stack = [node]
        while stack:
            n = stack.pop()
            if isinstance(n, dict):
                cid = str(n.get("conversation_id") or "")
                name = n.get("name") or n.get("title") or ""
                if (cid and cid != "0" and len(cid) > 5 and name
                        and self.conv_names.get(cid) != name):
                    self.conv_names[cid] = name
                    self.emit({"t": "chat.conv", "cid": cid, "cname": name})
                stack.extend(n.values())
            elif isinstance(n, list):
                stack.extend(n)

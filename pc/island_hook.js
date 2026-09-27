// IslandBridge network hook — forwards Doubao SSE stream chunks in real time.
// Reports via window.__caplog(jsonString) (CDP Runtime binding).
//
// v2: installs via Object.defineProperty so later page code that re-assigns
// window.fetch / XHR.prototype methods gets wrapped instead of overwriting us.
// (Found empirically: Doubao re-wraps fetch after injection, killing a plain
// assignment hook — 0 events reached the daemon.)
(function () {
  if (window.__islandhook_v4) return 'already';
  window.__islandhook_v4 = true;
  const S = (o) => { try { return JSON.stringify(o); } catch (e) { return '{"err":"json"}'; } };
  const emit = (o) => { try { window.__caplog && window.__caplog(S(o)); } catch (e) {} };
  const b64 = (buf) => {
    try {
      let u8 = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
      let s = ''; const CH = 0x8000;
      for (let i = 0; i < u8.length; i += CH)
        s += String.fromCharCode.apply(null, u8.subarray(i, i + CH));
      return btoa(s);
    } catch (e) { return ''; }
  };

  // Endpoints we care about (substring match on url)
  const WATCH = [
    '/chat/completion',
    '/chat/async/chunk_stream',
    '/samantha/chat/async/stream',
    '/im/thread/info',
    '/im/chain/thread_message',
    '/im/chain/single',
    '/im/conversation/info',
    '/samantha/supertask/terminate',
    '/samantha/supertask/reactivate',
  ];
  const watch = (url) => WATCH.some((p) => url.indexOf(p) >= 0);

  // ---------- guarded wrapper: survive later re-assignment ----------
  // wrap(realFn) -> instrumentedFn. The getter always returns the latest
  // instrumented version; if the app assigns a new function, we wrap THAT.
  function guard(obj, prop, wrap) {
    try {
      let wrapped = wrap(obj[prop]);
      const desc = Object.getOwnPropertyDescriptor(obj, prop) || {};
      Object.defineProperty(obj, prop, {
        configurable: true,
        enumerable: desc.enumerable !== undefined ? desc.enumerable : true,
        get() { return wrapped; },
        set(v) { wrapped = wrap(v); },
      });
      return true;
    } catch (e) { return false; }
  }

  // ---------- send-request template + programmatic reply ----------
  // The page signs requests below window.fetch (we see every send twice:
  // unsigned first, then with msToken/a_bogus). Replaying through
  // window.fetch with the UNSIGNED url re-enters that same signing layer,
  // so __ibSendReply = template clone + fresh ids + new text.
  const normHeaders = (h) => {
    try {
      if (!h) return null;
      if (h instanceof Headers) {
        const o = {}; h.forEach((v, k) => { o[k] = v; }); return o;
      }
      if (Array.isArray(h)) {
        const o = {}; for (const kv of h) o[kv[0]] = kv[1]; return o;
      }
      return { ...h };
    } catch (e) { return null; }
  };
  window.__ibSendByCid = window.__ibSendByCid || {};
  function stashSend(url, method, headers, body) {
    try {
      const o = JSON.parse(body);
      const cid = (o.client_meta && o.client_meta.conversation_id) || '';
      const t = { url, method, headers, body };
      window.__ibSendLast = t;
      if (cid) window.__ibSendByCid[cid] = t;
    } catch (e) {}
  }
  const ibUuid = () => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    .replace(/[xy]/g, (c) => {
      const r = Math.random() * 16 | 0;
      return (c === 'x' ? r : (r & 3 | 8)).toString(16);
    });
  // daemon calls this via Runtime.evaluate(awaitPromise) on POST /reply.
  window.__ibSendReply = function (cid, text) {
    try {
      const t = (cid && window.__ibSendByCid[cid]) || window.__ibSendLast;
      if (!t) return Promise.resolve({ ok: false, err: 'no-template' });
      const b = JSON.parse(t.body);
      if (cid && b.client_meta) b.client_meta.conversation_id = cid;
      const m = (b.messages || [])[0] || {};
      m.local_message_id = ibUuid();
      (m.content_block || []).forEach((bl) => {
        bl.block_id = ibUuid();
        if (bl.content && bl.content.text_block)
          bl.content.text_block.text = text;
      });
      if (b.option) {
        b.option.unique_key = ibUuid();
        b.option.create_time_ms = Date.now();
        if (b.option.recovery_option)
          b.option.recovery_option.req_create_time_sec =
            (Date.now() / 1000) | 0;
      }
      const init = { method: t.method || 'POST',
                     credentials: 'include', body: JSON.stringify(b) };
      if (t.headers) init.headers = t.headers;
      return window.fetch(t.url, init)
        .then((r) => ({ ok: r.status < 400, status: r.status }))
        .catch((e) => ({ ok: false, err: String(e) }));
    } catch (e) {
      return Promise.resolve({ ok: false, err: String(e) });
    }
  };

  // ---------- fetch ----------
  function wrapFetch(real) {
    if (typeof real !== 'function' || real.__ib_wrapped) return real;
    const f = function (input, init) {
      const url = (typeof input === 'string') ? input : (input && input.url) || '';
      if (!watch(url)) return real.apply(this, arguments);

      const method = (init && init.method) || (input && input.method) || 'GET';
      const rec = { k: 'req', url, method, t: Date.now() };
      try {
        const b = init && init.body;
        if (typeof b === 'string') rec.reqBody = b.slice(0, 100000);
        const h = (init && init.headers) || (input && input.headers);
        const ho = normHeaders(h);
        if (ho) rec.reqHeaders = ho;
        // remember the send template for __ibSendReply (keep the PRE-SIGN
        // call — a_bogus/msToken urls are one-shot signed replays of it)
        if (rec.reqBody && url.indexOf('/chat/completion') >= 0 &&
            !/[?&](msToken|a_bogus|X-Bogus|_signature)=/.test(url))
          stashSend(url, method, rec.reqHeaders, rec.reqBody);
      } catch (e) {}
      emit({ ...rec, ev: 'open' });

      const p = real.apply(this, arguments);
      p.then((res) => {
        emit({ ...rec, ev: 'headers', status: res.status });
        try {
          const clone = res.clone();
          if (clone.body && clone.body.getReader) {
            const reader = clone.body.getReader();
            let seq = 0;
            (function pump() {
              reader.read().then(({ done, value }) => {
                if (value && value.length)
                  emit({ ...rec, ev: 'chunk', seq: seq++, data: b64(value) });
                if (done) emit({ ...rec, ev: 'done' });
                else pump();
              }).catch(() => emit({ ...rec, ev: 'err' }));
            })();
          } else {
            clone.arrayBuffer().then((ab) => emit({ ...rec, ev: 'body', data: b64(ab) }))
              .catch(() => emit({ ...rec, ev: 'err' }));
          }
        } catch (e) { emit({ ...rec, ev: 'err' }); }
      }).catch((e) => emit({ ...rec, ev: 'err', err: String(e) }));
      return p;
    };
    f.__ib_wrapped = true;
    return f;
  }
  guard(window, 'fetch', wrapFetch);

  // ---------- XMLHttpRequest ----------
  function guardProto(proto, prop, wrap) {
    try {
      let wrapped = wrap(proto[prop]);
      Object.defineProperty(proto, prop, {
        configurable: true,
        get() { return wrapped; },
        set(v) { wrapped = wrap(v); },
      });
      return true;
    } catch (e) { return false; }
  }
  function wrapOpen(real) {
    if (typeof real !== 'function' || real.__ib_wrapped) return real;
    const f = function (m, u) {
      this.__ib_url = u; this.__ib_method = m;
      return real.apply(this, arguments);
    };
    f.__ib_wrapped = true;
    return f;
  }
  function wrapSend(real) {
    if (typeof real !== 'function' || real.__ib_wrapped) return real;
    const f = function (body) {
      const url = this.__ib_url || '';
      if (watch(url)) {
        const rec = { k: 'xhr', url, method: this.__ib_method || 'POST', t: Date.now() };
        if (typeof body === 'string') rec.reqBody = body.slice(0, 100000);
        emit({ ...rec, ev: 'open' });
        let lastLen = 0;
        const poll = () => {
          try {
            const txt = this.responseText;
            if (txt && txt.length > lastLen) {
              const delta = txt.slice(lastLen);
              lastLen = txt.length;
              emit({ ...rec, ev: 'chunk', seq: (rec._s = (rec._s || 0) + 1), text: delta.slice(0, 100000) });
            }
          } catch (e) {}
        };
        this.addEventListener('progress', poll);
        this.addEventListener('load', () => { poll(); emit({ ...rec, ev: 'done', status: this.status }); });
        this.addEventListener('error', () => emit({ ...rec, ev: 'err' }));
      }
      return real.apply(this, arguments);
    };
    f.__ib_wrapped = true;
    return f;
  }
  guardProto(XMLHttpRequest.prototype, 'open', wrapOpen);
  guardProto(XMLHttpRequest.prototype, 'send', wrapSend);

  // ---------- WebSocket (diagnostic: Doubao IM uses a wss protobuf channel)
  function wrapWS(Real) {
    if (typeof Real !== 'function' || Real.__ib_wrapped) return Real;
    const W = function (url, protos) {
      const ws = protos ? new Real(url, protos) : new Real(url);
      emit({ k: 'ws', ev: 'open', url: String(url), t: Date.now() });
      return ws;
    };
    W.prototype = Real.prototype;
    W.CONNECTING = Real.CONNECTING; W.OPEN = Real.OPEN;
    W.CLOSING = Real.CLOSING; W.CLOSED = Real.CLOSED;
    W.__ib_wrapped = true;
    return W;
  }
  guard(window, 'WebSocket', wrapWS);

  // ---------- re-arm: the app may clobber our accessors via its own
  // Object.defineProperty — check every 2s and re-wrap anything lost.
  setInterval(() => {
    try {
      if (!(window.fetch && window.fetch.__ib_wrapped))
        guard(window, 'fetch', wrapFetch);
      if (!(XMLHttpRequest.prototype.send &&
            XMLHttpRequest.prototype.send.__ib_wrapped)) {
        guardProto(XMLHttpRequest.prototype, 'open', wrapOpen);
        guardProto(XMLHttpRequest.prototype, 'send', wrapSend);
      }
      if (!(window.WebSocket && window.WebSocket.__ib_wrapped))
        guard(window, 'WebSocket', wrapWS);
    } catch (e) {}
  }, 2000);

  emit({ k: 'meta', ev: 'hook_installed', url: location.href });
  return 'ok';
})();

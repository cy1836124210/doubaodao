// Doubao network hook — intercepts fetch / XHR / WebSocket / EventSource.
// Reports via window.__caplog(jsonString) (CDP Runtime binding).
(function () {
  if (window.__nethook_installed) return 'already';
  window.__nethook_installed = true;
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
  const hdrs = (h) => { const o = {}; try { new Headers(h).forEach((v, k) => o[k] = v); } catch (e) {} return o; };

  // ---------- fetch ----------
  const ofetch = window.fetch;
  window.fetch = function (input, init) {
    const url = (typeof input === 'string') ? input : (input && input.url) || '';
    const method = (init && init.method) || (input && input.method) || 'GET';
    let reqBody = init && init.body;
    const rec = { k: 'fetch', url, method, reqHeaders: hdrs((init && init.headers) || (input && input.headers)), t: Date.now() };
    try {
      if (reqBody) {
        if (typeof reqBody === 'string') rec.reqBody = reqBody.slice(0, 200000);
        else if (reqBody instanceof ArrayBuffer) rec.reqBodyB64 = b64(reqBody);
        else if (ArrayBuffer.isView(reqBody)) rec.reqBodyB64 = b64(reqBody.buffer);
        else if (reqBody instanceof Blob) reqBody.arrayBuffer().then(ab => emit({ k: 'fetch_body', url, bodyB64: b64(ab) }));
        else rec.reqBodyType = Object.prototype.toString.call(reqBody);
      }
      if (!reqBody && typeof Request !== 'undefined' && input instanceof Request) {
        try {
          const rc = input.clone();
          rc.arrayBuffer().then(ab => {
            rec.reqBodyB64 = b64(ab);
            emit({ k: 'fetch_body', url, t: rec.t, reqBodyB64: rec.reqBodyB64 });
          }).catch(() => {});
        } catch (e) {}
      }
    } catch (e) {}
    const p = ofetch.apply(this, arguments);
    p.then((res) => {
      rec.status = res.status;
      rec.resHeaders = hdrs(res.headers);
      // tee the stream if it's streaming, else clone
      try {
        const ct = res.headers.get('content-type') || '';
        const clone = res.clone();
        if (clone.body && clone.body.getReader) {
          const reader = clone.body.getReader();
          const chunks = [];
          (function pump() {
            reader.read().then(({ done, value }) => {
              if (value) {
                chunks.push(value.length);
                if (rec.stream === undefined) rec.stream = [];
                // store each chunk b64 (cap 200KB total)
                if ((rec._sz || 0) < 200 * 1024) {
                  rec.stream.push(b64(value));
                  rec._sz = (rec._sz || 0) + value.length;
                }
              }
              if (done) {
                rec.done = true;
                emit(rec);
              } else pump();
            }).catch(() => { rec.done = 'err'; emit(rec); });
          })();
        } else {
          clone.arrayBuffer().then((ab) => { rec.body = b64(ab); emit(rec); })
            .catch(() => emit(rec));
        }
      } catch (e) { emit(rec); }
    }).catch((e) => { rec.err = String(e); emit(rec); });
    return p;
  };

  // ---------- XMLHttpRequest ----------
  const OXHR = window.XMLHttpRequest;
  const oopen = OXHR.prototype.open;
  const osend = OXHR.prototype.send;
  const oseth = OXHR.prototype.setRequestHeader;
  OXHR.prototype.open = function (m, u) {
    this.__cap = { k: 'xhr', method: m, url: u, reqHeaders: {}, t: Date.now() };
    return oopen.apply(this, arguments);
  };
  OXHR.prototype.setRequestHeader = function (k, v) {
    if (this.__cap) this.__cap.reqHeaders[k] = v;
    return oseth.apply(this, arguments);
  };
  OXHR.prototype.send = function (body) {
    const cap = this.__cap;
    if (cap) {
      if (body) {
        try {
          if (typeof body === 'string') cap.reqBody = body.slice(0, 100000);
          else if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) cap.reqBodyB64 = b64(body.buffer || body);
        } catch (e) {}
      }
      this.addEventListener('loadend', () => {
        cap.status = this.status;
        try { cap.resHeaders = this.getAllResponseHeaders(); } catch (e) {}
        try {
          if (this.responseType === '' || this.responseType === 'text')
            cap.resBody = (this.responseText || '').slice(0, 200000);
          else if (this.response instanceof ArrayBuffer)
            cap.resBodyB64 = b64(this.response);
        } catch (e) {}
        emit(cap);
      });
    }
    return osend.apply(this, arguments);
  };

  // ---------- WebSocket ----------
  const OWS = window.WebSocket;
  window.WebSocket = function (url, protos) {
    const ws = protos ? new OWS(url, protos) : new OWS(url);
    const rec = { k: 'ws', url, t: Date.now() };
    emit({ ...rec, ev: 'open_attempt' });
    ws.addEventListener('open', () => emit({ ...rec, ev: 'open' }));
    ws.addEventListener('close', (e) => emit({ ...rec, ev: 'close', code: e.code }));
    ws.addEventListener('message', (e) => {
      let d = e.data;
      if (d instanceof ArrayBuffer) d = 'B64:' + b64(d);
      else if (d instanceof Blob) { d.arrayBuffer().then(ab => emit({ ...rec, ev: 'msg', data: 'B64:' + b64(ab) })); return; }
      else if (typeof d === 'string') d = d.slice(0, 50000);
      emit({ ...rec, ev: 'msg', data: d });
    });
    const osend = ws.send;
    ws.send = function (d) {
      let dd = d;
      if (d instanceof ArrayBuffer || ArrayBuffer.isView(d)) dd = 'B64:' + b64(d.buffer || d);
      else if (typeof d === 'string') dd = d.slice(0, 50000);
      emit({ ...rec, ev: 'send', data: dd });
      return osend.apply(this, arguments);
    };
    return ws;
  };
  window.WebSocket.prototype = OWS.prototype;
  window.WebSocket.CONNECTING = OWS.CONNECTING;
  window.WebSocket.OPEN = OWS.OPEN;
  window.WebSocket.CLOSING = OWS.CLOSING;
  window.WebSocket.CLOSED = OWS.CLOSED;

  // ---------- EventSource ----------
  if (window.EventSource) {
    const OES = window.EventSource;
    window.EventSource = function (url, cfg) {
      const es = new OES(url, cfg);
      const rec = { k: 'sse', url, t: Date.now() };
      emit({ ...rec, ev: 'open_attempt' });
      es.addEventListener('message', (e) =>
        emit({ ...rec, ev: 'msg', data: (e.data || '').slice(0, 50000) }));
      es.addEventListener('error', () => emit({ ...rec, ev: 'error' }));
      return es;
    };
    window.EventSource.prototype = OES.prototype;
  }

  emit({ k: 'meta', ev: 'hook_installed', url: location.href });
  return 'ok';
})();

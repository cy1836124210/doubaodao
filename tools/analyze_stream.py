"""Analyze the last N /chat/completion streams' SSE events."""
import json, base64, sys

comps = []
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    if j.get('k') == 'fetch' and 'chat/completion' in str(j.get('url', '')):
        comps.append(j)

print('total completion calls:', len(comps))
j = comps[-1]
st = j.get('stream') or []
raw = b''.join(base64.b64decode(x) for x in st).decode('utf-8', errors='replace')
open(r'E:\doubaoni\capture\last_stream.txt', 'w', encoding='utf-8').write(raw)

events = {}
for block in raw.split('\n\n'):
    ev = None; data = []
    for ln in block.split('\n'):
        if ln.startswith('event:'):
            ev = ln[6:].strip()
        elif ln.startswith('data:'):
            data.append(ln[5:])
    if ev:
        events.setdefault(ev, []).append('\n'.join(data))

for ev, ds in events.items():
    print(f'=== {ev} x{len(ds)} ===')
    seen_key = set()
    for d in ds[:2]:
        try:
            o = json.loads(d)
            # summarize structure
            def keys(o, depth=0):
                if isinstance(o, dict):
                    return {k: keys(v, depth+1) for k, v in o.items()} if depth < 3 else '...'
                if isinstance(o, list):
                    return [keys(o[0], depth+1)] if o else []
                return type(o).__name__
            print(json.dumps(keys(o), ensure_ascii=False)[:2000])
        except Exception:
            print(d[:400])

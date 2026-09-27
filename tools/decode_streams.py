import json, base64, re
hits = 0
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    for ch in (j.get('stream') or []):
        try:
            d = base64.b64decode(ch.get('b64', '')).decode('utf-8', errors='replace')
        except Exception:
            continue
        for kw in ('fin_reason', 'async_task', 'task_id', 'supertask'):
            if kw in d:
                print('=== url:', j.get('url', '')[:100], 'chunk', ch.get('i'))
                for m in re.finditer(re.escape(kw), d):
                    s = m.start()
                    print(d[max(0, s-300):s+300])
                    print('---')
                hits += 1
                break
print('hits:', hits)

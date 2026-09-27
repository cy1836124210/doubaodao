import json
from collections import Counter
c = Counter()
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    u = j.get('url', '')
    if not u.startswith('http'):
        continue
    path = u.split('?')[0].replace('https://', '')
    c[(j.get('method', 'GET'), path)] += 1
for (m, p), n in sorted(c.items(), key=lambda x: -x[1]):
    print(f'{n:5} {m:5} {p}')

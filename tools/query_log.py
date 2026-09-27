"""Query hook.jsonl. Usage: python query_log.py <url_substr> [--full]"""
import json, sys

path = r'E:\doubaoni\capture\hook.jsonl'
sub = sys.argv[1]
full = '--full' in sys.argv
n = 0
for line in open(path, encoding='utf-8'):
    try:
        j = json.loads(line)
    except Exception:
        continue
    if sub not in str(j.get('url', '')):
        continue
    n += 1
    if not full:
        print(f"{j.get('k'):5} {j.get('method',''):4} {j.get('status','')} {j.get('url','')[:140]}")
    else:
        # redact cookies
        h = dict(j.get('reqHeaders') or {})
        for k in list(h):
            if k.lower() in ('cookie',):
                h[k] = h[k][:80] + '...(%d chars)' % len(h[k])
        j['reqHeaders'] = h
        print(json.dumps(j, ensure_ascii=False, indent=1)[:12000])
        print('=' * 60)
print('---', n, 'matches')

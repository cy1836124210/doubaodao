"""Find keyword context in hook.jsonl bodies. Usage: grep_ctx.py <url_substr> <keyword>"""
import json, re, sys
sub, kw = sys.argv[1], sys.argv[2]
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    if sub not in str(j.get('url', '')):
        continue
    blob = json.dumps(j, ensure_ascii=False)
    for m in re.finditer(kw, blob, re.I):
        s = max(0, m.start() - 120)
        print('...' + blob[s:m.start() + 300] + '...')
        print('-' * 60)
        break  # one per record

import json
seen = set()
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    u = j.get('url', '')
    if '/samantha/' in u:
        path = u.split('?')[0]
        key = (j.get('method'), path)
        if key in seen:
            continue
        seen.add(key)
        print('===', j.get('k'), j.get('method'), u[:400])
        if j.get('reqBody'):
            print('REQ:', str(j['reqBody'])[:600])
        if j.get('reqHeaders'):
            print('HDR:', json.dumps(j['reqHeaders'])[:400])
        if j.get('resBody'):
            print('RES:', str(j['resBody'])[:600])
        print()

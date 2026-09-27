import json
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    u = j.get('url', '')
    if '/samantha/thread/' in u or '/im/thread' in u:
        print('===', j.get('k'), j.get('method'), u.split('?')[0])
        rb = j.get('reqBody')
        if rb:
            print('REQ:', str(rb)[:800])
        sb = j.get('resBody')
        if sb:
            print('RES:', str(sb)[:1500])
        print()

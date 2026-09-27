import json
seen = set()
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    if 'supertask/terminate' not in l:
        continue
    try:
        j = json.loads(l)
    except Exception:
        continue
    u = j.get('url', '')
    if 'supertask/terminate' not in u:
        continue
    key = (str(j.get('reqBody') or j.get('fetch_body')), str(j.get('resBody'))[:200])
    if key in seen:
        continue
    seen.add(key)
    print('===', j.get('k'), j.get('method'))
    print('REQ:', j.get('reqBody') or j.get('fetch_body'))
    print('HDR:', json.dumps(j.get('reqHeaders'))[:300])
    print('STATUS:', j.get('status'))
    print('RES:', str(j.get('resBody'))[:800])
    print()

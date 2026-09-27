import json
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    if '/chat/completion' not in j.get('url', ''):
        continue
    body = j.get('reqBody') or j.get('fetch_body')
    if not body:
        continue
    print('URL:', j['url'])
    print('HDR:', json.dumps(j.get('reqHeaders'), ensure_ascii=False))
    try:
        b = json.loads(body)
        print('REQ keys:', list(b.keys()))
        print(json.dumps(b, ensure_ascii=False, indent=1)[:5000])
    except Exception:
        print('REQ:', body[:3000])
    break

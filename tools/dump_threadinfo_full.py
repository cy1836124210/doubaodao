import json
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    if '/im/thread/info' in j.get('url', ''):
        print(json.dumps(j, ensure_ascii=False, indent=1)[:4000])
        break

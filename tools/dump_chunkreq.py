import json, re
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    if 'chunk_stream' in l:
        try:
            j = json.loads(l)
        except Exception:
            continue
        u = j.get('url', '')
        if 'chunk_stream' not in u:
            continue
        print('===', j.get('k'), j.get('method'), u[:150])
        for key in ('reqBody', 'fetch_body', 'body'):
            if j.get(key):
                print(key, ':', str(j[key])[:1200])
        print('stream chunks:', len(j.get('stream') or []))
        print()

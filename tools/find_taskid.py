import json, re
ids = set()
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    blob = json.dumps(j)
    for m in re.finditer(r'"task_id":\s*"?(\d+)"?', blob):
        ids.add(m.group(1))
print('task_ids:', sorted(ids))

# also look for supertask mentions
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    blob = json.dumps(j, ensure_ascii=False)
    if 'supertask' in blob.lower():
        for m in re.finditer(r'.{80}supertask.{120}', blob, re.I):
            print(m.group(0)[:250])
        break

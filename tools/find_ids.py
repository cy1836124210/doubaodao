import json, re
pat = re.compile(r'"(task_id|agent_id|thread_id|conversation_id|bot_id|job_id)":\s*"?([0-9a-zA-Z_-]+)"?')
seen = {}
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    url = j.get('url') or ''
    blob = json.dumps(j)
    for m in pat.finditer(blob):
        k, v = m.group(1), m.group(2)
        seen.setdefault((k, v), url)
for (k, v), u in sorted(seen.items()):
    print(f'{k:16} {v:24} {u[:80]}')

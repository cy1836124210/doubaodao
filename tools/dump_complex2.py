import json, re

def walk(o, out):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == 'complex_task_block':
                out.append(v)
            else:
                walk(v, out)
    elif isinstance(o, list):
        for v in o:
            walk(v, out)
    elif isinstance(o, str):
        if 'complex_task_block' in o:
            try:
                walk(json.loads(o), out)
            except Exception:
                pass

out = []
seen = set()
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    if 'complex_task_block' not in l:
        continue
    try:
        j = json.loads(l)
    except Exception:
        continue
    tmp = []
    walk(j, tmp)
    for t in tmp:
        key = json.dumps(t, sort_keys=True)
        if key not in seen:
            seen.add(key)
            out.append(t)

print(len(out), 'unique blocks')
for t in out:
    print(json.dumps(t, ensure_ascii=False, indent=1)[:4000])
    print('====')

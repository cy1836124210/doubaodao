import re
pat = re.compile(r'\\?"task_id\\?"\s*:\s*\\?"?([0-9a-zA-Z_-]{4,})')
for i, l in enumerate(open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace')):
    for m in pat.finditer(l):
        s = m.start()
        print(f'=== line {i} ===')
        print(l[max(0, s-600):s+300].replace('\\"', '"')[:900])
        print()

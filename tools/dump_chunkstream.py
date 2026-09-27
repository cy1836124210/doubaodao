import json, base64, re, sys

recs = []
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    if 'chunk_stream' in str(j.get('url', '')):
        recs.append(j)

print('chunk_stream calls:', len(recs))
allraw = b''
for j in recs:
    st = j.get('stream') or []
    allraw += b''.join(base64.b64decode(x) for x in st)
raw = allraw.decode('utf-8', errors='replace')
open(r'E:\doubaoni\capture\chunk_stream_all.txt', 'w', encoding='utf-8').write(raw)

# event type counts
evs = re.findall(r'^event: (\S+)', raw, re.M)
from collections import Counter
print(Counter(evs))

# find todo/plan content
for kw in ['TodoWrite', 'todo_list', 'todo', 'plan_step']:
    idxs = [m.start() for m in re.finditer(kw, raw)]
    print(kw, len(idxs))
    if idxs:
        i = idxs[0]
        print(raw[max(0, i - 100):i + 800])
        print('...')

# block types in chunk stream
print('block_types:', sorted(set(re.findall(r'"block_type":(\d+)', raw)), key=int))

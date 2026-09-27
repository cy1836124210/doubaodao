import re
data = open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace').read()
for m in re.finditer(r'async_task', data):
    s = m.start()
    frag = data[max(0, s-200):s+400].replace('\\"', '"')
    print('=== @', s)
    print(frag[:600])
    print()

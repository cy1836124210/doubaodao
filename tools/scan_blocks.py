import json, re
raw = open(r'E:\doubaoni\capture\last_stream.txt', encoding='utf-8').read()
blocks = raw.split('\n\n')
seen_bt = {}
seen_po = {}
for b in blocks:
    for m in re.finditer(r'"block_type":(\d+)', b):
        bt = m.group(1)
        if bt not in seen_bt:
            # capture surrounding context
            s = max(0, m.start() - 50)
            seen_bt[bt] = b[s:m.start() + 600]
    for m in re.finditer(r'"patch_object":(\d+)', b):
        po = m.group(1)
        if po not in seen_po:
            s = max(0, m.start() - 30)
            seen_po[po] = b[s:m.start() + 700]
for k in sorted(seen_bt, key=int):
    print('##### block_type', k)
    print(seen_bt[k][:650])
    print()
for k in sorted(seen_po, key=int):
    print('##### patch_object', k)
    print(seen_po[k][:700])
    print()

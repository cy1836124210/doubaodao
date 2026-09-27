import json, re
raw = open(r'E:\doubaoni\capture\last_stream.txt', encoding='utf-8').read()
for kw in ['plan', 'Plan', 'task_status', 'supertask', 'todo', 'Todo',
           'step', 'terminate', 'interrupt']:
    print(kw, len(re.findall(kw, raw)))
bts = set(re.findall(r'"block_type":(\d+)', raw))
print('block_types:', sorted(bts, key=int))
pos = set(re.findall(r'"patch_object":(\d+)', raw))
print('patch_objects:', sorted(pos, key=int))
pts = set(re.findall(r'"patch_type":(\d+)', raw))
print('patch_types:', sorted(pts, key=int))

import re
# find a fully-unescaped complex_task_block (from resBody, not stream chunk)
data = open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace').read()
# occurrences with single-escaping are inside stream chunks; look for '"complex_task_block"' plain
for m in re.finditer(r'"complex_task_block":\{', data):
    s = m.start()
    frag = data[s:s+4000]
    # print until matching-ish end
    print(frag[:3500])
    print('\n========\n')

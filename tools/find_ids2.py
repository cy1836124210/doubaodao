import re
pat = re.compile(r'\\?"(task_id|agent_id|thread_id|conversation_id|bot_id|job_id|chat_id)\\?"\s*:\s*\\?"?([0-9a-zA-Z_-]{4,})')
seen = {}
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    for m in pat.finditer(l):
        k, v = m.group(1), m.group(2)
        if (k, v) not in seen:
            seen[(k, v)] = l[:0]
print(len(seen))
for (k, v) in sorted(seen):
    print(f'{k:16} {v}')

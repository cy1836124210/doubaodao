import json
WANT = ['/im/conversation/info', '/im/message/chain_by_block', '/im/chain/single',
        '/im/chain/recent_conv', '/im/conversation/abstract', '/im/conversation/batch_get',
        '/im/message/mark_conv_read', '/im/conversation/modify', '/im/project/list',
        '/im/group/list', '/im/message/send_rate_limit', '/im/chain/thread_message']
seen = set()
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    u = j.get('url', '')
    path = next((w for w in WANT if w in u), None)
    if not path:
        continue
    req = j.get('reqBody')
    if not req:
        continue
    try:
        rq = json.loads(req)
    except Exception:
        continue
    cmd = rq.get('cmd')
    key = (path, cmd)
    if key in seen:
        continue
    seen.add(key)
    print('###', j.get('method'), path, 'cmd=', cmd)
    print('REQ:', req[:900])
    res = j.get('resBody')
    if res:
        print('RES:', res[:1200])
    print()

"""Attach to the Doubao chat page and dump all network traffic to JSONL.

Usage: python capture_network.py [url_substring]
Writes E:\\doubaoni\\capture\\network.jsonl
"""
import json, sys, time, base64
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

OUT = r'E:\doubaoni\capture\network.jsonl'
FILTER = sys.argv[1] if len(sys.argv) > 1 else ''

target = find_target(url_substr='doubao-chat/chat')
if not target:
    print('chat page not found'); sys.exit(1)

c = CDP(browser_ws())
sess = c.attach(target['id'])

reqs = {}   # requestId -> record
lock_file = open(OUT, 'a', encoding='utf-8')

def write(rec):
    lock_file.write(json.dumps(rec, ensure_ascii=False) + '\n')
    lock_file.flush()

def interesting(url):
    if not FILTER:
        return True
    return FILTER in url

def on_event(m):
    meth = m.get('method', '')
    p = m.get('params', {})
    if meth == 'Network.requestWillBeSent':
        r = p['request']
        if not interesting(r['url']):
            return
        reqs[p['requestId']] = {'url': r['url'], 'method': r['method'],
                                'headers': r.get('headers'),
                                'postData': r.get('postData'),
                                'hasPostData': r.get('hasPostData'),
                                'type': p.get('type'),
                                'ts': p.get('wallTime')}
        write({'ev': 'request', 'id': p['requestId'],
               'url': r['url'], 'method': r['method'],
               'headers': r.get('headers'),
               'postData': r.get('postData'),
               'hasPostData': r.get('hasPostData')})
        print('>>', r['method'], r['url'][:140])
    elif meth == 'Network.responseReceived':
        rid = p['requestId']
        if rid not in reqs:
            return
        resp = p['response']
        write({'ev': 'response', 'id': rid, 'url': resp['url'],
               'status': resp['status'], 'mime': resp.get('mimeType'),
               'headers': resp.get('headers')})
        print('<<', resp['status'], resp.get('mimeType', ''), resp['url'][:120])
    elif meth == 'Network.loadingFinished':
        rid = p['requestId']
        if rid not in reqs:
            return
        try:
            body = c.call('Network.getResponseBody', {'requestId': rid},
                          session_id=sess, timeout=10)
            data = body.get('body', '')
            write({'ev': 'body', 'id': rid, 'url': reqs[rid]['url'],
                   'b64': body.get('base64Encoded', False),
                   'body': data[:200000]})
            print('== body', len(data), 'bytes for', reqs[rid]['url'][:100])
        except Exception as e:
            write({'ev': 'body_err', 'id': rid, 'err': str(e)})
        del reqs[rid]
    elif meth == 'Network.webSocketCreated':
        write({'ev': 'ws_created', 'url': p['request'].get('url'),
               'id': p['requestId']})
        print('WS>>', p['request'].get('url'))
    elif meth == 'Network.webSocketFrameSent':
        write({'ev': 'ws_send', 'id': p['requestId'],
               'data': p['response'].get('payloadData', '')[:5000]})
    elif meth == 'Network.webSocketFrameReceived':
        write({'ev': 'ws_recv', 'id': p['requestId'],
               'data': p['response'].get('payloadData', '')[:5000]})

c.on_event = on_event
c.call('Network.enable', session_id=sess)
print('attached to', target['url'], '— capturing. Ctrl+C to stop.')
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    pass
finally:
    lock_file.close()
    c.close()

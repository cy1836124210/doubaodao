"""Capture request postData via CDP Network domain on the chat page."""
import json, sys, time, threading
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

WANT = sys.argv[1] if len(sys.argv) > 1 else 'chat/completion'
SECS = int(sys.argv[2]) if len(sys.argv) > 2 else 30

t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])

eq = []
lock = threading.Lock()
def on_ev(m):
    with lock:
        eq.append(m)
c.on_event = on_ev

c.call('Network.enable', session_id=sess)
print('listening for', WANT, '... send the message now')
deadline = time.time() + SECS
seen = set()
while time.time() < deadline:
    with lock:
        evs, eq[:] = eq[:], []
    for m in evs:
        if m.get('method') != 'Network.requestWillBeSent':
            continue
        p = m['params']
        r = p['request']
        if WANT not in r['url'] or p['requestId'] in seen:
            continue
        seen.add(p['requestId'])
        print('==>', r['method'], r['url'][:160])
        print('headers:', json.dumps(r.get('headers', {}), ensure_ascii=False)[:1500])
        if p.get('hasPostData') or r.get('postData'):
            try:
                pd = c.call('Network.getRequestPostData',
                            {'requestId': p['requestId']}, session_id=sess)
                print('POSTDATA:', pd.get('postData', '')[:6000])
            except Exception as e:
                print('postData err', e, '| inline:', (r.get('postData') or '')[:2000])
    time.sleep(0.05)
c.close()

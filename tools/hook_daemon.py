"""Inject the network hook into every Doubao page/frame target and log to hook.jsonl.

Event dispatch happens on the main thread (reader thread only buffers),
so CDP calls inside handlers don't deadlock.
"""
import json, sys, time, threading
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws

OUT = r'E:\doubaoni\capture\hook.jsonl'
HOOK_JS = open(r'E:\doubaoni\tools\hook.js', encoding='utf-8').read()

c = CDP(browser_ws())
out = open(OUT, 'a', encoding='utf-8')
sessions = {}   # sessionId -> targetId
targets = {}
eq = []         # event queue
eq_lock = threading.Lock()

def log(rec):
    out.write(json.dumps(rec, ensure_ascii=False) + '\n')
    out.flush()

def instrument(sess, tid):
    try:
        c.call('Runtime.enable', session_id=sess)
    except Exception:
        pass
    try:
        c.call('Runtime.addBinding', {'name': '__caplog'}, session_id=sess)
    except Exception as e:
        print('bind err', tid, e)
    try:
        c.call('Page.enable', session_id=sess)
        c.call('Page.addScriptToEvaluateOnNewDocument',
               {'source': HOOK_JS}, session_id=sess)
    except Exception:
        pass
    try:
        r = c.call('Runtime.evaluate',
                   {'expression': HOOK_JS, 'returnByValue': True},
                   session_id=sess)
        print('hooked', tid[:8], '->', r.get('result', {}).get('value'))
    except Exception as e:
        print('eval err', tid[:8], e)

def attach_and_instrument(t):
    try:
        sid = c.attach(t['targetId'])
    except Exception as e:
        print('attach fail', t['type'], t.get('url', '')[:60], e)
        return
    sessions[sid] = t['targetId']
    targets[t['targetId']] = t
    print('attached', t['type'], t.get('url', '')[:100])
    if t['type'] in ('page', 'iframe', 'worker', 'shared_worker',
                     'service_worker', 'other'):
        instrument(sid, t['targetId'])

def handle(m):
    meth = m.get('method')
    p = m.get('params', {})
    sid = m.get('sessionId')
    if meth == 'Target.attachedToTarget':
        t = p['targetInfo']
        targets[t['targetId']] = t
        sessions[p['sessionId']] = t['targetId']
        print('auto-attached', t['type'], t['url'][:100])
        if t['type'] in ('page', 'iframe', 'worker', 'shared_worker',
                         'service_worker', 'other'):
            instrument(p['sessionId'], t['targetId'])
    elif meth == 'Target.detachedFromTarget':
        sessions.pop(p.get('sessionId'), None)
    elif meth == 'Runtime.bindingCalled':
        if p.get('name') != '__caplog':
            return
        tid = sessions.get(sid, '?')
        turl = targets.get(tid, {}).get('url', '')
        try:
            payload = json.loads(p['payload'])
        except Exception:
            payload = {'raw': p['payload']}
        payload['_target'] = tid
        payload['_turl'] = turl
        log(payload)
        k = payload.get('k')
        url = payload.get('url', '')[:120]
        if k == 'fetch':
            print('F', payload.get('method'), payload.get('status'), url)
        elif k == 'xhr':
            print('X', payload.get('method'), payload.get('status'), url)
        elif k in ('ws', 'sse'):
            print(k.upper(), payload.get('ev'), url)
        else:
            print('.', k, payload.get('ev', ''))

# reader thread: just buffer events
def reader_on_event(m):
    with eq_lock:
        eq.append(m)
c.on_event = reader_on_event

try:
    c.call('Target.setAutoAttach',
           {'autoAttach': True, 'waitForDebuggerOnStart': False,
            'flatten': True}, timeout=15)
except Exception as e:
    print('autoAttach failed:', e)

res = c.call('Target.getTargets')
for t in res['targetInfos']:
    attach_and_instrument(t)

print('daemon running; logging to', OUT)
try:
    while True:
        while True:
            with eq_lock:
                if not eq:
                    break
                m = eq.pop(0)
            try:
                handle(m)
            except Exception as e:
                print('handle err', e)
        time.sleep(0.05)
except KeyboardInterrupt:
    pass
finally:
    out.close()
    c.close()

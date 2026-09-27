"""Network-domain sniffer on the Doubao chat page: show where chat traffic
actually goes (HTTP vs WebSocket) for ~45s."""
import sys, time, base64, threading
sys.path.insert(0, '../tools'); sys.path.insert(0, '../pylibs')
from cdp import CDP, browser_ws

c = CDP(browser_ws(9222))
targets = c.call('Target.getTargets')['targetInfos']
tid = [t['targetId'] for t in targets if 'doubao-chat/chat/' in t.get('url', '')][0]
sid = c.attach(tid)
c.call('Network.enable', {}, session_id=sid)

ws_ids = {}
stop = threading.Event()

def preview(b):
    txt = ''.join(chr(x) if 32 <= x < 127 else '.' for x in b)
    return txt[:150]

def on_event(m):
    meth, p = m.get('method'), m.get('params', {})
    if m.get('sessionId') != sid:
        return
    if meth == 'Network.requestWillBeSent':
        r = p['request']
        print('HTTP >>', r['method'], r['url'][:110])
    elif meth == 'Network.webSocketCreated':
        ws_ids[p['requestId']] = p['url']
        print('WS open', p['url'][:100])
    elif meth in ('Network.webSocketFrameSent',
                  'Network.webSocketFrameReceived'):
        d = p['response']['payloadData']
        raw = base64.b64decode(d) if p['response'].get('opcodeData') or True else b''
        try:
            raw = d.encode('utf-8')          # payloadData is str (b64 if base64Encoded)
        except Exception:
            pass
        # CDP gives payloadData base64-encoded when base64Encoded flag set,
        # else utf-8 text. Try both.
        try:
            raw = base64.b64decode(d)
        except Exception:
            raw = d.encode('utf-8', 'replace')
        marks = [k for k in ('text_block', 'thinking_block', 'complex_task',
                             'STREAM', 'patch_op', 'message') if
                 k.encode() in raw]
        tag = 'WStx' if 'Sent' in meth else 'WSrx'
        print(f'{tag} {len(raw)}B', 'marks=' + ','.join(marks) if marks else '',
              preview(raw)[:100])
    elif meth == 'Network.responseReceived':
        print('HTTP <<', p['response']['status'],
              p['response'].get('mimeType', ''), p['response']['url'][:100])

c.on_event = on_event
print('sniffing 45s — send a message in Doubao now…')
time.sleep(45)
stop.set()
c.close()

import json, sys, time
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])
r = c.call('Runtime.evaluate', {'expression':
    "(function(){var b=document.querySelector('.send-btn-wrapper button')||"
    "document.querySelector('.send-btn-wrapper');if(!b)return 'no';"
    "var r=b.getBoundingClientRect();return JSON.stringify({x:r.x+r.width/2,y:r.y+r.height/2})})()",
    'returnByValue': True}, session_id=sess)
pos = json.loads(r['result']['value'])
print('btn pos', pos)
for typ, extra in [('mousePressed', {'button': 'left', 'clickCount': 1}),
                   ('mouseReleased', {'button': 'left', 'clickCount': 1})]:
    c.call('Input.dispatchMouseEvent',
           {'type': typ, 'x': pos['x'], 'y': pos['y'], **extra},
           session_id=sess)
print('clicked')
c.close()

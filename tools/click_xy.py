import sys, json, time
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target
x, y = float(sys.argv[1]), float(sys.argv[2])
t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])
for typ in ('mousePressed', 'mouseReleased'):
    c.call('Input.dispatchMouseEvent',
           {'type': typ, 'x': x, 'y': y, 'button': 'left', 'clickCount': 1},
           session_id=sess)
print('clicked', x, y)
c.close()

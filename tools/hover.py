import sys, time
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target
x, y = float(sys.argv[1]), float(sys.argv[2])
t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])
c.call('Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y},
       session_id=sess)
time.sleep(float(sys.argv[3]) if len(sys.argv) > 3 else 1.0)
import base64
r = c.call('Page.captureScreenshot', {'format': 'png'}, session_id=sess)
open(r'E:\doubaoni\capture\hover.png', 'wb').write(base64.b64decode(r['data']))
print('done')
c.close()

import sys
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target
t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
r = c.call('Target.activateTarget', {'targetId': t['id']})
print('activated', t['id'])
c.close()

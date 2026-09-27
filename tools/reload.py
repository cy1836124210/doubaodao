import json, sys
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target
t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])
c.call('Page.enable', session_id=sess)
c.call('Page.reload', {'ignoreCache': False}, session_id=sess)
print('reloaded', t['url'])
c.close()

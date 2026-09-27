import json, sys
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws

c = CDP(browser_ws())
c.call('Target.setDiscoverTargets', {'discover': True})
res = c.call('Target.getTargets')
for t in res['targetInfos']:
    print(f"{t['type']:15} {t['targetId'][:12]}  {t.get('title','')[:50]:50}  {t.get('url','')[:110]}")
c.close()

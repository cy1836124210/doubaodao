"""One-off Runtime.evaluate on a target. Usage: python eval.py <url_substr> <expr_file_or_string>"""
import json, sys
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

sub = sys.argv[1] if len(sys.argv) > 1 else 'doubao-chat/chat'
expr = sys.argv[2] if len(sys.argv) > 2 else 'location.href'
if expr.endswith('.js'):
    expr = open(expr, encoding='utf-8').read()

t = find_target(url_substr=sub)
if not t:
    print('target not found'); sys.exit(1)
c = CDP(browser_ws())
sess = c.attach(t['id'])
r = c.call('Runtime.evaluate', {'expression': expr, 'returnByValue': True,
                                'awaitPromise': True}, session_id=sess)
print(json.dumps(r, ensure_ascii=False, indent=1)[:8000])
c.close()

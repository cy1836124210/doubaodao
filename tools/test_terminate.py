import sys, json
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

# real URL template from a captured samantha call
URL = None
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    if '/samantha/user/setting/get' in j.get('url', ''):
        URL = j['url'].replace('/samantha/user/setting/get', '/samantha/supertask/terminate')
        break
print('URL:', URL[:120])

tid = sys.argv[1] if len(sys.argv) > 1 else '56356499033802498'

JS = '''
async () => {
  const r = await fetch(%s, {
    method: 'POST',
    headers: {'Content-Type': 'application/json; encoding=utf-8', 'Agw-Js-Conv': 'str', 'Accept': 'application/json, text/plain, */*'},
    credentials: 'include',
    body: JSON.stringify({task_id: %s})
  });
  const t = await r.text();
  return JSON.stringify({status: r.status, body: t.slice(0, 1000)});
}''' % (json.dumps(URL), json.dumps(tid))

t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])
r = c.call('Runtime.evaluate', {'expression': '(' + JS + ')()', 'awaitPromise': True, 'returnByValue': True}, session_id=sess)
print(json.dumps(r, ensure_ascii=False, indent=1)[:3000])
c.close()

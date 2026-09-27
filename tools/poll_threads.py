import sys, json, time
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

THREADS = ['56356036522376194', '56356499033802498', '56355216887980802',
           '56354662769794306', '56358312752963330', '56347854500559618']

JS = '''
async () => {
  const out = [];
  for (const tid of %s) {
    const r = await fetch('https://www.doubao.com/im/thread/info?aid=582478&device_platform=web&samantha_web=1', {
      method: 'POST',
      headers: {'Content-Type': 'application/json', 'Agw-Js-Conv': 'str'},
      credentials: 'include',
      body: JSON.stringify({cmd:3400, uplink_body:{get_thread_info_uplink_body:{thread_id:tid}}, sequence_id: crypto.randomUUID(), channel:2, version:'1'})
    });
    const j = await r.json();
    const ti = j && j.downlink_body && j.downlink_body.get_thread_info_downlink_body && j.downlink_body.get_thread_info_downlink_body.thread_info;
    out.push({tid, status: ti && ti.ext && ti.ext.thread_status, name: ti && ti.thread_name, code: j.status_code});
  }
  return JSON.stringify(out);
}''' % json.dumps(THREADS)

t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])
r = c.call('Runtime.evaluate', {'expression': '(' + JS + ')()', 'awaitPromise': True, 'returnByValue': True}, session_id=sess)
print(json.dumps(r, ensure_ascii=False, indent=1)[:3000])
c.close()

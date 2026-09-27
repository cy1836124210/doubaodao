import sys, time
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])
c.call('Runtime.evaluate', {'expression':
    "document.querySelector('[contenteditable=true]').focus()"},
    session_id=sess)
time.sleep(0.3)
for ev in [
    {'type': 'keyDown', 'key': 'Enter', 'code': 'Enter',
     'windowsVirtualKeyCode': 13, 'nativeVirtualKeyCode': 13,
     'text': '\r', 'unmodifiedText': '\r'},
    {'type': 'keyUp', 'key': 'Enter', 'code': 'Enter',
     'windowsVirtualKeyCode': 13, 'nativeVirtualKeyCode': 13},
]:
    c.call('Input.dispatchKeyEvent', ev, session_id=sess)
    time.sleep(0.05)
time.sleep(1)
r = c.call('Runtime.evaluate', {'expression':
    "document.querySelector('[contenteditable=true]').innerText",
    'returnByValue': True}, session_id=sess)
print('editor now:', repr(r.get('result', {}).get('value')))
c.close()

"""Send a chat message in the Doubao desktop UI via CDP input pipeline."""
import json, sys, time
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

TEXT = sys.argv[1] if len(sys.argv) > 1 else '你好，请用一句话介绍你自己'

t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])

# focus the editor
r = c.call('Runtime.evaluate', {'expression':
    "(function(){var e=document.querySelector('[contenteditable=true]');"
    "if(!e)return 'no-editor';e.focus();return 'focused'})()",
    'returnByValue': True}, session_id=sess)
print('focus:', r.get('result', {}).get('value'))
time.sleep(0.3)

# insert text through the real input pipeline
c.call('Input.insertText', {'text': TEXT}, session_id=sess)
time.sleep(0.5)

# press Enter to send
for typ in ('rawKeyDown', 'keyUp'):
    c.call('Input.dispatchKeyEvent', {
        'type': typ, 'key': 'Enter', 'code': 'Enter',
        'windowsVirtualKeyCode': 13, 'nativeVirtualKeyCode': 13,
    }, session_id=sess)
print('sent:', TEXT)
c.close()

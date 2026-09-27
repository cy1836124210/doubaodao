"""Click an element by its exact text. Usage: click_text.py '新工作任务'"""
import sys, json, time
sys.path.insert(0, r'E:\doubaoni\tools')
from cdp import CDP, browser_ws, find_target

TEXT = sys.argv[1]
t = find_target(url_substr='doubao-chat/chat')
c = CDP(browser_ws())
sess = c.attach(t['id'])
expr = """
(function(){
  var want = %s;
  var els = document.querySelectorAll('span,div,button,a');
  for (var i=0;i<els.length;i++){
    var e=els[i];
    var t=e.innerText?e.innerText.trim():'';
    if (t===want){
      var r=e.getBoundingClientRect();
      if(r.width===0) continue;
      return JSON.stringify({x:r.x+r.width/2,y:r.y+r.height/2,tag:e.tagName,cls:(e.className||'').toString().slice(0,60)});
    }
  }
  return 'nf';
})()
""" % json.dumps(TEXT)
r = c.call('Runtime.evaluate', {'expression': expr, 'returnByValue': True},
           session_id=sess)
v = r['result']['value']
print('found:', v)
if v == 'nf':
    c.close(); sys.exit(1)
pos = json.loads(v)
for typ in ('mousePressed', 'mouseReleased'):
    c.call('Input.dispatchMouseEvent',
           {'type': typ, 'x': pos['x'], 'y': pos['y'], 'button': 'left',
            'clickCount': 1}, session_id=sess)
print('clicked at', pos['x'], pos['y'])
c.close()

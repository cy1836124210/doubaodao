import json, base64, sys

comps = []
for l in open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8'):
    try:
        j = json.loads(l)
    except Exception:
        continue
    if j.get('k') == 'fetch' and 'chat/completion' in str(j.get('url', '')):
        comps.append(j)

print('completion calls:', len(comps))
if not comps:
    sys.exit()
j = comps[-1]
h = dict(j.get('reqHeaders') or {})
for k in list(h):
    if k.lower() == 'cookie':
        h[k] = h[k][:40] + '...(%d)' % len(h[k])
print('URL:', j['url'][:250])
print('HEADERS:', json.dumps(h, ensure_ascii=False, indent=1))
rb = j.get('reqBody')
if rb:
    print('REQBODY:')
    print(rb[:5000])
elif j.get('reqBodyB64'):
    print('REQBODY(b64 decoded):')
    print(base64.b64decode(j['reqBodyB64'])[:500])
else:
    print('no body captured; keys:', list(j.keys()))

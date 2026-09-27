import re
targets = ['56544991295958786', '56544991295959554']
for i, l in enumerate(open(r'E:\doubaoni\capture\hook.jsonl', encoding='utf-8', errors='replace')):
    if 'monitor_browser' in l or 'slardar' in l.lower():
        continue
    for t in targets:
        p = l.find(t)
        if p >= 0:
            print(f'=== line {i} id={t} ===')
            # find url field
            um = re.search(r'"url":\s*"([^"]+)"', l[:p+2000])
            print('url:', um.group(1) if um else '?')
            print(l[max(0, p-800):p+400].replace('\\"', '"')[:1200])
            print()
            break

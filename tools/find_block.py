import re, sys
bt = sys.argv[1] if len(sys.argv) > 1 else '10006'
fn = sys.argv[2] if len(sys.argv) > 2 else r'E:\doubaoni\capture\chunk_stream_all.txt'
raw = open(fn, encoding='utf-8').read()
m = re.search(r'"block_type":' + bt + r'\b', raw)
if m:
    i = m.start()
    print(raw[max(0, i - 80):i + 2500])
else:
    print('not found')

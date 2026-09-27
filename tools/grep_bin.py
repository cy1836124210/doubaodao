"""Find string context in binary file. Usage: grep_bin.py <file> <pattern> [ctx] [max]"""
import re, sys

f, pat = sys.argv[1], sys.argv[2]
ctx = int(sys.argv[3]) if len(sys.argv) > 3 else 120
maxn = int(sys.argv[4]) if len(sys.argv) > 4 else 20

data = open(f, 'rb').read()
# work on latin-1 view to keep byte offsets
s = data.decode('latin-1', errors='replace')
seen = set()
n = 0
for m in re.finditer(re.escape(pat), s):
    i = m.start()
    frag = s[max(0, i - ctx):i + ctx]
    # keep only printable-ish
    frag = ''.join(c if 32 <= ord(c) < 127 or ord(c) > 255 else '.' for c in frag)
    key = frag.strip()
    if key in seen:
        continue
    seen.add(key)
    n += 1
    print(f'--- @{i} ---')
    print(frag)
    if n >= maxn:
        break
print(f'total uniq shown {n}')

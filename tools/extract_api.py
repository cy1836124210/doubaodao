"""Extract all API endpoint paths + HTTP methods from biz.pak generated client code."""
import re, sys

f = r'E:\doubaoni\Doubao\app\local_webcontents\biz\biz.pak'
data = open(f, 'rb').read()
s = data.decode('latin-1', errors='replace')

# pattern: genBaseURL("PATH") ... method = "METHOD"
eps = {}
for m in re.finditer(r'genBaseURL\(\\?"([^"\\]+)\\?"\)', s):
    path = m.group(1)
    seg = s[m.end():m.end() + 400]
    mm = re.search(r'method = \\?"(GET|POST|PUT|DELETE|PATCH)\\?"', seg)
    meth = mm.group(1) if mm else '?'
    eps[path] = meth

out = open(r'E:\doubaoni\api_endpoints_full.txt', 'w', encoding='utf-8')
for p in sorted(eps):
    out.write(f'{eps[p]:6} {p}\n')
out.close()
print(len(eps), 'endpoints ->', r'E:\doubaoni\api_endpoints_full.txt')

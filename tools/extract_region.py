import sys
f, off, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else 2000
data = open(f, 'rb').read()
s = data[off:off+n].decode('latin-1', errors='replace')
print(s.encode('utf-8', errors='replace').decode('utf-8'))

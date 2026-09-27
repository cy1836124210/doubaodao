import zipfile, re, sys

pats = re.compile(rb"[\x20-\x7e\xe4-\xe9][\x20-\x7e\xe4-\xe9\x80-\xbf]{5,}")
keys = ["callinguid", "calling uid", "caller", "no_permission", "uid mismatch",
        "self-reported", "hascaller", "checkpermission", "publish_activity",
        "not bound", "untrusted"]

def scan(path, label, extra_descr=False):
    print("=" * 20, label)
    try:
        z = zipfile.ZipFile(path)
    except Exception as e:
        print("  ERR", e); return
    seen = set()
    for n in z.namelist():
        if not (n.endswith(".dex") or n.endswith(".jar")):
            continue
        try:
            data = z.read(n)
        except Exception:
            continue
        if data[:2] == b"PK":
            continue
        for m in pats.finditer(data):
            s = m.group().decode("latin1")
            low = s.lower()
            if extra_descr and ("island" in low and s.startswith("Lcom/")):
                key = s
            elif any(k in low for k in keys):
                key = s
            else:
                continue
            if key not in seen:
                seen.add(key)
    for s in sorted(seen):
        print("  ", s)

scan(r"D:\aiwork\doubaoni\dev\jar\astraflow.apk", "astraflow.apk (island host)", True)
scan(r"D:\aiwork\doubaoni\android\app\libs\astraisland-client.aar",
     "astraisland-client.aar", True)

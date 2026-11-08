"""Copy the hidden FAT32 of an R36S-H backup image file by file onto a mounted drive.

Used by `r36s-h-tool.ps1 -Action CloneSmall` to move the system to a SMALLER card.

- Keeps the lowercase flags of 8.3 names (FAT "NT case" byte 0x08/0x10). Without this the
  Linux system on the card can't find /etc, /bin, ... and the device hangs at the boot logo.
- Copies the whole system (everything that is not a game).
- Game folders: only games whose file name or menu title matches GAMES (regex, case
  insensitive). Systems without a match keep their smallest game, so no menu list is empty.
- FILELIST.CSV and IMAGES\\*.png are reduced to the copied games.

usage: clone_small.py <image> <fat32-offset-bytes> <target-root> <games-regex|-> [--dry-run]
"""
import ctypes, os, re, struct, sys, time

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
img, voff, target, games_rx = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
dry = "--dry-run" in sys.argv
WANT = None if games_rx in ("", "-") else re.compile(games_rx, re.I)
GAME_EXT = {".zip", ".iso", ".img", ".bin", ".cue", ".pbp", ".chd", ".a26", ".fba"}

f = open(img, "rb")
def rd(o, n): f.seek(o); return f.read(n)
bs = rd(voff, 512)
bps, spc, res, nf = struct.unpack("<HBHB", bs[11:17])
fsz, rootcl = struct.unpack("<I", bs[36:40])[0], struct.unpack("<I", bs[44:48])[0]
fat_off = voff + res * bps; data_off = fat_off + nf * fsz * bps; csz = bps * spc
fat = rd(fat_off, fsz * bps)

def nxt(c): return struct.unpack_from("<I", fat, c * 4)[0] & 0x0FFFFFFF
def chain(c):
    out = []
    while 2 <= c < 0x0FFFFFF8 and len(out) < 10_000_000:
        out.append(c); c = nxt(c)
    return out
def short_name(e):
    base = e[0:8].decode("latin1").rstrip(); ext = e[8:11].decode("latin1").rstrip()
    if base[:1] == "\x05": base = "\xe5" + base[1:]
    if e[12] & 0x08: base = base.lower()
    if e[12] & 0x10: ext = ext.lower()
    return base + ("." + ext if ext else "")
def listdir(cl):
    data = b"".join(rd(data_off + (c - 2) * csz, csz) for c in chain(cl))
    out, lfn = [], []
    for i in range(0, len(data), 32):
        e = data[i:i + 32]
        if e[0] == 0: break
        if e[0] == 0xE5: lfn = []; continue
        if e[11] == 0x0F:
            lfn.insert(0, (e[1:11] + e[14:26] + e[28:32]).decode("utf-16-le", "ignore").split("\0")[0]); continue
        name = "".join(lfn) or short_name(e); lfn = []
        if name in (".", "..") or e[11] & 0x08: continue
        c = (struct.unpack("<H", e[20:22])[0] << 16) | struct.unpack("<H", e[26:28])[0]
        out.append((name, bool(e[11] & 0x10), c, struct.unpack("<I", e[28:32])[0], e[11]))
    return out
def read_file(cl, size):
    out = bytearray()
    for c in chain(cl):
        out += rd(data_off + (c - 2) * csz, csz)
        if len(out) >= size: break
    return bytes(out[:size])

files, dirs = [], []
def walk(cl, rel):
    for name, isdir, c, size, attr in listdir(cl):
        p = f"{rel}/{name}" if rel else name
        if p.lower() == "system volume information": continue
        if isdir: dirs.append(p); walk(c, p)
        else: files.append((p, c, size, attr))
walk(rootcl, "")

# system folders = top-level folders that contain a FILELIST.CSV
systems = {p.split("/")[0] for p, c, s, a in files if p.count("/") == 1 and p.lower().endswith("/filelist.csv")}
def is_game(p): return p.count("/") == 1 and p.split("/")[0] in systems and os.path.splitext(p)[1].lower() in GAME_EXT

keep, bases = set(), {}
for sysname in systems:
    games = [(p, s) for p, c, s, a in files if is_game(p) and p.split("/")[0] == sysname]
    if not games: continue
    titles = {}
    for p, c, s, a in files:
        if p.split("/")[0] == sysname and p.count("/") == 1 and p.lower().endswith(".csv"):
            for line in read_file(c, s).decode("utf-8", "replace").lstrip("﻿").split("\r\n"):
                cols = line.split(",")
                if len(cols) >= 2: titles[cols[0].strip().lower()] = cols[1]
    chosen = [(p, s) for p, s in games if WANT and (WANT.search(p.split("/")[1]) or WANT.search(titles.get(p.split("/")[1].lower(), "")))]
    if not chosen: chosen = [min(games, key=lambda x: x[1])]
    for p, s in chosen: keep.add(p)
    bases[sysname] = {os.path.splitext(p.split("/")[1])[0].lower() for p, s in chosen}

def wanted(p):
    parts = p.split("/")
    if parts[0] not in systems: return True
    if is_game(p): return p in keep
    if len(parts) == 3 and parts[1].lower() == "images":
        return os.path.splitext(parts[2])[0].lower() in bases.get(parts[0], set())
    return True
files = [x for x in files if wanted(x[0])]
total = sum(s for _, _, s, _ in files)
for p in sorted(keep): print("  game:", p, flush=True)
print(f"FILES {len(files)} BYTES {total}", flush=True)
if dry: sys.exit(0)

for d in dirs: os.makedirs(os.path.join(target, d), exist_ok=True)
done, t0, last = 0, time.time(), -1
for p, c, size, attr in files:
    data = read_file(c, size)
    parts = p.split("/")
    if parts[0] in systems and len(parts) == 2 and p.lower().endswith(".csv"):
        text = data.decode("utf-8", "replace"); bom = text.startswith("﻿")
        names = {os.path.basename(x).lower() for x in keep if x.split("/")[0] == parts[0]}
        lines = [l for l in text.lstrip("﻿").split("\r\n") if l.split(",")[0].strip().lower() in names]
        listed = {l.split(",")[0].strip().lower() for l in lines}
        for n in sorted(names - listed):
            t = os.path.splitext(n)[0]; lines.append(f"{n},{t},{t}")
        data = (("﻿" if bom else "") + "\r\n".join(lines) + "\r\n").encode("utf-8")
    out = os.path.join(target, p)
    with open(out, "wb") as o: o.write(data)
    if attr & 0x07:
        ctypes.windll.kernel32.SetFileAttributesW(out, (attr & 0x27) or 0x80)
    done += size
    pct = done * 100 // max(total, 1)
    if pct // 5 != last:
        last = pct // 5
        print(f"PROGRESS {pct} {done} {total} {done / max(time.time() - t0, 0.001) / 1048576:.1f}", flush=True)
print("DONE", flush=True)

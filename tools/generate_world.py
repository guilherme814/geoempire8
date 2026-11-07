#!/usr/bin/env python3
"""Gera data/world.json: mapa procedural de provincias (diagrama de Voronoi) do GeoEmpire.

Uso:
    python3 tools/generate_world.py [seed] [--preview mapa.png] [--out caminho.json]

O jogo so depende do formato abaixo; um mapa real (ou desenhado a mao) pode
substituir data/world.json sem mexer no codigo GDScript.

  map_size   [largura, altura]
  countries  [{id, name, color, capital}]
  provinces  [{id, name, poly[x0,y0,x1,y1,...], edges[...], sea[...], terrain,
               resource, coastal, pop, owner}]
  edges[i] = id da provincia vizinha do lado do segmento i -> i+1 (-1 = mar/borda)
  sea      = ids de provincias ligadas por rota maritima (estreitos)
"""
import argparse
import heapq
import json
import math
import os
import random
import struct
import zlib
from collections import defaultdict, deque

ap = argparse.ArgumentParser()
ap.add_argument("seed", nargs="?", type=int, default=1850)
ap.add_argument("--preview", help="grava um PNG de pre-visualizacao")
ap.add_argument(
    "--out",
    default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "world.json"),
)
opt = ap.parse_args()

SEED = opt.seed
W, H = 2400, 1200
SPACING = 70
NUM_COUNTRIES = 14
LAND_THRESHOLD = 0.12
MIN_COMPONENT = 3

rng = random.Random(SEED)


# --------------------------------------------------------------------------
# Ruido de valor (para continentes, relevo e umidade)
# --------------------------------------------------------------------------
def _hash(ix, iy, s):
    n = (ix * 374761393 + iy * 668265263 + s * 982451653) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    n ^= n >> 16
    return (n & 0xFFFF) / 65535.0


def _smooth(t):
    return t * t * (3 - 2 * t)


def vnoise(x, y, s):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    a, b = _hash(ix, iy, s), _hash(ix + 1, iy, s)
    c, d = _hash(ix, iy + 1, s), _hash(ix + 1, iy + 1, s)
    u, v = _smooth(fx), _smooth(fy)
    return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v


def fbm(x, y, s, octaves=4):
    total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
    for o in range(octaves):
        total += vnoise(x * freq, y * freq, s + o * 17) * amp
        norm += amp
        amp *= 0.5
        freq *= 2
    return total / norm


# cx, cy, rx, ry (fracoes do mapa)
CONTINENTS = [
    (0.21, 0.46, 0.19, 0.36),
    (0.55, 0.56, 0.22, 0.34),
    (0.84, 0.40, 0.11, 0.30),
    (0.46, 0.14, 0.10, 0.11),
]


def land_value(x, y):
    nx, ny = x / W, y / H
    base = -1.0
    for cx, cy, rx, ry in CONTINENTS:
        d = math.sqrt(((nx - cx) / rx) ** 2 + ((ny - cy) / ry) ** 2)
        base = max(base, 1.0 - d)
    return base + (fbm(x / 380.0, y / 380.0, SEED) - 0.5) * 0.95


# --------------------------------------------------------------------------
# Voronoi por recorte de semiplanos (poligonos convexos, com rotulo de vizinho)
# --------------------------------------------------------------------------
def clip(poly, si, sj, label):
    xi, yi = si
    xj, yj = sj
    nx, ny = xj - xi, yj - yi
    c = (xj * xj + yj * yj - xi * xi - yi * yi) / 2.0
    out = []
    n = len(poly)
    for k in range(n):
        ax, ay, la = poly[k]
        bx, by, _ = poly[(k + 1) % n]
        fa = nx * ax + ny * ay - c
        fb = nx * bx + ny * by - c
        if fa <= 0:
            out.append((ax, ay, la))
            if fb > 0:
                t = fa / (fa - fb)
                out.append((ax + t * (bx - ax), ay + t * (by - ay), label))
        elif fb <= 0:
            t = fa / (fa - fb)
            out.append((ax + t * (bx - ax), ay + t * (by - ay), la))
    return out


def voronoi(sites):
    cell = SPACING * 3.5
    grid = defaultdict(list)
    for i, (x, y) in enumerate(sites):
        grid[(int(x // cell), int(y // cell))].append(i)
    cells = []
    for i, (sx, sy) in enumerate(sites):
        poly = [(0.0, 0.0, -1), (float(W), 0.0, -1), (float(W), float(H), -1), (0.0, float(H), -1)]
        cx, cy = int(sx // cell), int(sy // cell)
        cand = []
        for gx in range(cx - 1, cx + 2):
            for gy in range(cy - 1, cy + 2):
                cand.extend(j for j in grid.get((gx, gy), []) if j != i)
        cand.sort(key=lambda j: (sites[j][0] - sx) ** 2 + (sites[j][1] - sy) ** 2)
        for j in cand:
            d2 = (sites[j][0] - sx) ** 2 + (sites[j][1] - sy) ** 2
            maxr2 = max((vx - sx) ** 2 + (vy - sy) ** 2 for vx, vy, _ in poly)
            if d2 / 4.0 > maxr2:
                break
            poly = clip(poly, (sx, sy), sites[j], j)
        cells.append(poly)
    return cells


def centroid(poly):
    a = cx = cy = 0.0
    n = len(poly)
    for k in range(n):
        x0, y0, _ = poly[k]
        x1, y1, _ = poly[(k + 1) % n]
        cr = x0 * y1 - x1 * y0
        a += cr
        cx += (x0 + x1) * cr
        cy += (y0 + y1) * cr
    a *= 0.5
    if abs(a) < 1e-9:
        return poly[0][0], poly[0][1]
    return cx / (6 * a), cy / (6 * a)


def clean(poly):
    out = []
    n = len(poly)
    for k in range(n):
        x0, y0, lab = poly[k]
        x1, y1, _ = poly[(k + 1) % n]
        if abs(x0 - x1) < 0.05 and abs(y0 - y1) < 0.05:
            continue
        out.append((x0, y0, lab))
    return out


# --------------------------------------------------------------------------
# Sitios (grade com jitter) + relaxamento de Lloyd
# --------------------------------------------------------------------------
cols = int(W / SPACING) + 1
rows = int(H / SPACING) + 1
sites = []
for j in range(rows):
    for i in range(cols):
        x = (i + 0.5) * W / cols + rng.uniform(-0.38, 0.38) * SPACING
        y = (j + 0.5) * H / rows + rng.uniform(-0.38, 0.38) * SPACING
        sites.append((x, y))

cells = voronoi(sites)
relaxed = []
for (sx, sy), poly in zip(sites, cells):
    cx, cy = centroid(poly)
    relaxed.append((sx + (cx - sx) * 0.7, sy + (cy - sy) * 0.7))
sites = relaxed
cells = [clean(p) for p in voronoi(sites)]

# --------------------------------------------------------------------------
# Terra x mar e remocao de ilhotas minusculas
# --------------------------------------------------------------------------
is_land = [land_value(x, y) > LAND_THRESHOLD for x, y in sites]


def land_adjacency():
    adj = defaultdict(set)
    for i, poly in enumerate(cells):
        if not is_land[i]:
            continue
        for _, _, lab in poly:
            if lab >= 0 and is_land[lab]:
                adj[i].add(lab)
    return adj


adj = land_adjacency()
seen = set()
for i in range(len(sites)):
    if not is_land[i] or i in seen:
        continue
    comp, queue = [i], deque([i])
    seen.add(i)
    while queue:
        cur = queue.popleft()
        for n in adj[cur]:
            if n not in seen:
                seen.add(n)
                comp.append(n)
                queue.append(n)
    if len(comp) < MIN_COMPONENT:
        for s in comp:
            is_land[s] = False

adj = land_adjacency()
land_sites = [i for i in range(len(sites)) if is_land[i]]
pid_of = {s: p for p, s in enumerate(land_sites)}
P = len(land_sites)

nbrs = {pid_of[s]: sorted(pid_of[n] for n in adj[s]) for s in land_sites}
cent = {pid_of[s]: sites[s] for s in land_sites}

# componentes (em ids de provincia)
comp_of, comps = {}, []
for p in range(P):
    if p in comp_of:
        continue
    members, queue = [p], deque([p])
    comp_of[p] = len(comps)
    while queue:
        cur = queue.popleft()
        for n in nbrs[cur]:
            if n not in comp_of:
                comp_of[n] = len(comps)
                members.append(n)
                queue.append(n)
    comps.append(members)


def dist(a, b):
    return math.hypot(cent[a][0] - cent[b][0], cent[a][1] - cent[b][1])


# --------------------------------------------------------------------------
# Paises: sementes espalhadas por continente + crescimento aleatorio
# --------------------------------------------------------------------------
big = [c for c in comps if len(c) >= 6]
total_big = sum(len(c) for c in big)
counts = [max(1, round(NUM_COUNTRIES * len(c) / total_big)) for c in big]
while sum(counts) > NUM_COUNTRIES:
    k = max(range(len(counts)), key=lambda i: counts[i])
    counts[k] -= 1
while sum(counts) < NUM_COUNTRIES:
    k = max(range(len(counts)), key=lambda i: len(big[i]) / counts[i])
    counts[k] += 1

seeds = []
for members, k in zip(big, counts):
    chosen = [rng.choice(members)]
    while len(chosen) < k:
        nxt = max(members, key=lambda m: min(dist(m, c) for c in chosen))
        chosen.append(nxt)
    seeds.extend(chosen)

owner = {}
heap = []
for ci, sp in enumerate(seeds):
    heapq.heappush(heap, (0.0, ci, sp))
while heap:
    cost, ci, p = heapq.heappop(heap)
    if p in owner:
        continue
    owner[p] = ci
    for q in nbrs[p]:
        if q not in owner:
            heapq.heappush(heap, (cost + 1.0 + rng.random() * 0.9, ci, q))
for p in range(P):  # ilhas pequenas: pais mais proximo
    if p not in owner:
        near = min((q for q in owner), key=lambda q: dist(p, q))
        owner[p] = owner[near]

# --------------------------------------------------------------------------
# Nomes, relevo, recursos, populacao
# --------------------------------------------------------------------------
PALETTE = [
    "#c0504d", "#4f81bd", "#9bbb59", "#f2a33a", "#8064a2", "#4bacc6", "#d97ba0",
    "#7f9f4e", "#c9b04a", "#5b7fa6", "#b86b3f", "#6aa7a0", "#a65e8f", "#8c8c5a",
]
C_A = ["Va", "Ka", "Ro", "Mer", "Tal", "Bor", "Ze", "Lu", "Ar", "Sa", "Ni", "Dro", "Ve", "Kor", "Is", "Thar"]
C_B = ["len", "ra", "dan", "mir", "vek", "to", "sa", "gor", "lon", "bar", "nor", "ven"]
C_C = ["ia", "ia", "ora", "enia", "land", "ica", "mark", "stan"]
P_A = ["Alt", "Bel", "Cor", "Dun", "El", "Fal", "Gran", "Hor", "Ist", "Jar", "Kel", "Lor", "Mar",
       "Nor", "Os", "Pra", "Quel", "Riv", "Sol", "Tor", "Ul", "Ven", "Wes", "Yor", "Zan"]
P_B = ["burg", "by", "dal", "ford", "gard", "heim", "mont", "polis", "stad", "ton", "vale", "wick",
       "a", "ia", "en", "or"]

used_names = set()


def unique_name(make):
    for _ in range(200):
        n = make()
        if n not in used_names:
            used_names.add(n)
            return n
    n = make() + str(len(used_names))
    used_names.add(n)
    return n


country_names = [
    unique_name(lambda: rng.choice(C_A) + rng.choice(C_B) + rng.choice(C_C)) for _ in range(NUM_COUNTRIES)
]

BASE_POP = {"plains": 150, "forest": 70, "hills": 85, "mountains": 40, "desert": 28}


def pick_terrain(x, y):
    elev = fbm(x / 300.0 + 50, y / 300.0 + 50, SEED + 101)
    moist = fbm(x / 350.0 - 20, y / 350.0 - 20, SEED + 202)
    if elev > 0.60:
        return "mountains"
    if elev > 0.54:
        return "hills"
    if moist < 0.38:
        return "desert"
    if moist > 0.58:
        return "forest"
    return "plains"


def pick_resource(terrain, coastal):
    r = rng.random()
    if terrain == "plains":
        if coastal and r > 0.75:
            return "fish"
        return "grain" if r < 0.6 else "cotton"
    if terrain == "forest":
        return "timber" if r < 0.8 else "grain"
    if terrain == "hills":
        if coastal and r > 0.85:
            return "fish"
        return "coal" if r < 0.45 else ("iron" if r < 0.8 else "grain")
    if terrain == "mountains":
        return "iron" if r < 0.5 else ("gold" if r < 0.62 else "coal")
    return "salt" if r < 0.6 else ("gold" if r < 0.75 else "iron")


provinces = []
for s in land_sites:
    pid = pid_of[s]
    poly = cells[s]
    edges = []
    for _, _, lab in poly:
        edges.append(pid_of[lab] if lab >= 0 and is_land[lab] else -1)
    coastal = any(e == -1 for e in edges)
    x, y = sites[s]
    terrain = pick_terrain(x, y)
    pop = BASE_POP[terrain] * rng.uniform(0.6, 1.4) * (1.15 if coastal else 1.0)
    flat = []
    for vx, vy, _ in poly:
        flat.extend([round(vx, 1), round(vy, 1)])
    provinces.append(
        {
            "id": pid,
            "name": unique_name(lambda: rng.choice(P_A) + rng.choice(P_B)),
            "poly": flat,
            "edges": edges,
            "sea": [],
            "terrain": terrain,
            "resource": pick_resource(terrain, coastal),
            "coastal": coastal,
            "pop": round(pop, 1),
            "owner": owner[pid],
        }
    )

# rotas maritimas entre continentes / ilhas
coastal_ids = [p["id"] for p in provinces if p["coastal"]]
pairs = []
for i, a in enumerate(coastal_ids):
    for b in coastal_ids[i + 1:]:
        if comp_of[a] != comp_of[b]:
            d = dist(a, b)
            if d < 9 * SPACING:
                pairs.append((d, a, b))
pairs.sort()
sea = defaultdict(list)
per_pair = defaultdict(int)
for d, a, b in pairs:
    key = (min(comp_of[a], comp_of[b]), max(comp_of[a], comp_of[b]))
    limit = 3 if d < 3.6 * SPACING else 1
    if per_pair[key] >= limit or (limit == 1 and per_pair[key] > 0):
        continue
    if len(sea[a]) >= 2 or len(sea[b]) >= 2:
        continue
    sea[a].append(b)
    sea[b].append(a)
    per_pair[key] += 1
for p in provinces:
    p["sea"] = sorted(sea[p["id"]])

# capitais: provincia mais proxima do centro de cada pais
countries = []
for ci in range(NUM_COUNTRIES):
    members = [p for p in range(P) if owner[p] == ci]
    mx = sum(cent[m][0] for m in members) / len(members)
    my = sum(cent[m][1] for m in members) / len(members)
    cap = min(members, key=lambda m: math.hypot(cent[m][0] - mx, cent[m][1] - my))
    countries.append({"id": ci, "name": country_names[ci], "color": PALETTE[ci % len(PALETTE)], "capital": cap})

world = {"map_size": [W, H], "countries": countries, "provinces": provinces}
os.makedirs(os.path.dirname(os.path.abspath(opt.out)), exist_ok=True)
with open(opt.out, "w", encoding="utf-8") as fh:
    json.dump(world, fh, ensure_ascii=False, separators=(",", ":"))

print(f"seed={SEED} provincias={P} paises={NUM_COUNTRIES} "
      f"continentes={len(big)} ilhas={len(comps) - len(big)} "
      f"rotas_maritimas={sum(len(v) for v in sea.values()) // 2}")
for c in countries:
    n = sum(1 for p in provinces if p["owner"] == c["id"])
    print(f"  {c['id']:2d} {c['name']:<12} {n:3d} provincias")


# --------------------------------------------------------------------------
# Pre-visualizacao opcional (PNG sem dependencias)
# --------------------------------------------------------------------------
def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * width * 3:(y + 1) * width * 3])

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


if opt.preview:
    S = 0.6
    pw, ph = int(W * S), int(H * S)
    buf = bytearray([22, 49, 79] * (pw * ph))
    TERRAIN_TINT = {"plains": 0, "forest": -22, "hills": -10, "mountains": -38, "desert": 28}

    def put(x, y, col):
        if 0 <= x < pw and 0 <= y < ph:
            i = (y * pw + x) * 3
            buf[i:i + 3] = bytes(col)

    def line(x0, y0, x1, y1, col):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for k in range(steps + 1):
            t = k / steps
            put(int(x0 + (x1 - x0) * t), int(y0 + (y1 - y0) * t), col)

    for p in provinces:
        pts = [(p["poly"][i] * S, p["poly"][i + 1] * S) for i in range(0, len(p["poly"]), 2)]
        h = countries[p["owner"]]["color"].lstrip("#")
        base = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
        tint = TERRAIN_TINT[p["terrain"]]
        col = [max(0, min(255, c + tint)) for c in base]
        xs, ys = [q[0] for q in pts], [q[1] for q in pts]
        for yy in range(int(min(ys)), int(max(ys)) + 1):
            for xx in range(int(min(xs)), int(max(xs)) + 1):
                inside = True
                n = len(pts)
                for k in range(n):
                    ax, ay = pts[k]
                    bx, by = pts[(k + 1) % n]
                    if (bx - ax) * (yy + 0.5 - ay) - (by - ay) * (xx + 0.5 - ax) < 0:
                        inside = False
                        break
                if inside:
                    put(xx, yy, col)
    for p in provinces:
        pts = [(p["poly"][i] * S, p["poly"][i + 1] * S) for i in range(0, len(p["poly"]), 2)]
        n = len(pts)
        for k in range(n):
            nb = p["edges"][k]
            ax, ay = pts[k]
            bx, by = pts[(k + 1) % n]
            if nb == -1 or provinces[nb]["owner"] != p["owner"]:
                line(ax, ay, bx, by, (10, 10, 10))
            else:
                line(ax, ay, bx, by, (60, 60, 60))
    write_png(opt.preview, pw, ph, buf)
    print("preview:", opt.preview)

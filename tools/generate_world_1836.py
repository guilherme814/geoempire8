#!/usr/bin/env python3
"""Gera data/world.json: mapa-múndi de 1836 a partir do Natural Earth (domínio público).

Uso:
    python3 tools/generate_world_1836.py --ne <pasta com ne_10m_admin_1_states_provinces.geojson> \
        [--out data/world.json] [--preview mapa.png] [--seed 1836] [--cache pasta]

Pipeline:
  1. projeta (Miller) e rasteriza as divisões admin-1 -> dono de 1836 por pixel
  2. limpa ilhotas/lagos, sorteia sítios (densidade por região) e faz Voronoi restrito ao dono
  3. cada componente conexo vira uma província (polígono simples, pode ser côncavo)
  4. extrai arcos de fronteira compartilhados (topologia exata) e simplifica (Douglas-Peucker)
  5. terreno/recurso/população por heurísticas históricas e geográficas

Formato (lido por scripts/core/game_state.gd):
  map_size [w, h]; projection {...}; countries [{id,tag,name,color,capital,pop}]
  provinces [{id,name,poly[x0,y0,...],edges[...],terrain,resource,coastal,pop,owner,center[x,y],area,lon,lat}]
  edges[i] = id da província vizinha do segmento i -> i+1 (-1 = mar). owner -1 = terra sem dono.
"""
import argparse
import json
import math
import os
import random
import sys
import time
from collections import Counter, defaultdict

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
from skimage import measure

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import world1836_data as D  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--ne", required=True)
ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "world.json"))
ap.add_argument("--preview")
ap.add_argument("--seed", type=int, default=1836)
ap.add_argument("--cache")
ap.add_argument("--width", type=int, default=4096)
ap.add_argument("--tol", type=float, default=1.1, help="tolerância Douglas-Peucker (px)")
ap.add_argument("--density", type=float, default=1.0,
                help="multiplicador do espaçamento entre províncias (>1 = menos províncias, mapa mais leve)")
ap.add_argument("--voronoi", action="store_true",
                help="usa células Voronoi no lugar das fronteiras administrativas originais")
ap.add_argument("--min-frac", type=float, default=0.2,
                help="divisões menores que isso x área nominal são fundidas à vizinha do mesmo país")
ap.add_argument("--wild-mult", type=float, default=6.0,
                help="multiplicador do tamanho das províncias em terras sem dono")
ap.add_argument("--max-frac", type=float, default=3.0,
                help="divisões maiores que isso x área nominal são subdivididas")
opt = ap.parse_args()

T0 = time.time()


def log(msg):
    print("[%5.1fs] %s" % (time.time() - T0, msg), flush=True)


# ---------------------------------------------------------------------------
# Projeção Miller
# ---------------------------------------------------------------------------
W = opt.width
K = W / (2 * math.pi)
LAT_TOP, LAT_BOT = 78.0, -56.0


def miller_y(lat_deg):
    return 1.25 * np.log(np.tan(np.pi / 4 + 0.4 * np.radians(lat_deg)))


Y_TOP = float(miller_y(LAT_TOP))
Y_BOT = float(miller_y(LAT_BOT))
H = int(round((Y_TOP - Y_BOT) * K))
R_OVER_K = 6371.0 / K


def project(lon, lat):
    lon = np.asarray(lon, dtype=np.float64)
    lat = np.clip(np.asarray(lat, dtype=np.float64), -85, 85)
    return (lon + 180.0) / 360.0 * W, (Y_TOP - miller_y(lat)) * K


def unproject(x, y):
    ym = Y_TOP - np.asarray(y, dtype=np.float64) / K
    lat = np.degrees((np.arctan(np.exp(ym / 1.25)) - np.pi / 4) / 0.4)
    lon = np.asarray(x, dtype=np.float64) / W * 360.0 - 180.0
    return lon, lat


def km_per_px(lat_deg):
    p = np.radians(lat_deg)
    return R_OVER_K * np.sqrt(np.cos(p) * np.cos(0.8 * p))


# ---------------------------------------------------------------------------
# 1. Rasterização das divisões admin-1
# ---------------------------------------------------------------------------
def ring_area_centroid(ring):
    a = 0.0
    cx = cy = 0.0
    n = len(ring)
    for i in range(n - 1):
        x0, y0 = ring[i][0], ring[i][1]
        x1, y1 = ring[i + 1][0], ring[i + 1][1]
        cr = x0 * y1 - x1 * y0
        a += cr
        cx += (x0 + x1) * cr
        cy += (y0 + y1) * cr
    a *= 0.5
    if abs(a) < 1e-12:
        return 0.0, ring[0][0], ring[0][1]
    return abs(a), cx / (6 * a), cy / (6 * a)


def load_features():
    path = os.path.join(opt.ne, "ne_10m_admin_1_states_provinces.geojson")
    with open(path) as f:
        data = json.load(f)
    feats = []
    for ft in data["features"]:
        g = ft["geometry"]
        if g is None:
            continue
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        rings = [p[0] for p in polys if p and len(p[0]) >= 4]
        if not rings:
            continue
        best = max(rings, key=lambda r: ring_area_centroid(r)[0])
        area, cx, cy = ring_area_centroid(best)
        total = sum(ring_area_centroid(r)[0] for r in rings)
        pr = ft["properties"]
        feats.append({
            "a3": pr.get("adm0_a3") or "", "name": pr.get("name") or pr.get("name_en") or "?",
            "region": pr.get("region"), "rings": rings, "lon": cx, "lat": cy, "area": total,
        })
    feats.sort(key=lambda f: -f["area"])
    return feats


def rasterize(feats):
    img = Image.new("I", (W, H), 0)
    dr = ImageDraw.Draw(img)
    for i, f in enumerate(feats, start=1):
        for ring in f["rings"]:
            arr = np.asarray(ring, dtype=np.float64)
            xs, ys = project(arr[:, 0], arr[:, 1])
            pts = list(zip(xs.tolist(), ys.tolist()))
            if len(pts) >= 3:
                dr.polygon(pts, fill=i, outline=i)
    return np.array(img, dtype=np.int32)


cache = opt.cache
if cache:
    os.makedirs(cache, exist_ok=True)

log("lendo Natural Earth admin-1")
feats = load_features()
state_index = {k: i + 1 for i, k in enumerate(D.STATE_KEYS)}
lut = np.zeros(len(feats) + 1, dtype=np.int16)
lut[0] = -1
unmapped = Counter()
for i, f in enumerate(feats, start=1):
    key = D.owner_for(f["a3"], f["name"], f["region"], f["lon"], f["lat"])
    lut[i] = state_index[key] if key else 0
    if key is None:
        unmapped[f["a3"]] += 1
log("%d divisões; sem dono por país: %s" % (len(feats), unmapped.most_common(14)))

log("rasterizando %dx%d" % (W, H))
adm = rasterize(feats)

# ---------------------------------------------------------------------------
# 2. Limpeza: lagos pequenos viram terra; ilhotas somem
# ---------------------------------------------------------------------------
sea = adm == 0
lab, n = ndi.label(sea)
sizes = ndi.sum(sea, lab, range(1, n + 1))
border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])).tolist())
fill = np.zeros(n + 1, dtype=bool)
for i in range(1, n + 1):
    if i not in border and sizes[i - 1] < 1500:
        fill[i] = True
fill_mask = fill[lab]
if fill_mask.any():
    _, inds = ndi.distance_transform_edt(sea, return_indices=True)
    adm[fill_mask] = adm[inds[0][fill_mask], inds[1][fill_mask]]
log("lagos preenchidos: %d px" % int(fill_mask.sum()))

land = adm > 0
lab_l = measure.label(land, connectivity=1)
cnt = np.bincount(lab_l.ravel())
small = cnt < 14
small[0] = False
adm[small[lab_l]] = 0
land = adm > 0
own = lut[adm]
log("pixels de terra: %d" % int(land.sum()))

# ---------------------------------------------------------------------------
# 3. Sítios por densidade + Voronoi restrito ao dono
# ---------------------------------------------------------------------------
rng = np.random.default_rng(opt.seed)
pyrng = random.Random(opt.seed)


def density_km(lon, lat):
    km = np.full(lon.shape, float(D.DENSITY_DEFAULT_KM))
    for (x0, y0, x1, y1, v) in D.DENSITY_RECTS:
        m = (lon >= x0) & (lon <= x1) & (lat >= y0) & (lat <= y1)
        km[m] = v
    return km * opt.density


ys_l, xs_l = np.nonzero(land)
ncand = min(len(xs_l), 500000)
pick = rng.choice(len(xs_l), size=ncand, replace=False)
cx = xs_l[pick].astype(np.float64) + 0.5
cy = ys_l[pick].astype(np.float64) + 0.5
clon, clat = unproject(cx, cy)
rpx = density_km(clon, clat) / km_per_px(clat)
keep = rng.random(ncand) < (rpx.min() / rpx) ** 2
cx, cy, rpx = cx[keep], cy[keep], rpx[keep]
order = rng.permutation(len(cx))
cx, cy, rpx = cx[order], cy[order], rpx[order]

CELL = 16.0
grid = defaultdict(list)
sites = []   # (x, y, r)
rmax = float(rpx.max())
for x, y, r in zip(cx.tolist(), cy.tolist(), rpx.tolist()):
    gx, gy = int(x // CELL), int(y // CELL)
    reach = int(((r + rmax) * 0.5) // CELL) + 1
    ok = True
    for ix in range(gx - reach, gx + reach + 1):
        if not ok:
            break
        for iy in range(gy - reach, gy + reach + 1):
            for j in grid.get((ix, iy), ()):
                sx, sy, sr = sites[j]
                lim = 0.5 * (r + sr) * 0.92
                if (sx - x) ** 2 + (sy - y) ** 2 < lim * lim:
                    ok = False
                    break
            if not ok:
                break
    if ok:
        grid[(gx, gy)].append(len(sites))
        sites.append((x, y, r))
log("sítios por densidade: %d" % len(sites))

sites_arr = np.array([(s[0], s[1]) for s in sites])
site_own = own[np.clip(sites_arr[:, 1].astype(int), 0, H - 1), np.clip(sites_arr[:, 0].astype(int), 0, W - 1)]
extra = []
for k in range(0, len(D.STATES) + 1):
    mask = own == k
    if not mask.any():
        continue
    labk = measure.label(mask, connectivity=1)
    counts = np.bincount(labk.ravel())
    has = set()
    for (sx, sy), so in zip(sites_arr.tolist(), site_own.tolist()):
        if so == k:
            has.add(int(labk[min(int(sy), H - 1), min(int(sx), W - 1)]))
    objs_k = ndi.find_objects(labk)
    for c in range(1, len(counts)):
        if counts[c] < 14 or c in has:
            continue
        sl = objs_k[c - 1]
        sub = np.pad(labk[sl] == c, 1)
        dist = ndi.distance_transform_edt(sub)
        py, px = np.unravel_index(int(np.argmax(dist)), dist.shape)
        extra.append((sl[1].start + px - 1 + 0.5, sl[0].start + py - 1 + 0.5, k))
log("sítios extras (componentes sem sítio): %d" % len(extra))
for x, y, k in extra:
    sites.append((x, y, 0.0))
sites_arr = np.array([(s[0], s[1]) for s in sites])
site_own = own[np.clip(sites_arr[:, 1].astype(int), 0, H - 1), np.clip(sites_arr[:, 0].astype(int), 0, W - 1)]

# distorção de domínio para fronteiras orgânicas
def noise_field(scale, seed):
    r = np.random.default_rng(seed)
    small_n = r.standard_normal((H // scale + 3, W // scale + 3))
    small_n = ndi.gaussian_filter(small_n, 1.6)
    small_n /= small_n.std() + 1e-9
    big = ndi.zoom(small_n, scale, order=1)
    return big[:H, :W].astype(np.float32)


nx_f = noise_field(16, opt.seed + 1)
ny_f = noise_field(16, opt.seed + 2)
AMP = 5.0

prov = np.full((H, W), -1, dtype=np.int32)
for k in range(0, len(D.STATES) + 1):
    idx = np.nonzero(site_own == k)[0]
    ys, xs = np.nonzero(own == k)
    if len(xs) == 0:
        continue
    if len(idx) == 0:
        idx = np.array([int(np.argmin(np.hypot(sites_arr[:, 0] - xs.mean(), sites_arr[:, 1] - ys.mean())))])
    tree = cKDTree(sites_arr[idx])
    q = np.stack([xs + 0.5 + nx_f[ys, xs] * AMP, ys + 0.5 + ny_f[ys, xs] * AMP], axis=1)
    _, nn = tree.query(q)
    prov[ys, xs] = idx[nn]
log("voronoi por dono concluído")


def real_border_labels():
    """Província = divisão administrativa real (admin-1 do Natural Earth).

    - divisões minúsculas são fundidas à vizinha do mesmo país com maior fronteira comum;
    - divisões gigantes (Sibéria, Amazonas...) são subdivididas pelos sítios Voronoi;
    - as fronteiras que sobram são, em quase toda parte, as originais.
    """
    import heapq
    nu = len(feats) + 1
    cnt = np.bincount(adm[land], minlength=nu).astype(np.int64)
    ys, xs = np.nonzero(land)
    ids = adm[ys, xs]
    sx = np.bincount(ids, weights=xs, minlength=nu)
    sy = np.bincount(ids, weights=ys, minlength=nu)
    cxu = sx / np.maximum(cnt, 1) + 0.5
    cyu = sy / np.maximum(cnt, 1) + 0.5
    lon_u, lat_u = unproject(cxu, cyu)
    r_u = density_km(np.asarray(lon_u), np.asarray(lat_u)) / km_per_px(np.asarray(lat_u))
    nominal = (r_u ** 2).astype(np.float64)       # área-alvo de uma província (px^2)
    # Terra sem dono em 1836 (interior da África, Ártico...): territórios grandes, como nos mapas da época
    nominal[lut[:nu] == 0] *= opt.wild_mult

    # adjacência entre divisões do MESMO país (contagem de pixels de fronteira)
    nbrs = defaultdict(Counter)
    for a_, b_ in ((adm[:, :-1], adm[:, 1:]), (adm[:-1, :], adm[1:, :])):
        m = (a_ != b_) & (a_ > 0) & (b_ > 0)
        aa, bb = a_[m], b_[m]
        same = lut[aa] == lut[bb]
        aa, bb = aa[same].astype(np.int64), bb[same].astype(np.int64)
        key = np.minimum(aa, bb) * nu + np.maximum(aa, bb)
        u, c = np.unique(key, return_counts=True)
        for k_, c_ in zip(u.tolist(), c.tolist()):
            lo, hi = divmod(k_, nu)
            nbrs[lo][hi] += c_
            nbrs[hi][lo] += c_

    parent = list(range(nu))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    garea = cnt.astype(np.float64)
    gnom = nominal.copy()
    heap = [(garea[i], i) for i in range(1, nu) if cnt[i] > 0 and garea[i] < opt.min_frac * gnom[i]]
    heapq.heapify(heap)
    merged = 0
    while heap:
        ar, i = heapq.heappop(heap)
        if find(i) != i or ar != garea[i] or not nbrs[i]:
            continue
        j = max(nbrs[i].items(), key=lambda kv: (kv[1], -kv[0]))[0]
        # i entra em j
        parent[i] = j
        tot = garea[i] + garea[j]
        gnom[j] = (gnom[i] * garea[i] + gnom[j] * garea[j]) / tot
        garea[j] = tot
        for m_, c_ in nbrs[i].items():
            if m_ == j:
                continue
            nbrs[m_].pop(i, None)
            nbrs[m_][j] += c_
            nbrs[j][m_] += c_
        nbrs[j].pop(i, None)
        nbrs[i] = Counter()
        merged += 1
        if garea[j] < opt.min_frac * gnom[j]:
            heapq.heappush(heap, (garea[j], j))
    log("divisões administrativas: %d | fundidas (muito pequenas): %d" % (int((cnt > 0).sum()), merged))

    root_lut = np.array([find(i) for i in range(nu)], dtype=np.int32)
    g = np.where(land, root_lut[adm], 0).astype(np.int32)
    labels = np.where(land, g, -1).astype(np.int32)

    # subdivide divisões gigantes com os sítios de densidade
    roots = [i for i in range(1, nu) if find(i) == i and cnt[i] > 0 or (find(i) == i and garea[i] > 0)]
    big = [r for r in roots if garea[r] > opt.max_frac * gnom[r]]
    site_adm = adm[np.clip(sites_arr[:, 1].astype(int), 0, H - 1), np.clip(sites_arr[:, 0].astype(int), 0, W - 1)]
    site_root = root_lut[site_adm]
    objs_g = ndi.find_objects(g)
    split = 0
    for r in big:
        idx = np.nonzero(site_root == r)[0]
        if len(idx) < 2 or r - 1 >= len(objs_g) or objs_g[r - 1] is None:
            continue
        sl = objs_g[r - 1]
        sub = g[sl] == r
        yy, xx = np.nonzero(sub)
        gy, gx = yy + sl[0].start, xx + sl[1].start
        tree = cKDTree(sites_arr[idx])
        q = np.stack([gx + 0.5 + nx_f[gy, gx] * AMP, gy + 0.5 + ny_f[gy, gx] * AMP], axis=1)
        _, nn = tree.query(q)
        view = labels[sl]
        view[sub] = 100000 + idx[nn]
        split += 1
    log("divisões gigantes subdivididas: %d" % split)
    return labels


if not opt.voronoi:
    prov = real_border_labels()
    log("fronteiras administrativas originais aplicadas")

# ---------------------------------------------------------------------------
# 4. Componentes conexos = províncias; fundir fragmentos minúsculos
# ---------------------------------------------------------------------------
comp = measure.label(prov, connectivity=1, background=-1)
MIN_PX = 9
for _ in range(3):
    cnt = np.bincount(comp.ravel())
    tiny = [c for c in np.argsort(cnt) if 0 < c < len(cnt) and cnt[c] < MIN_PX]
    if not tiny:
        break
    objs = ndi.find_objects(comp)
    for c in tiny:
        if cnt[c] >= MIN_PX or objs[c - 1] is None:
            continue
        sl = objs[c - 1]
        y0, y1 = max(sl[0].start - 1, 0), min(sl[0].stop + 1, H)
        x0, x1 = max(sl[1].start - 1, 0), min(sl[1].stop + 1, W)
        sub = comp[y0:y1, x0:x1]
        m = sub == c
        ring = ndi.binary_dilation(m) & ~m
        nb = sub[ring]
        nb = nb[nb > 0]
        if len(nb) == 0:
            comp[y0:y1, x0:x1][m] = 0     # ilhotinha isolada: some
            own[y0:y1, x0:x1][m] = -1
            adm[y0:y1, x0:x1][m] = 0
        else:
            tgt = int(np.bincount(nb).argmax())
            comp[y0:y1, x0:x1][m] = tgt
            own_t = own[y0:y1, x0:x1][sub == tgt]
            if len(own_t):
                own[y0:y1, x0:x1][m] = own_t[0]
        cnt[tgt if len(nb) else 0] += int(m.sum())
        cnt[c] = 0

uniq, inv = np.unique(comp, return_inverse=True)
comp = inv.reshape(comp.shape).astype(np.int32)
if uniq[0] != 0:
    comp += 1
NPROV = int(comp.max())
lab = comp - 1          # -1 = mar, 0..NPROV-1 = província
log("províncias: %d" % NPROV)

# ---------------------------------------------------------------------------
# 5. Arcos de fronteira compartilhados
# ---------------------------------------------------------------------------
pad = np.pad(lab, 1, constant_values=-1)
vl = pad[1:H + 1, 0:W + 1]
vr = pad[1:H + 1, 1:W + 2]
vy, vx = np.nonzero(vl != vr)
hu = pad[0:H + 1, 1:W + 1]
hd = pad[1:H + 2, 1:W + 1]
hy, hx = np.nonzero(hu != hd)

EV = len(vx)
EH = len(hx)
E = EV + EH
stride = W + 1
# aresta vertical (x,y)->(x,y+1): esquerda = leste = vr ; direita = oeste = vl
eu = np.concatenate([vy * stride + vx, hy * stride + hx])
ev = np.concatenate([(vy + 1) * stride + vx, hy * stride + hx + 1])
eA = np.concatenate([vr[vy, vx], hu[hy, hx]]).astype(np.int64)   # rótulo à esquerda de u->v
eB = np.concatenate([vl[vy, vx], hd[hy, hx]]).astype(np.int64)   # rótulo à direita
log("arestas de fronteira: %d" % E)

ends = np.concatenate([eu, ev])
uverts, inv_e = np.unique(ends, return_inverse=True)
cu, cv = inv_e[:E], inv_e[E:]
deg = np.bincount(inv_e, minlength=len(uverts))
order_e = np.argsort(inv_e, kind="stable")
eidx = np.concatenate([np.arange(E), np.arange(E)])
starts = np.concatenate([[0], np.cumsum(deg)])
pk = (np.minimum(eA, eB) + 1) * (NPROV + 2) + (np.maximum(eA, eB) + 1)

is_junc = deg != 2
two = np.nonzero(deg == 2)[0]
e_a = eidx[order_e[starts[two]]]
e_b = eidx[order_e[starts[two] + 1]]
is_junc[two[pk[e_a] != pk[e_b]]] = True

visited = np.zeros(E, dtype=bool)
chains = []   # (lista de vértices comprimidos, esquerda, direita)


def other_edge(c, e):
    s = starts[c]
    a = eidx[order_e[s]]
    b = eidx[order_e[s + 1]]
    return b if a == e else a


def walk(start_c, e0):
    chain = [start_c]
    c = start_c
    e = e0
    while True:
        visited[e] = True
        nxt = int(cv[e]) if cu[e] == c else int(cu[e])
        chain.append(nxt)
        c = nxt
        if is_junc[c]:
            break
        e2 = other_edge(c, e)
        if visited[e2]:
            break
        e = e2
    return chain


def left_right(c0, e0):
    return (int(eA[e0]), int(eB[e0])) if cu[e0] == c0 else (int(eB[e0]), int(eA[e0]))


junc_idx = np.nonzero(is_junc)[0]
for c in junc_idx.tolist():
    for pos in range(starts[c], starts[c + 1]):
        e = int(eidx[order_e[pos]])
        if visited[e]:
            continue
        ch = walk(c, e)
        chains.append((ch, *left_right(c, e)))
for e in range(E):
    if not visited[e]:
        c0 = int(cu[e])
        ch = walk(c0, e)
        chains.append((ch, *left_right(c0, e)))
log("arcos: %d" % len(chains))


def dp(pts, tol):
    n = len(pts)
    if n <= 2:
        return pts
    keepm = np.zeros(n, dtype=bool)
    keepm[0] = keepm[-1] = True
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = pts[i], pts[j]
        seg = pts[i + 1:j]
        d = b - a
        L = math.hypot(d[0], d[1])
        if L < 1e-9:
            dist = np.hypot(seg[:, 0] - a[0], seg[:, 1] - a[1])
        else:
            dist = np.abs(d[0] * (seg[:, 1] - a[1]) - d[1] * (seg[:, 0] - a[0])) / L
        k = int(np.argmax(dist))
        if dist[k] > tol:
            m = i + 1 + k
            keepm[m] = True
            stack.append((i, m))
            stack.append((m, j))
    return pts[keepm]


def simplify(pts, tol):
    if len(pts) <= 3:
        return pts
    if np.array_equal(pts[0], pts[-1]):
        m = int(np.argmax(np.hypot(pts[:, 0] - pts[0, 0], pts[:, 1] - pts[0, 1])))
        a = dp(pts[:m + 1], tol)
        b = dp(pts[m:], tol)
        return np.concatenate([a, b[1:]])
    return dp(pts, tol)


arcs = []   # dict(pts int array (n,2), left, right)
for ch, left, right in chains:
    vid = uverts[np.asarray(ch)]
    pts = np.stack([vid % stride, vid // stride], axis=1).astype(np.float64)
    pts = simplify(pts, opt.tol)
    arcs.append({"pts": pts.astype(np.int32), "l": left, "r": right})
log("arcos simplificados: %d vértices" % sum(len(a["pts"]) for a in arcs))

# ---------------------------------------------------------------------------
# 6. Polígonos das províncias a partir dos arcos
# ---------------------------------------------------------------------------
out_arcs = defaultdict(lambda: defaultdict(list))   # prov -> início(x,y) -> [(arco, invertido)]
for ai, a in enumerate(arcs):
    first = tuple(a["pts"][0])
    last = tuple(a["pts"][-1])
    if a["l"] >= 0:
        out_arcs[a["l"]][first].append((ai, False))
    if a["r"] >= 0:
        out_arcs[a["r"]][last].append((ai, True))


def shoelace(poly):
    x = poly[:, 0].astype(np.float64)
    y = poly[:, 1].astype(np.float64)
    return 0.5 * float(np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y))


polys = {}
for p in range(NPROV):
    table = {k: list(v) for k, v in out_arcs[p].items()}
    loops = []
    while table:
        k0 = next(iter(table))
        lst = table[k0]
        ai, inverted = lst.pop(0)
        if not lst:
            del table[k0]
        verts = []
        nbs = []
        cur_start = k0
        while True:
            a = arcs[ai]
            pts = a["pts"][::-1] if inverted else a["pts"]
            nb = a["l"] if inverted else a["r"]
            verts.extend(map(tuple, pts[:-1].tolist()))
            nbs.extend([nb] * (len(pts) - 1))
            end = tuple(pts[-1].tolist())
            if end == cur_start:
                break
            lst2 = table.get(end)
            if not lst2:
                verts = None
                break
            ai, inverted = lst2.pop(0)
            if not lst2:
                del table[end]
        if verts and len(verts) >= 3:
            loops.append((np.array(verts, dtype=np.int32), nbs))
    if not loops:
        continue
    best = max(loops, key=lambda t: abs(shoelace(t[0])))
    polys[p] = best

log("polígonos montados: %d de %d" % (len(polys), NPROV))

# ---------------------------------------------------------------------------
# 7. Atributos das províncias
# ---------------------------------------------------------------------------
objs = ndi.find_objects(comp)
adm_names = [""] + [f["name"] for f in feats]
infos = {}
for p in polys:
    sl = objs[p]
    y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
    m = comp[sl] == p + 1
    area_px = int(m.sum())
    yy, xx = np.nonzero(m)
    cxm, cym = xx.mean() + x0 + 0.5, yy.mean() + y0 + 0.5
    dist = ndi.distance_transform_edt(np.pad(m, 1))
    py, px = np.unravel_index(int(np.argmax(dist)), dist.shape)
    pole = (x0 + px - 1 + 0.5, y0 + py - 1 + 0.5)
    names = adm[sl][m]
    names = names[names > 0]
    nm = adm_names[int(np.bincount(names).argmax())] if len(names) else "Terra"
    ow = own[sl][m]
    ow = ow[ow >= 0]
    owner = int(np.bincount(ow).argmax()) if len(ow) else 0
    infos[p] = {"area_px": area_px, "centroid": (cxm, cym), "pole": pole, "name": nm, "owner": owner}

# Cidade-sede de cada província: o lugar povoado mais importante dentro dela
# (capital do país > capital de estado/província > maior população).
def load_places():
    path = os.path.join(opt.ne, "ne_10m_populated_places_simple.geojson")
    if not os.path.exists(path):
        log("sem lugares povoados; províncias ficarão sem cidade-sede")
        return []
    with open(path) as f:
        data = json.load(f)
    out = []
    for ft in data["features"]:
        pr = ft["properties"]
        cls = pr.get("featurecla") or ""
        if cls in ("Scientific station", "Historic place"):
            continue
        lon, lat = ft["geometry"]["coordinates"][:2]
        score = float(pr.get("pop_max") or 0)
        if cls.startswith("Admin-0 capital"):
            score += 2e9
        elif cls.startswith("Admin-1"):
            score += 1e8
        out.append((lon, lat, score, pr.get("name") or pr.get("nameascii") or "?", cls.startswith("Admin-0 capital"), float(pr.get("pop_max") or 0)))
    return out


places = load_places()
objs_idx = set(polys.keys())
best_city = {}
if places:
    pl = np.array([(p[0], p[1]) for p in places])
    pxs, pys = project(pl[:, 0], pl[:, 1])
    city_weight = defaultdict(float)
    city_unit = {}
    for (lon_, lat_, score, nm, is_cap, popmax), px_, py_ in zip(places, pxs.tolist(), pys.tolist()):
        ix, iy = int(px_), int(py_)
        if not (0 <= ix < W and 0 <= iy < H):
            continue
        lbl = int(comp[iy, ix])
        if lbl <= 0:
            continue
        p_ = lbl - 1
        city_weight[p_] += max(popmax, 5000.0) ** 0.85
        if p_ not in best_city or score > best_city[p_][0]:
            best_city[p_] = (score, nm, is_cap)
            city_unit[p_] = int(adm[iy, ix])
    for p_, wgt in city_weight.items():
        if p_ in infos:
            infos[p_]["city_w"] = wgt
    log("cidades-sede atribuídas: %d" % len(best_city))
for p_, (_, nm, is_cap) in best_city.items():
    if p_ in infos:
        infos[p_]["city"] = nm
        infos[p_]["capital_city"] = bool(is_cap)
        # província fundida leva o nome da divisão onde está a cidade principal (Rio, não Minas)
        # (só se essa divisão for >= 25% da província; capital de país sem isso leva o nome da cidade)
        un = city_unit.get(p_, 0)
        if un > 0 and adm_names[un] and p_ in objs_idx:
            sl_ = objs[p_]
            m_ = comp[sl_] == p_ + 1
            frac = float((adm[sl_][m_] == un).mean()) if m_.any() else 0.0
            if frac >= 0.25:
                infos[p_]["name"] = adm_names[un]
            elif is_cap:
                infos[p_]["name"] = nm

# províncias que não têm polígono (falha de montagem) são descartadas; ids por área decrescente
valid = sorted(polys.keys(), key=lambda p: -infos[p]["area_px"])
new_id = {p: i for i, p in enumerate(valid)}
log("províncias finais: %d" % len(valid))

# Estados que ficaram sem província saem da lista
used_states = sorted({infos[p]["owner"] for p in valid if infos[p]["owner"] > 0})
state_final = {s: i for i, s in enumerate(used_states)}   # índice no JSON
dropped = [D.STATES[s - 1][1] for s in range(1, len(D.STATES) + 1) if s not in state_final]
if dropped:
    log("estados sem território no raster (removidos): %s" % ", ".join(dropped))

# vizinhança
neigh = defaultdict(set)
for a in arcs:
    if a["l"] >= 0 and a["r"] >= 0 and a["l"] in new_id and a["r"] in new_id:
        neigh[new_id[a["l"]]].add(new_id[a["r"]])
        neigh[new_id[a["r"]]].add(new_id[a["l"]])

out_provs = []
terrain_count = Counter()
res_count = Counter()
for p in valid:
    info = infos[p]
    pid = new_id[p]
    verts, nbs = polys[p]
    cxp, cyp = info["pole"]
    lon, lat = unproject(cxp, cyp)
    lon, lat = float(lon), float(lat)
    ms = D.mountain_score(lon, lat)
    terrain = D.terrain_for(lon, lat, ms)
    if terrain == "plains" and pyrng.random() < 0.10:
        terrain = "hills"
    km2 = info["area_px"] * float(km_per_px(lat)) ** 2
    coastal = any(nb == -1 for nb in nbs)

    weights = defaultdict(float)
    for res, rects in D.RESOURCE_REGIONS.items():
        for (x0, y0, x1, y1, w) in rects:
            if x0 <= lon <= x1 and y0 <= lat <= y1:
                weights[res] += w
    if weights and pyrng.random() < 0.8:
        items = list(weights.items())
        resource = pyrng.choices([i[0] for i in items], [i[1] for i in items])[0]
    else:
        fb = D.FALLBACK_BY_TERRAIN[terrain]
        resource = pyrng.choices([i[0] for i in fb], [i[1] for i in fb])[0]
    if coastal and terrain in ("plains", "hills", "forest", "tundra") and pyrng.random() < 0.12:
        resource = "fish"
    terrain_count[terrain] += 1
    res_count[resource] += 1

    nb_ids = [(new_id[nb] if nb >= 0 and nb in new_id else -1) for nb in nbs]
    owner_state = info["owner"]
    out_provs.append({
        "id": pid, "name": info["name"], "poly": [int(v) for v in verts.reshape(-1)],
        "edges": nb_ids, "terrain": terrain, "resource": resource, "coastal": bool(coastal),
        "owner": state_final[owner_state] if owner_state in state_final else -1,
        "center": [int(round(cxp)), int(round(cyp))], "area": int(round(km2)),
        "lon": round(lon, 2), "lat": round(lat, 2), "pop": 0, "neighbors": sorted(neigh[pid]), "_cw": info.get("city_w", 0.0),
        "city": info.get("city", ""), "capital_city": bool(info.get("capital_city", False)),
    })

# nomes duplicados dentro do mesmo país ganham sufixo
groups = defaultdict(list)
for pr in out_provs:
    groups[(pr["owner"], pr["name"])].append(pr)
for (_, nm), lst in groups.items():
    if len(lst) == 1:
        continue
    if len(lst) == 2:
        dx = abs(lst[0]["center"][0] - lst[1]["center"][0])
        dy = abs(lst[0]["center"][1] - lst[1]["center"][1])
        if dy >= dx:
            lst.sort(key=lambda q: q["center"][1])
            lst[0]["name"], lst[1]["name"] = nm + " Norte", nm + " Sul"
        else:
            lst.sort(key=lambda q: q["center"][0])
            lst[0]["name"], lst[1]["name"] = nm + " Oeste", nm + " Leste"
    else:
        lst.sort(key=lambda q: (q["center"][1], q["center"][0]))
        roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV"]
        for i, q in enumerate(lst):
            q["name"] = "%s %s" % (nm, roman[i] if i < len(roman) else str(i + 1))

# população: total do Estado distribuído por (60% cidades + 40% área x fertilidade). Só por área,
# o interior vazio ficava mais populoso que o litoral e as capitais.
by_owner = defaultdict(list)
for pr in out_provs:
    w = pr["area"] * D.TERRAIN_POP_FACTOR[pr["terrain"]] * (1.15 if pr["coastal"] else 1.0)
    if pr["resource"] in ("grain", "cotton", "sugar", "wine", "silk", "tea"):
        w *= 1.2
    elif pr["resource"] in ("furs", "salt"):
        w *= 0.8
    pr["_w"] = max(w, 1.0)
    by_owner[pr["owner"]].append(pr)
for owner, lst in by_owner.items():
    if owner >= 0:
        total = D.STATES[used_states[owner] - 1][3] * 1e6
        sa = sum(q["_w"] for q in lst)
        sc = sum(q["_cw"] for q in lst)
        for q in lst:
            share = q["_w"] / sa
            if sc > 0:
                share = 0.4 * share + 0.6 * q["_cw"] / sc
            q["pop"] = int(round(total * share / 100.0)) * 100
    else:
        for q in lst:
            dens = D.unclaimed_density(q["lon"], q["lat"])
            q["pop"] = int(round(q["area"] * dens * D.TERRAIN_POP_FACTOR[q["terrain"]] / 100.0)) * 100
for pr in out_provs:
    pr["pop"] = max(pr["pop"], 100)
    del pr["_w"]
    del pr["_cw"]

# países
countries = []
auto = D.auto_colors(len(used_states))
for s in used_states:
    key, name, color, popm, (clon, clat) = D.STATES[s - 1]
    cid = state_final[s]
    mine = [pr for pr in out_provs if pr["owner"] == cid]
    cxp, cyp = project(clon, clat)
    cap = min(mine, key=lambda q: (q["center"][0] - cxp) ** 2 + (q["center"][1] - cyp) ** 2)
    countries.append({"id": cid, "tag": key, "name": name, "color": color, "capital": cap["id"], "pop_total": popm})

# ---------------------------------------------------------------------------
# 7b. Rotas marítimas: estreitos entre massas de terra diferentes
# ---------------------------------------------------------------------------
STRAIT_PX = 14.0      # distância máxima de um estreito (~180 km no equador)
FALLBACK_PX = 48.0    # ilhas/continentes isolados ganham ao menos uma ligação até esta distância
MAX_STRAITS = 3       # ligações por província


def compute_sea_links(provs):
    n = len(provs)
    # componentes de terra (adjacência por fronteira)
    comp_of = [-1] * n
    ncomp = 0
    for s in range(n):
        if comp_of[s] >= 0:
            continue
        stack = [s]
        comp_of[s] = ncomp
        while stack:
            u = stack.pop()
            for v in provs[u]["neighbors"]:
                if comp_of[v] < 0:
                    comp_of[v] = ncomp
                    stack.append(v)
        ncomp += 1
    pts, owners = [], []
    for pr in provs:
        if not pr["coastal"]:
            continue
        for i in range(0, len(pr["poly"]), 2):
            pts.append((pr["poly"][i], pr["poly"][i + 1]))
            owners.append(pr["id"])
    pts = np.asarray(pts, dtype=np.float64)
    owners = np.asarray(owners, dtype=np.int64)
    tree = cKDTree(pts)

    def candidates(pid, radius):
        """melhor distância de pid a cada província costeira de OUTRA massa de terra."""
        best = {}
        pr = provs[pid]
        for i in range(0, len(pr["poly"]), 2):
            v = (pr["poly"][i], pr["poly"][i + 1])
            for j in tree.query_ball_point(v, radius):
                q = int(owners[j])
                if comp_of[q] == comp_of[pid]:
                    continue
                d = math.hypot(pts[j][0] - v[0], pts[j][1] - v[1])
                if d < best.get(q, 1e18):
                    best[q] = d
        return best

    links = defaultdict(set)
    for pr in provs:
        if not pr["coastal"]:
            continue
        cand = sorted(candidates(pr["id"], STRAIT_PX).items(), key=lambda kv: (kv[1], kv[0]))
        for q, _ in cand[:MAX_STRAITS]:
            links[pr["id"]].add(q)
            links[q].add(pr["id"])

    # união de componentes (terra + estreitos) e ligações de último recurso
    parent = list(range(ncomp))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for pid in range(n):
        for q in list(provs[pid]["neighbors"]) + list(links.get(pid, ())):
            a, b = find(comp_of[pid]), find(comp_of[q])
            if a != b:
                parent[a] = b
    sizes = Counter(find(comp_of[i]) for i in range(n))
    main_root = sizes.most_common(1)[0][0]
    changed = True
    while changed:
        changed = False
        roots = sorted({find(comp_of[i]) for i in range(n)}, key=lambda r: sizes[r])
        for r in roots:
            if r == main_root or find(r) != r:
                continue
            best = (1e18, None, None)
            for pid in range(n):
                if not provs[pid]["coastal"] or find(comp_of[pid]) != r:
                    continue
                for q, d in candidates(pid, FALLBACK_PX).items():
                    if find(comp_of[q]) != r and d < best[0]:
                        best = (d, pid, q)
            if best[1] is not None:
                _, a_, b_ = best
                links[a_].add(b_)
                links[b_].add(a_)
                ra, rb = find(comp_of[a_]), find(comp_of[b_])
                parent[ra] = rb
                sizes[rb] += sizes[ra]
                if main_root == ra:
                    main_root = rb
                changed = True
    return {pid: sorted(v) for pid, v in links.items()}


sea = compute_sea_links(out_provs)
for pr in out_provs:
    pr["sea"] = sea.get(pr["id"], [])
log("rotas marítimas: %d ligações em %d províncias" % (sum(len(v) for v in sea.values()) // 2, len(sea)))

# ---------------------------------------------------------------------------
# 7b. Grade marítima (para os navios) e porto de cada província costeira
# ---------------------------------------------------------------------------
SEA_CELL = 12


def build_sea_grid():
    """Grade de água navegável: célula é água se tiver >= 2 pixels de água. Istmos de Suez e
    Panamá são fechados (em 1836 não havia canais) e água que não liga ao oceano principal
    (lagos, Cáspio) vira terra."""
    gw, gh = (W + SEA_CELL - 1) // SEA_CELL, (H + SEA_CELL - 1) // SEA_CELL
    water_px = ~land
    pad = np.zeros((gh * SEA_CELL, gw * SEA_CELL), dtype=np.int32)
    pad[:H, :W] = water_px
    cnt = pad.reshape(gh, SEA_CELL, gw, SEA_CELL).sum(axis=(1, 3))
    grid = cnt >= 2
    # fecha Suez e Panamá
    for (lon0, lat0, lon1, lat1) in ((32.0, 29.5, 33.2, 31.4), (-80.6, 8.4, -78.8, 9.8)):
        xs, ys = project(np.array([lon0, lon1]), np.array([lat0, lat1]))
        x0, x1 = int(min(xs)) // SEA_CELL, int(max(xs)) // SEA_CELL
        y0, y1 = int(min(ys)) // SEA_CELL, int(max(ys)) // SEA_CELL
        # só fecha células cuja maioria é terra
        for cy in range(max(0, y0), min(gh, y1 + 1)):
            for cx in range(max(0, x0), min(gw, x1 + 1)):
                if cnt[cy, cx] < SEA_CELL * SEA_CELL * 0.5:
                    grid[cy, cx] = False
    lab, nl = ndi.label(grid, structure=np.ones((3, 3)))
    if nl:
        sizes = np.bincount(lab.ravel())
        sizes[0] = 0
        grid = lab == int(np.argmax(sizes))
    return grid


sea_grid = build_sea_grid()
SGH, SGW = sea_grid.shape
near_water = ndi.binary_dilation(sea_grid, structure=np.ones((3, 3)), iterations=1)
nports = 0
for pr in out_provs:
    pr["port"] = -1
    if not pr.get("coastal"):
        continue
    poly = np.asarray(pr["poly"], dtype=np.float64).reshape(-1, 2)
    cx = np.clip((poly[:, 0] // SEA_CELL).astype(int), 0, SGW - 1)
    cy = np.clip((poly[:, 1] // SEA_CELL).astype(int), 0, SGH - 1)
    ok = near_water[cy, cx]
    if not ok.any():
        continue
    ctr = np.asarray(pr["center"], dtype=np.float64)
    cand = np.nonzero(ok)[0]
    k = cand[np.argmin(((poly[cand] - ctr) ** 2).sum(axis=1))]
    best = None
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            yy, xx = cy[k] + dy, cx[k] + dx
            if 0 <= yy < SGH and 0 <= xx < SGW and sea_grid[yy, xx]:
                d = (xx * SEA_CELL + SEA_CELL / 2 - poly[k, 0]) ** 2 + (yy * SEA_CELL + SEA_CELL / 2 - poly[k, 1]) ** 2
                if best is None or d < best[0]:
                    best = (d, yy * SGW + xx)
    if best is not None:
        pr["port"] = int(best[1])
        nports += 1
log("grade marítima %dx%d (%d células de água); portos: %d" % (SGW, SGH, int(sea_grid.sum()), nports))

# ---------------------------------------------------------------------------
# 8. Validação rápida: autointerseção de polígonos
# ---------------------------------------------------------------------------
def self_intersects(poly):
    p = np.asarray(poly, dtype=np.float64).reshape(-1, 2)
    n = len(p)
    if n < 4:
        return False
    a = p
    b = np.roll(p, -1, axis=0)
    # compara todos os pares de segmentos não adjacentes, em blocos
    for s in range(0, n, 512):
        e = min(n, s + 512)
        a1, b1 = a[s:e, None, :], b[s:e, None, :]
        a2, b2 = a[None, :, :], b[None, :, :]

        def cross(o, u, v):
            return (u[..., 0] - o[..., 0]) * (v[..., 1] - o[..., 1]) - (u[..., 1] - o[..., 1]) * (v[..., 0] - o[..., 0])

        d1 = cross(a1, b1, a2)
        d2 = cross(a1, b1, b2)
        d3 = cross(a2, b2, a1)
        d4 = cross(a2, b2, b1)
        inter = (d1 * d2 < 0) & (d3 * d4 < 0)
        ii = np.arange(s, e)[:, None]
        jj = np.arange(n)[None, :]
        adj = (np.abs(ii - jj) <= 1) | (np.abs(ii - jj) == n - 1)
        if np.any(inter & ~adj):
            return True
    return False


bad = [pr["id"] for pr in out_provs if len(pr["poly"]) < 6000 and self_intersects(pr["poly"])]
log("polígonos com autointerseção: %d" % len(bad))
for pr in out_provs:
    pr["bad"] = pr["id"] in bad
    if not pr["bad"]:
        del pr["bad"]

world = {
    "map_size": [W, H],
    "projection": {"type": "miller", "lat_top": LAT_TOP, "lat_bot": LAT_BOT, "width": W, "height": H},
    "start_date": [1836, 1, 1],
    "countries": countries,
    "provinces": out_provs,
    "sea_grid": {"cell": SEA_CELL, "w": SGW, "h": SGH,
                 "rows": ["".join("1" if v else "0" for v in row) for row in sea_grid]},
}
os.makedirs(os.path.dirname(os.path.abspath(opt.out)), exist_ok=True)
with open(opt.out, "w") as f:
    json.dump(world, f, separators=(",", ":"), ensure_ascii=False)
log("gravado %s (%.2f MB)  %d províncias, %d países" % (opt.out, os.path.getsize(opt.out) / 1e6, len(out_provs), len(countries)))
log("terrenos: %s" % dict(terrain_count))
log("recursos: %s" % dict(res_count))
vcount = sum(len(p["poly"]) // 2 for p in out_provs)
log("vértices totais: %d" % vcount)

if opt.preview:
    scale = 0.5
    img = Image.new("RGB", (int(W * scale), int(H * scale)), (30, 60, 95))
    dr = ImageDraw.Draw(img)
    cols = {c["id"]: tuple(int(c["color"][i:i + 2], 16) for i in (1, 3, 5)) for c in countries}
    for pr in out_provs:
        col = cols.get(pr["owner"], (150, 150, 150))
        pts = [(pr["poly"][i] * scale, pr["poly"][i + 1] * scale) for i in range(0, len(pr["poly"]), 2)]
        dr.polygon(pts, fill=col, outline=(20, 20, 20))
    img.save(opt.preview)
    log("preview: %s" % opt.preview)

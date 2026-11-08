class_name Province
extends RefCounted
## Província: unidade básica do mapa (gerada por tools/generate_world_1836.py a partir
## do Natural Earth). Polígonos podem ser côncavos, por isso são triangulados uma vez
## aqui e o mapa usa uma única malha. População em pessoas (inteiro) para manter a
## simulação determinística.

const MAX_BUILDING := 3
const FLAT_TAX := 2   # imposto fixo por província (mantém países minúsculos viáveis)

# Multiplicadores inteiros (permil) para evitar float na economia.
const TERRAIN_MULT := {
	"plains": 1000, "hills": 900, "mountains": 600, "forest": 800,
	"desert": 500, "jungle": 700, "tundra": 400,
}
## Custo de movimento por terreno de destino (permil).
const MOVE_MULT := {
	"plains": 1000, "hills": 1300, "mountains": 1800, "forest": 1400,
	"desert": 1500, "jungle": 1700, "tundra": 1300,
}
## Preço-base do recurso (décimos de ouro por unidade).
const RESOURCE_PRICE := {
	"grain": 10, "livestock": 11, "fish": 9, "timber": 10, "furs": 16, "wool": 13,
	"cotton": 14, "coal": 15, "iron": 16, "salt": 14, "wine": 17, "sugar": 18,
	"tobacco": 18, "coffee": 19, "tea": 22, "silk": 24, "spices": 28, "opium": 26,
	"gold": 45,
}

var id: int = 0
var name: String = ""
var poly: PackedVector2Array = PackedVector2Array()
var tris: PackedInt32Array = PackedInt32Array()     # triângulos (índices em poly)
var edges: PackedInt32Array = PackedInt32Array()    # edges[i] = vizinha do lado i -> i+1 (-1 = mar)
var neighbors: Array[int] = []
var sea_links: Array[int] = []                      # estreitos / travessias marítimas
var terrain: String = "plains"
var resource_type: String = "grain"
var coastal: bool = false
var population: int = 0
var owner_id: int = -1                              # -1 = terra sem dono
var lon: float = 0.0
var lat: float = 0.0
var area: float = 0.0

# Estado econômico/militar (entra no snapshot de rede)
var workshop: int = 0
var barracks: int = 0
var manpower: int = 0

# Derivados
var center: Vector2 = Vector2.ZERO   # ponto garantidamente dentro da província
var bounds: Rect2 = Rect2()


static func from_dict(d: Dictionary) -> Province:
	var p := Province.new()
	p.id = int(d["id"])
	p.name = str(d["name"])

	var raw: Array = d["poly"]
	var pts := PackedVector2Array()
	for i in range(0, raw.size(), 2):
		pts.append(Vector2(float(raw[i]), float(raw[i + 1])))

	var raw_edges: Array = d["edges"]
	for e in raw_edges:
		p.edges.append(int(e))

	var raw_nb: Array = d.get("neighbors", [])
	for n in raw_nb:
		p.neighbors.append(int(n))
	var raw_sea: Array = d.get("sea", [])
	for s in raw_sea:
		p.sea_links.append(int(s))

	p.terrain = str(d["terrain"])
	p.resource_type = str(d["resource"])
	p.coastal = bool(d["coastal"])
	p.population = int(d["pop"])
	p.owner_id = int(d["owner"])
	p.lon = float(d.get("lon", 0.0))
	p.lat = float(d.get("lat", 0.0))
	p.area = float(d.get("area", 0.0))

	var c: Array = d["center"]
	p.center = Vector2(float(c[0]), float(c[1]))

	var tr: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
	if tr.is_empty():
		# Raro: polígono degenerado. Cai para o casco convexo (e o desenho de bordas ignora a província).
		push_warning("GeoEmpire: triangulação falhou em '%s'; usando casco convexo" % p.name)
		var hull: PackedVector2Array = Geometry2D.convex_hull(pts)
		if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
			hull.remove_at(hull.size() - 1)
		pts = hull
		tr = Geometry2D.triangulate_polygon(pts)
	p.poly = pts
	p.tris = tr

	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for v in pts:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	p.bounds = Rect2(mn, mx - mn)
	p.manpower = p.manpower_max()
	return p


## Produção mensal (ouro, antes de impostos): população x preço do recurso x terreno.
@warning_ignore("integer_division")
func production() -> int:
	var price: int = RESOURCE_PRICE.get(resource_type, 10)
	var tm: int = TERRAIN_MULT.get(terrain, 1000)
	var base: int = population * price * tm / 150000000
	return base * (100 + 25 * workshop) / 100


## Imposto mensal que o dono recebe.
@warning_ignore("integer_division")
func monthly_tax(tax_pct: int) -> int:
	return FLAT_TAX + production() * tax_pct / 100


## Mão de obra máxima: 2% da população (+1% por nível de quartel).
@warning_ignore("integer_division")
func manpower_max() -> int:
	return population * (200 + 100 * barracks) / 10000


func building_level(kind: String) -> int:
	if kind == "workshop":
		return workshop
	if kind == "barracks":
		return barracks
	return 0


func set_building_level(kind: String, level: int) -> void:
	if kind == "workshop":
		workshop = level
	elif kind == "barracks":
		barracks = level

class_name Province
extends RefCounted
## Província: unidade básica do mapa (célula de Voronoi de tools/generate_world.py).
## População em pessoas (inteiro) para manter a simulação determinística.

# Multiplicadores inteiros (permil / décimos) para evitar float na economia.
const TERRAIN_MULT := {"plains": 1000, "hills": 900, "mountains": 700, "forest": 800, "desert": 600}
const RESOURCE_VALUE := {"grain": 10, "iron": 14, "coal": 14, "timber": 10, "cotton": 13, "fish": 9, "gold": 40, "salt": 16}

var id: int = 0
var name: String = ""
var poly: PackedVector2Array = PackedVector2Array()
var edges: PackedInt32Array = PackedInt32Array()   # edges[i] = vizinha do lado i -> i+1 (-1 = mar)
var neighbors: Array[int] = []
var sea_links: Array[int] = []
var terrain: String = "plains"
var resource_type: String = "grain"
var coastal: bool = false
var population: int = 0
var owner_id: int = -1

# Derivados (não entram no estado de rede)
var center: Vector2 = Vector2.ZERO
var bounds: Rect2 = Rect2()


static func from_dict(d: Dictionary) -> Province:
	var p := Province.new()
	p.id = int(d["id"])
	p.name = str(d["name"])

	var raw: Array = d["poly"]
	var pts := PackedVector2Array()
	for i in range(0, raw.size(), 2):
		pts.append(Vector2(float(raw[i]), float(raw[i + 1])))
	p.poly = pts

	var raw_edges: Array = d["edges"]
	for e in raw_edges:
		var ei := int(e)
		p.edges.append(ei)
		if ei >= 0 and not p.neighbors.has(ei):
			p.neighbors.append(ei)

	var raw_sea: Array = d["sea"]
	for s in raw_sea:
		p.sea_links.append(int(s))

	p.terrain = str(d["terrain"])
	p.resource_type = str(d["resource"])
	p.coastal = bool(d["coastal"])
	p.population = int(round(float(d["pop"]) * 1000.0))
	p.owner_id = int(d["owner"])

	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	var sum := Vector2.ZERO
	for v in pts:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
		sum += v
	p.bounds = Rect2(mn, mx - mn)
	p.center = sum / float(pts.size())   # células são convexas: a média cai dentro
	return p


## Renda mensal (inteira) com a taxa de imposto do dono.
@warning_ignore("integer_division")
func monthly_income(tax_pct: int) -> int:
	var rv: int = RESOURCE_VALUE.get(resource_type, 10)
	var tm: int = TERRAIN_MULT.get(terrain, 1000)
	return population * rv * tm * tax_pct / 1000000000

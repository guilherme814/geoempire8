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

## Bens processados (preço-base em décimos de ouro por unidade).
const PROCESSED := {"fabric": 30, "tools": 36, "furniture": 28, "steel": 42}
## Fábricas: por nível produzem `amount` unidades de `out` por mês e consomem `inputs` do mercado.
const FACTORIES := {
	"textile": {"out": "fabric", "amount": 100, "inputs": {"cotton": 60, "wool": 60}},
	"smithy": {"out": "tools", "amount": 100, "inputs": {"iron": 80, "timber": 40}},
	"carpentry": {"out": "furniture", "amount": 100, "inputs": {"timber": 100}},
	"steel": {"out": "steel", "amount": 100, "inputs": {"iron": 100, "coal": 100}},
}

## Construções por aba: tab (gov/res/ind), nome, custo-base (x nível+1), tecnologia exigida, efeito.
const BUILDINGS := {
	"school": {"tab": "gov", "name": "Escola", "cost": 120, "tech": 0, "desc": "Alfabetização"},
	"university": {"tab": "gov", "name": "Universidade", "cost": 320, "tech": 1, "desc": "Alfabetização e pesquisa"},
	"barracks": {"tab": "gov", "name": "Quartel", "cost": 100, "tech": 0, "desc": "Mão de obra militar +1%"},
	"mine": {"tab": "res", "name": "Mina", "cost": 140, "tech": 0, "desc": "+35% carvão, ferro, sal, ouro"},
	"farm": {"tab": "res", "name": "Fazenda", "cost": 110, "tech": 0, "desc": "+35% produção agrícola"},
	"logging": {"tab": "res", "name": "Madeireira", "cost": 110, "tech": 0, "desc": "+35% madeira (ou madeira extra em florestas)"},
	"workshop": {"tab": "res", "name": "Oficina", "cost": 120, "tech": 0, "desc": "+25% produção do recurso"},
	"textile": {"tab": "ind", "name": "Tecelagem", "cost": 150, "tech": 0, "desc": "Algodão + lã -> tecido"},
	"carpentry": {"tab": "ind", "name": "Marcenaria", "cost": 130, "tech": 0, "desc": "Madeira -> móveis"},
	"smithy": {"tab": "ind", "name": "Ferraria", "cost": 180, "tech": 1, "desc": "Ferro + madeira -> ferramentas"},
	"steel": {"tab": "ind", "name": "Siderúrgica", "cost": 260, "tech": 3, "desc": "Ferro + carvão -> aço"},
}
const EXTRA_KINDS := ["school", "university", "mine", "farm", "logging"]
const MINE_RES := ["coal", "iron", "salt", "gold"]

## ECONOMIA DOS EDIFÍCIOS (salários, impostos e materiais de obra).
## Se true, as fábricas são empresas privadas: pagam salários à população e o Estado
## recebe só o imposto (taxa nacional sobre o lucro operacional). Se false, a fábrica é
## estatal: o tesouro recebe o lucro operacional (receita - insumos - salários).
const FACTORIES_PRIVATE := true
## Salário pago por edifício produtivo, em % da receita que ele gera.
const WAGE_PCT := {
	"mine": 35, "farm": 28, "logging": 30, "workshop": 25,
	"textile": 30, "carpentry": 28, "smithy": 32, "steel": 38,
}
## Custo mensal fixo por nível dos edifícios de governo (escola e universidade já eram
## SCHOOL_UPKEEP / UNIVERSITY_UPKEEP do game_state; o quartel passa a ter soldo de instrutores).
const GOV_UPKEEP := {"school": 2, "university": 5, "barracks": 3}
## Empregos criados por nível (informativo: aparece na interface).
const JOBS_PER_LEVEL := {
	"school": 12, "university": 30, "barracks": 20, "mine": 300, "farm": 220, "logging": 180,
	"workshop": 120, "textile": 260, "carpentry": 140, "smithy": 160, "steel": 340,
}
## Materiais de obra por nível construído (unidades de bens). São pagos em ouro, ao preço
## de mercado do país, junto com o custo base (não há estoque no jogo).
const BUILD_MATERIALS := {
	"school": {"timber": 150},
	"university": {"timber": 300, "tools": 80},
	"barracks": {"timber": 200, "iron": 60},
	"mine": {"timber": 200, "tools": 60},
	"farm": {"timber": 150, "tools": 40},
	"logging": {"tools": 60, "iron": 60},
	"workshop": {"timber": 150, "tools": 60},
	"textile": {"timber": 250, "tools": 80},
	"carpentry": {"timber": 200, "tools": 50},
	"smithy": {"iron": 200, "timber": 150},
	"steel": {"iron": 300, "coal": 200, "tools": 80},
}

var id: int = 0
var name: String = ""
var port: int = -1                                 # célula marítima do porto (-1 = sem porto)
var factory: String = ""                            # "" ou chave de FACTORIES
var factory_level: int = 0
var city: String = ""                               # cidade-sede (município principal)
var capital_city: bool = false                      # sede é capital nacional
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
var bld: Dictionary = {}                            # escola, universidade, mina, fazenda, madeireira
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
	p.port = int(d.get("port", -1))
	p.city = str(d.get("city", ""))
	p.capital_city = bool(d.get("capital_city", false))
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


## Preços locais (% do preço-base) de cada país, indexados pelo id do dono; preenchido pelo Game.
static var country_prices: Array = []


## Preço de mercado de um bem no país dono desta província.
func price_of(good: String) -> int:
	if owner_id >= 0 and owner_id < country_prices.size():
		return int(country_prices[owner_id].get(good, 100))
	return 100


## Unidades do recurso produzidas por mês: população x terreno, com bônus de oficina.
@warning_ignore("integer_division")
func base_units() -> int:
	var tm: int = TERRAIN_MULT.get(terrain, 1000)
	return population * tm / 1500000


## Níveis atuais dos edifícios que mexem na produção do recurso.
func _extraction_levels() -> Dictionary:
	return {
		"workshop": workshop, "mine": int(bld.get("mine", 0)),
		"farm": int(bld.get("farm", 0)), "logging": int(bld.get("logging", 0)),
	}


@warning_ignore("integer_division")
func _units_for(lv: Dictionary) -> int:
	var boost: int = 25 * int(lv["workshop"]) + 35 * (int(lv["mine"]) + int(lv["farm"]))
	if resource_type == "timber":
		boost += 35 * int(lv["logging"])
	return base_units() * (100 + boost) / 100


@warning_ignore("integer_division")
func _side_timber_for(lv: Dictionary) -> int:
	if resource_type == "timber":
		return 0
	return base_units() * 60 * int(lv["logging"]) / 100


@warning_ignore("integer_division")
func _production_for(lv: Dictionary) -> int:
	var price: int = RESOURCE_PRICE.get(resource_type, 10)
	var pct: int = price_of(resource_type)
	var extra: int = _side_timber_for(lv) * base_price("timber") * price_of("timber") / 10000
	return _units_for(lv) * price * pct / 10000 + extra


func units() -> int:
	return _units_for(_extraction_levels())


## Madeira extra da madeireira em província cujo recurso principal não é madeira.
func side_timber() -> int:
	return _side_timber_for(_extraction_levels())


## Esta província pode receber a construção?
func can_host(kind: String) -> bool:
	if kind == "mine":
		return resource_type in MINE_RES
	if kind == "farm":
		return resource_type != "timber" and not (resource_type in MINE_RES)
	if kind == "logging":
		return resource_type == "timber" or terrain == "forest" or terrain == "jungle"
	return BUILDINGS.has(kind)


## Produção mensal em ouro (antes de impostos) = unidades x preço-base x preço de mercado.
func production() -> int:
	return _production_for(_extraction_levels())


## Imposto mensal que o dono recebe.
@warning_ignore("integer_division")
func monthly_tax(tax_pct: int) -> int:
	return FLAT_TAX + production() * tax_pct / 100


## Mão de obra máxima: 2% da população (+1% por nível de quartel).
@warning_ignore("integer_division")
func manpower_max() -> int:
	return population * (200 + 100 * barracks) / 10000


static func base_price(good: String) -> int:
	return int(RESOURCE_PRICE.get(good, PROCESSED.get(good, 10)))


## Lucro mensal da fábrica: receita dos produtos - custo dos insumos (a preço de mercado).
@warning_ignore("integer_division")
func factory_profit() -> int:
	if factory == "" or factory_level <= 0:
		return 0
	var f: Dictionary = FACTORIES[factory]
	var out: String = f["out"]
	var revenue: int = int(f["amount"]) * factory_level * base_price(out) * price_of(out) / 10000
	var cost := 0
	var ins: Dictionary = f["inputs"]
	for g in ins.keys():
		cost += int(ins[g]) * factory_level * base_price(g) * price_of(g) / 10000
	return revenue - cost


## Relatório mensal de um edifício no nível `level` (a preço de mercado do país).
## Edifícios de extração (mina, fazenda, madeireira, oficina): a receita é o ganho de produção
## que o edifício acrescenta; o imposto dela já é cobrado em monthly_tax, então `state_income` = 0.
## Fábricas: receita das vendas - insumos - salários; o Estado recebe o imposto (ver FACTORIES_PRIVATE).
## Governo (escola, universidade, quartel): só custo mensal (salários).
## Chaves: units, product, revenue, inputs [{good, amount, value}], inputs_cost, wages,
## operating, tax, net (lucro líquido do edifício), state_income, jobs.
@warning_ignore("integer_division")
func building_report(kind: String, level: int, tax_pct: int) -> Dictionary:
	var r := {
		"units": 0, "product": "", "revenue": 0, "inputs": [], "inputs_cost": 0, "wages": 0,
		"operating": 0, "tax": 0, "net": 0, "state_income": 0,
		"jobs": int(JOBS_PER_LEVEL.get(kind, 0)) * maxi(0, level),
	}
	if level <= 0 or not BUILDINGS.has(kind):
		return r
	var is_factory := FACTORIES.has(kind)
	if is_factory:
		var f: Dictionary = FACTORIES[kind]
		var out: String = f["out"]
		r["product"] = out
		r["units"] = int(f["amount"]) * level
		r["revenue"] = int(f["amount"]) * level * base_price(out) * price_of(out) / 10000
		var ins: Dictionary = f["inputs"]
		var cost := 0
		for g in ins.keys():
			var n: int = int(ins[g]) * level
			var v: int = n * base_price(g) * price_of(g) / 10000
			(r["inputs"] as Array).append({"good": g, "amount": n, "value": v})
			cost += v
		r["inputs_cost"] = cost
	elif WAGE_PCT.has(kind):
		var with_lv := _extraction_levels()
		var without_lv := with_lv.duplicate()
		with_lv[kind] = level
		without_lv[kind] = 0
		r["revenue"] = _production_for(with_lv) - _production_for(without_lv)
		r["units"] = (_units_for(with_lv) + _side_timber_for(with_lv)) - (_units_for(without_lv) + _side_timber_for(without_lv))
		r["product"] = "timber" if (kind == "logging" and resource_type != "timber") else resource_type
	if WAGE_PCT.has(kind):
		r["wages"] = int(r["revenue"]) * int(WAGE_PCT[kind]) / 100
		var op: int = int(r["revenue"]) - int(r["inputs_cost"]) - int(r["wages"])
		r["operating"] = op
		if is_factory and not FACTORIES_PRIVATE:
			r["net"] = op
			r["state_income"] = op
		else:
			var tx: int = maxi(0, op) * tax_pct / 100
			r["tax"] = tx
			r["net"] = op - tx
			r["state_income"] = tx if is_factory else 0
	else:
		var w: int = int(GOV_UPKEEP.get(kind, 0)) * level
		r["wages"] = w
		r["operating"] = -w
		r["net"] = -w
	return r


## O que o tesouro recebe por mês da fábrica desta província.
func factory_state_income(tax_pct: int) -> int:
	if factory == "" or factory_level <= 0:
		return 0
	return int(building_report(factory, factory_level, tax_pct)["state_income"])


## Materiais de obra para construir o nível `level`: [{good, amount, value}] (value em ouro).
@warning_ignore("integer_division")
func material_list(kind: String, level: int) -> Array:
	var out: Array = []
	var m: Dictionary = BUILD_MATERIALS.get(kind, {})
	for g in m.keys():
		var n: int = int(m[g]) * level
		out.append({"good": g, "amount": n, "value": n * base_price(g) * price_of(g) / 10000})
	return out


func material_cost(kind: String, level: int) -> int:
	var t := 0
	for row in material_list(kind, level):
		t += int(row["value"])
	return t


func building_level(kind: String) -> int:
	if FACTORIES.has(kind):
		return factory_level if factory == kind else 0
	if EXTRA_KINDS.has(kind):
		return int(bld.get(kind, 0))
	if kind == "workshop":
		return workshop
	if kind == "barracks":
		return barracks
	return 0


func set_building_level(kind: String, level: int) -> void:
	if FACTORIES.has(kind):
		factory = kind
		factory_level = level
	elif EXTRA_KINDS.has(kind):
		bld[kind] = level
	elif kind == "workshop":
		workshop = level
	elif kind == "barracks":
		barracks = level

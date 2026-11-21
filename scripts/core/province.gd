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
const PROCESSED := {"fabric": 30, "tools": 36, "furniture": 28, "steel": 42, "paper": 26, "machines": 60}
## Demanda-base por habitante (escala do mercado) dos bens processados; padrão 3000.
const PROCESSED_DEM := {"paper": 1500, "machines": 1200}
## Fábricas: por nível produzem `amount` unidades de `out` por mês e consomem `inputs` do mercado.
const FACTORIES := {
	"textile": {"out": "fabric", "amount": 100, "inputs": {"cotton": 60, "wool": 60}},
	"smithy": {"out": "tools", "amount": 100, "inputs": {"iron": 80, "timber": 40}},
	"carpentry": {"out": "furniture", "amount": 100, "inputs": {"timber": 100}},
	"steel": {"out": "steel", "amount": 100, "inputs": {"iron": 100, "coal": 100}},
	"paper": {"out": "paper", "amount": 100, "inputs": {"timber": 100}},
	"machinery": {"out": "machines", "amount": 100, "inputs": {"steel": 60, "tools": 60}},
}

## Métodos de produção das fábricas (estilo Victoria 3): trocam trabalho por produtividade.
## out/inp/jobs em % do método artesanal; `tech` = era mínima do país; `cost` = ouro por nível da fábrica.
const METHODS := [
	{"name": "Artesanal", "out": 100, "inp": 100, "jobs": 130, "tech": 0, "cost": 0},
	{"name": "Manufatura", "out": 130, "inp": 120, "jobs": 100, "tech": 1, "cost": 150},
	{"name": "Mecanizada", "out": 170, "inp": 150, "jobs": 70, "tech": 3, "cost": 320},
]
var method: int = 0   # método de produção da fábrica (índice em METHODS)
var rmethod: int = 0  # método de extração (fazenda, mina ou madeireira) — índice em METHODS


## Construção de extração principal da província ("mine", "farm" ou "logging"), "" se não houver.
func primary_extractor() -> String:
	if resource_type in MINE_RES:
		return "mine"
	if resource_type == "timber":
		return "logging"
	return "farm"


func extractor_level() -> int:
	return int(bld.get(primary_extractor(), 0))


func rmethod_pct(field: String) -> int:
	return int((METHODS[clampi(rmethod, 0, METHODS.size() - 1)] as Dictionary)[field])


func method_pct(field: String) -> int:
	return int((METHODS[clampi(method, 0, METHODS.size() - 1)] as Dictionary)[field])


## Unidades produzidas por mês pela fábrica (nível x quantidade-base x método).
@warning_ignore("integer_division")
func factory_units() -> int:
	if factory == "" or factory_level <= 0:
		return 0
	return int(FACTORIES[factory]["amount"]) * factory_level * method_pct("out") / 100


## Insumo consumido por mês (unidades do bem `good`) pela fábrica, no método atual.
@warning_ignore("integer_division")
func factory_input(good: String) -> int:
	if factory == "" or factory_level <= 0:
		return 0
	return int((FACTORIES[factory]["inputs"] as Dictionary).get(good, 0)) * factory_level * method_pct("inp") / 100


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
	"paper": {"tab": "ind", "name": "Fábrica de papel", "cost": 170, "tech": 2, "desc": "Madeira -> papel (escolas, bibliotecas, bancos)"},
	"machinery": {"tab": "ind", "name": "Fábrica de máquinas", "cost": 340, "tech": 4, "desc": "Aço + ferramentas -> máquinas (usinas, laboratórios)"},
	"carpentry": {"tab": "ind", "name": "Marcenaria", "cost": 130, "tech": 0, "desc": "Madeira -> móveis"},
	"smithy": {"tab": "ind", "name": "Ferraria", "cost": 180, "tech": 1, "desc": "Ferro + madeira -> ferramentas"},
	"steel": {"tab": "ind", "name": "Siderúrgica", "cost": 260, "tech": 3, "desc": "Ferro + carvão -> aço"},
	"hospital": {"tab": "gov", "name": "Hospital", "cost": 180, "tech": 1, "desc": "Crescimento populacional +0,03%/mês por nível"},
	"market": {"tab": "inf", "name": "Mercado", "cost": 160, "tech": 0, "desc": "+8% de imposto da província por nível"},
	"railway": {"tab": "inf", "name": "Ferrovia", "cost": 220, "tech": 2, "desc": "+12% de produção do recurso por nível"},
	"dock": {"tab": "inf", "name": "Cais comercial", "cost": 200, "tech": 1, "desc": "+60 de comércio marítimo (só litoral)"},
	# Construções liberadas por uma tecnologia específica ("req" = id em Techs.ALL).
	"library": {"tab": "gov", "name": "Biblioteca pública", "cost": 130, "tech": 0, "req": 4, "desc": "Conta como +1 escola na alfabetização"},
	"sanitation": {"tab": "gov", "name": "Esgoto e água encanada", "cost": 200, "tech": 0, "req": 11, "desc": "Crescimento populacional +0,04%/mês por nível"},
	"academy": {"tab": "gov", "name": "Academia militar", "cost": 190, "tech": 0, "req": 3, "desc": "Mão de obra militar +0,3% da população por nível"},
	"arsenal": {"tab": "gov", "name": "Arsenal nacional", "cost": 260, "tech": 0, "req": 14, "desc": "Manutenção do exército -2% por nível (máx. -20%)"},
	"lab": {"tab": "gov", "name": "Laboratório de pesquisa", "cost": 340, "tech": 0, "req": 22, "desc": "+6 pontos de pesquisa por mês por nível"},
	"irrigation": {"tab": "res", "name": "Irrigação", "cost": 150, "tech": 0, "req": 13, "desc": "+25% produção agrícola por nível"},
	"power_plant": {"tab": "ind", "name": "Usina elétrica", "cost": 380, "tech": 0, "req": 30, "desc": "+20% produção de recursos por nível"},
	"bank": {"tab": "inf", "name": "Banco", "cost": 240, "tech": 0, "req": 7, "desc": "+6% de imposto da província por nível"},
	"shipyard": {"tab": "inf", "name": "Estaleiro naval", "cost": 280, "tech": 0, "req": 15, "desc": "Manutenção da frota -10% por nível (só litoral)"},
	"depot": {"tab": "inf", "name": "Depósito de suprimentos", "cost": 220, "tech": 0, "req": 9, "desc": "Fonte de abastecimento do exército: alcance +2000 e +8 regimentos atendidos por nível"},
	"telegraph": {"tab": "inf", "name": "Central telegráfica", "cost": 220, "tech": 0, "req": 19, "desc": "+5% de comércio nacional por nível (máx. +30%)"},
}
const EXTRA_KINDS := ["school", "university", "mine", "farm", "logging", "hospital", "market", "railway", "dock",
	"library", "sanitation", "academy", "arsenal", "lab", "irrigation", "power_plant", "bank", "shipyard", "telegraph", "depot"]
const MINE_RES := ["coal", "iron", "salt", "gold"]

## ECONOMIA DOS EDIFÍCIOS (salários, impostos e materiais de obra).
## Se true, as fábricas são empresas privadas: pagam salários à população e o Estado
## recebe só o imposto (taxa nacional sobre o lucro operacional). Se false, a fábrica é
## estatal: o tesouro recebe o lucro operacional (receita - insumos - salários).
const FACTORIES_PRIVATE := true
## Salário pago por edifício produtivo, em % da receita que ele gera.
const WAGE_PCT := {
	"mine": 35, "farm": 28, "logging": 30, "workshop": 25,
	"textile": 30, "carpentry": 28, "smithy": 32, "steel": 38, "railway": 28, "paper": 28, "machinery": 36,
	"irrigation": 26, "power_plant": 30,
}
## Custo mensal fixo por nível dos edifícios de governo (escola e universidade já eram
## SCHOOL_UPKEEP / UNIVERSITY_UPKEEP do game_state; o quartel passa a ter soldo de instrutores).
const GOV_UPKEEP := {"school": 2, "university": 5, "barracks": 3, "hospital": 3, "market": 2, "dock": 3,
	"library": 1, "sanitation": 3, "academy": 4, "arsenal": 4, "lab": 6, "bank": 3, "shipyard": 4, "telegraph": 3, "depot": 3}
## Empregos criados por nível (informativo: aparece na interface).
const JOBS_PER_LEVEL := {
	"school": 12, "university": 30, "barracks": 20, "mine": 300, "farm": 220, "logging": 180,
	"workshop": 120, "textile": 260, "carpentry": 140, "smithy": 160, "steel": 340, "paper": 150, "machinery": 280,
	"hospital": 40, "market": 90, "railway": 200, "dock": 150,
	"library": 10, "sanitation": 50, "academy": 25, "arsenal": 60, "lab": 35, "irrigation": 120,
	"power_plant": 150, "bank": 60, "shipyard": 180, "telegraph": 40, "depot": 60,
}
## Materiais de obra por nível construído (unidades de bens). São pagos em ouro, ao preço
## de mercado do país, junto com o custo base (não há estoque no jogo).
const BUILD_MATERIALS := {
	"school": {"timber": 150, "paper": 40},
	"university": {"timber": 300, "tools": 80, "paper": 60},
	"barracks": {"timber": 200, "iron": 60},
	"mine": {"timber": 200, "tools": 60},
	"farm": {"timber": 150, "tools": 40},
	"logging": {"tools": 60, "iron": 60},
	"workshop": {"timber": 150, "tools": 60},
	"textile": {"timber": 250, "tools": 80},
	"carpentry": {"timber": 200, "tools": 50},
	"smithy": {"iron": 200, "timber": 150},
	"steel": {"iron": 300, "coal": 200, "tools": 80, "machines": 30},
	"paper": {"timber": 200, "tools": 60},
	"machinery": {"iron": 300, "timber": 150, "tools": 100},
	"hospital": {"timber": 200, "tools": 40},
	"market": {"timber": 180, "tools": 30},
	"railway": {"iron": 250, "timber": 150, "tools": 60},
	"dock": {"timber": 250, "iron": 80, "tools": 40},
	"library": {"timber": 120, "paper": 60},
	"sanitation": {"timber": 100, "iron": 120, "tools": 40},
	"academy": {"timber": 200, "iron": 60},
	"arsenal": {"iron": 250, "timber": 150, "tools": 60},
	"lab": {"timber": 200, "tools": 120, "iron": 40, "machines": 30},
	"irrigation": {"timber": 100, "tools": 60},
	"power_plant": {"iron": 300, "coal": 200, "tools": 100, "machines": 60},
	"bank": {"timber": 150, "tools": 30, "paper": 40},
	"shipyard": {"timber": 350, "iron": 150, "tools": 60},
	"telegraph": {"iron": 120, "tools": 60},
	"depot": {"timber": 200, "iron": 60, "tools": 20},
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
var core_owner: int = -1                          # dono no início (para marcar território conquistado)
var unrest: int = 0                                # agitação local 0..100 (B18): >=40 protestos, >=70 rebeldes
var region: String = ""                           # província histórica (data/regions.json)
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
	p.core_owner = p.owner_id
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
		"railway": int(bld.get("railway", 0)), "irrigation": int(bld.get("irrigation", 0)),
		"power_plant": int(bld.get("power_plant", 0)),
	}


@warning_ignore("integer_division")
func _units_for(lv: Dictionary) -> int:
	var boost: int = 25 * int(lv["workshop"]) + 35 * (int(lv["mine"]) + int(lv["farm"])) + 12 * int(lv["railway"])
	if resource_type == "timber":
		boost += 35 * int(lv["logging"])
	if resource_type != "timber" and not (resource_type in MINE_RES):
		boost += 25 * int(lv["irrigation"])
	boost += 20 * int(lv["power_plant"])
	var ext_pct: int = rmethod_pct("out") if extractor_level() > 0 else 100
	return base_units() * (100 + boost) / 100 * ext_pct / 100


@warning_ignore("integer_division")
func _side_timber_for(lv: Dictionary) -> int:
	if resource_type == "timber":
		return 0
	return base_units() * 60 * int(lv["logging"]) / 100


@warning_ignore("integer_division")
## Produtividade histórica da província (% do valor), definida no carregamento do mundo a partir do
## PIB per capita de 1836 do país de origem (data/real_economy_1836.json). Dado estático: não entra
## no estado salvo e vale igual para todos os jogadores. Afeta o valor (imposto, PIB), não as unidades.
var value_pct: int = 100


func _production_for(lv: Dictionary) -> int:
	var price: int = RESOURCE_PRICE.get(resource_type, 10)
	var pct: int = price_of(resource_type)
	var extra: int = _side_timber_for(lv) * base_price("timber") * price_of("timber") / 10000
	return (_units_for(lv) * price * pct / 10000 + extra) * value_pct / 100


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
	if kind == "dock" or kind == "shipyard":
		return port >= 0
	if kind == "irrigation":
		return resource_type != "timber" and not (resource_type in MINE_RES)
	return BUILDINGS.has(kind)


## Produção mensal em ouro (antes de impostos) = unidades x preço-base x preço de mercado.
func production() -> int:
	return _production_for(_extraction_levels())


## Imposto mensal que o dono recebe.
@warning_ignore("integer_division")
func monthly_tax(tax_pct: int) -> int:
	var base_tax: int = production() * tax_pct / 100
	return FLAT_TAX + base_tax * (100 + 8 * int(bld.get("market", 0)) + 6 * int(bld.get("bank", 0))) / 100


## Mão de obra máxima: 2% da população (+1% por nível de quartel).
@warning_ignore("integer_division")
func manpower_max() -> int:
	return population * (200 + 100 * barracks + 30 * int(bld.get("academy", 0))) / 10000


static func base_price(good: String) -> int:
	return int(RESOURCE_PRICE.get(good, PROCESSED.get(good, 10)))


## Lucro mensal da fábrica: receita dos produtos - custo dos insumos (a preço de mercado).
@warning_ignore("integer_division")
func factory_profit() -> int:
	if factory == "" or factory_level <= 0:
		return 0
	var f: Dictionary = FACTORIES[factory]
	var out: String = f["out"]
	var revenue: int = factory_units() * base_price(out) * price_of(out) / 10000
	var cost := 0
	var ins: Dictionary = f["inputs"]
	for g in ins.keys():
		cost += factory_input(str(g)) * base_price(g) * price_of(g) / 10000
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
	if kind == primary_extractor() and level > 0:
		r["jobs"] = int(r["jobs"]) * rmethod_pct("jobs") / 100
	if level <= 0 or not BUILDINGS.has(kind):
		return r
	var is_factory := FACTORIES.has(kind)
	if is_factory:
		var f: Dictionary = FACTORIES[kind]
		var out: String = f["out"]
		r["product"] = out
		var o_pct := 100
		var i_pct := 100
		if factory == kind:
			o_pct = method_pct("out")
			i_pct = method_pct("inp")
			r["jobs"] = int(r["jobs"]) * method_pct("jobs") / 100
		r["units"] = int(f["amount"]) * level * o_pct / 100
		r["revenue"] = int(r["units"]) * base_price(out) * price_of(out) / 10000
		var ins: Dictionary = f["inputs"]
		var cost := 0
		for g in ins.keys():
			var n: int = int(ins[g]) * level * i_pct / 100
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
		if kind == "market" or kind == "bank":
			r["revenue"] = production() * tax_pct / 100 * (8 if kind == "market" else 6) * level / 100
			r["net"] = int(r["revenue"]) - w
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


## Soma dos níveis de construções (desenvolvimento urbano/industrial); base da migração interna.
func development() -> int:
	var n: int = workshop + factory_level
	for k in EXTRA_KINDS:
		n += int(bld.get(k, 0))
	return n


## Atração local para a migração interna: desenvolvimento, capital e porto.
func pull() -> int:
	return 15 * mini(6, development()) + (30 if capital_city else 0) + (15 if port >= 0 else 0)


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

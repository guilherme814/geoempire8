extends Node
## Estado global e motor da simulação (autoload "Game").
##
## Regras de ouro (necessárias para o multiplayer P2P determinístico):
##  1. O estado de jogo só muda via apply_command() e _simulate_*().
##  2. Nada de randf()/Time/OS dentro da simulação: use `rng` (semente fixa) e inteiros.
##  3. A UI nunca altera o estado direto: ela chama submit_command().
##  4. step() é a ÚNICA função que avança o jogo. Offline ela é chamada por _process();
##     online (lockstep) quem chama é o Net, com a lista de comandos de cada frame.
##  5. Todo comando é validado aqui (dono, ouro, mão de obra...), igual em todos os pares.

const WORLD_PATH := "res://data/world.json"
const EVENTS_PATH := "res://data/events.json"
const SAVE_PATH := "user://savegame.json"
const EVENT_DECISION_DAYS := 30   # sem escolha, vale a 1ª opção (também vale para países sem jogador)

## Dias simulados por segundo em cada velocidade (0 = pausado).
const SPEED_TPS: Array[float] = [0.0, 2.0, 5.0, 10.0, 25.0]
const MAX_SPEED := 4
const ALLOW_DEBUG_COMMANDS := true
const DEFAULT_PLAYER_TAG := "GBR"

# Economia
const EXPENSE_PER_PROVINCE := 1
const REGIMENT_UPKEEP := 2
const MIN_START_TREASURY := 300
const MAX_TECH := 6                  # nível máximo de tecnologia
const RESEARCH_MAX_PCT := 30         # teto do investimento em pesquisa (% da renda)
## Eras tecnológicas: nome e o que cada nível libera além das construções (Province.BUILDINGS).
const TECH_ERAS := [
	{"name": "Manufatura artesanal", "extra": "Fragatas. Base do jogo."},
	{"name": "Vapor estacionário", "extra": "Navios de linha. Universidades, ferrarias, hospitais e cais."},
	{"name": "Vapor de transporte", "extra": "Vapores de guerra. Ferrovias."},
	{"name": "Siderurgia moderna", "extra": "Siderúrgicas."},
	{"name": "Telégrafo e burocracia", "extra": "+4% de imposto."},
	{"name": "Fábricas mecanizadas", "extra": "+4% de imposto e exércitos 10% mais baratos."},
	{"name": "Era industrial madura", "extra": "+4% de imposto e exércitos 20% mais baratos."},
]
# Nível de tecnologia inicial (x Country.TECH_STEP pontos) por país em 1836; o padrão é 0
const TECH_START := {
	"GBR": 4, "FRA": 3, "PRU": 3, "BEL": 3, "USA": 2, "NED": 2, "SUI": 2, "AUT": 2,
	"SWE": 2, "DEN": 2, "SAX": 2, "BAV": 2, "HAN": 2, "WUR": 2, "JAP": 1, "RUS": 1, "ESP": 1, "SAR": 1,
}
# Política interna: classes sociais e correntes ideológicas
const CLASSES := ["peasants", "workers", "aristocrats", "bourgeoisie", "officials", "soldiers"]
const IDEOLOGIES := ["conservatism", "liberalism", "socialism", "nationalism", "reactionism"]
const CLASS_PART := [2, 3, 40, 25, 15, 10]       # participação política por pessoa (relativa)
# afinidade base de cada classe (%) por corrente: [conserv., liberal., social., nacional., reacion.]
const CLASS_AFF := [[40, 10, 5, 15, 30], [10, 25, 45, 20, 0], [30, 0, 0, 10, 60],
	[25, 55, 5, 15, 0], [45, 25, 0, 25, 5], [30, 5, 0, 50, 15]]
const CLASS_RADICAL := [2, 2, 4, 1, 1, 3]        # corrente que cresce quando a classe fica insatisfeita
const LABOR_FORCE_PCT := 35                      # força de trabalho (% da população)
const SURPLUS_LABOR_PCT := 20                    # % da força de trabalho que busca emprego formal
const JOB_SCALE := 60                            # trabalhadores por vaga declarada em JOBS_PER_LEVEL
const UNEMP_BASE := 14                           # desemprego "neutro" para a satisfação
const REVOLT_STABILITY := 25                     # abaixo disso há risco de revolta
const UNREST_TAX_STABILITY := 40                 # abaixo disso a arrecadação cai
const SCHOOL_UPKEEP := 2         # por nível de escola / mês
const UNIVERSITY_UPKEEP := 5     # por nível de universidade / mês

# Exército
const REGIMENT_SIZE := 1000
const RECRUIT_COST := 30
const RECRUIT_DAYS := 30
const MAX_QUEUE_PER_PROVINCE := 3
const MANPOWER_REGEN_PCT := 10   # % do máximo recuperado por mês

# Guerra
const WAR_MIN_DAYS := 30         # dias de guerra antes de poder pedir paz
const SIEGE_DAYS := 10           # dias de ocupação até a província mudar de dono
const BATTLE_LOSS_PCT := 25      # % do exército inimigo (arredondado p/ cima) perdido por dia de batalha

# Alfabetização inicial (% por país em 1836, aproximada); o padrão é 10%
const LITERACY_START := {
	"GBR": 55, "FRA": 40, "PRU": 60, "SWE": 75, "DEN": 70, "NED": 65, "SUI": 60, "USA": 70,
	"AUT": 35, "RUS": 5, "OTT": 5, "ESP": 20, "POR": 15, "SAR": 25, "SIC": 15, "BEL": 45,
	"BAV": 55, "SAX": 60, "HAN": 55, "WUR": 60, "GRE": 15, "BRZ": 10, "MEX": 15, "ARG": 20,
	"CHL": 20, "JAP": 40, "QNG": 20, "BIC": 8, "HAW": 30,
}
const LITERACY_MAX := 950        # teto (95,0%)

# Marinha e comércio
const SHIP_COST := 80
const SHIP_DAYS := 40
const SHIP_UPKEEP := 3
const SEA_SPEED := 3             # células da grade por dia
const SHIP_CAP := 120            # unidades de comércio marítimo por navio por mês
const DOCK_CAP := 60             # comércio marítimo extra por nível de cais comercial
const PORT_CAP := 40             # capacidade básica por porto (província costeira)
const PRICE_MIN := 70
const PRICE_MAX := 140
const TRADE_TARIFF_PCT := 10     # ganho do importador (tarifas) sobre o valor importado

# Diplomacia
const IMPROVE_COST := 50
const ALLIANCE_MIN_OPINION := 40
const VASSAL_TRIBUTE_PCT := 25     # % da renda do vassalo enviada ao suserano
const ANNEX_MIN_DAYS := 360        # tempo mínimo como vassalo antes de poder ser anexado
const ANNEX_COST_PER_PROVINCE := 60
const SCORE_INDEMNITY := 15        # pontuação de guerra mínima para cada termo de paz
const SCORE_VASSAL := 45
const SCORE_ANNEX := 75
const CAPITAL_SCORE := 30          # bônus por capturar a capital inimiga
const TRUCE_DAYS := 360          # após a paz, ninguém declara guerra por 1 ano
const AI_WAR_GRACE_TICKS := 360  # a IA só declara guerra depois do primeiro ano
const AI_WAR_CHANCE := 12        # 1 em N por mês, por país elegível

var loaded: bool = false
var map_size: Vector2 = Vector2(3072.0, 1394.0)
var provinces: Array[Province] = []
var countries: Array[Country] = []
var clock: GameClock = GameClock.new()
var graph: ProvinceGraph

var armies: Dictionary = {}      # id -> Army
var training: Array = []         # [{province, owner, days}]
var next_army_id: int = 1
var fleets: Dictionary = {}        # id -> Fleet
var next_fleet_id: int = 1
var sea_cell: int = 12             # lado da célula da grade marítima (px do mapa)
var sea_w: int = 0
var sea_h: int = 0
var sea_astar: AStarGrid2D = null
var wars: Array = []             # [{a, b, days}] com a < b
var sieges: Dictionary = {}      # província -> {by, days}
# Mercado mundial: preço (% do base) por recurso, demanda-base e população de referência.
var local_price: Array = []        # por país: {bem -> % do preço-base}
var gates: Array = []              # passagens estratégicas (data/sea_gates.json)
var gate_flow: Array = []          # carga que passou por cada passagem no último mês (derivado)
var prov_zone: PackedInt32Array = PackedInt32Array()
var _zone_paths: Array = []        # [zona][zona] -> lista de índices de passagens
var embargoes: Array = []          # emissor*1000+alvo
var trade_imp: Array = []          # por país: {bem -> unidades} (derivado, mostra o último mês)
var trade_exp: Array = []
var trade_bonus: Array = []
var market_dem: Dictionary = {}
var market_pop0: int = 1
var relations: Dictionary = {}   # par -> opinião (-100..100)
var alliances: Array = []        # pares aliados
var peace_offers: Array = []       # propostas de paz pendentes (IA -> jogador): from, to, winner, term, tick
var peace_cd: Dictionary = {}      # par -> tick até o qual a IA não oferece paz de novo
var truces: Dictionary = {}      # par -> tick em que a trégua acaba

var event_defs: Array = []         # definições de data/events.json (somente leitura)
var pending_events: Array = []     # [{uid, country, event, days}]
var fired_events: Dictionary = {}  # "pais|evento" -> true (eventos "once")
var next_event_uid: int = 1

var tick: int = 0     # dias simulados
var frame: int = 0    # passos executados (inclui frames com o jogo pausado)
var speed: int = 1
var player_country: int = 0
var lockstep: bool = false   # true quando o Net controla o avanço do tempo
var world_seed: int = 1836
var history: Dictionary = {}       # dados históricos de 1836 por tag (data/history_1836.json)
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _acc: float = 0.0


func _ready() -> void:
	load_world()


func _process(delta: float) -> void:
	if not loaded or lockstep or speed <= 0:
		return
	_acc += delta
	var interval: float = 1.0 / SPEED_TPS[speed]
	var steps := 0
	while _acc >= interval and steps < 8:
		_acc -= interval
		step()
		steps += 1
		if speed <= 0:
			break
	if steps >= 8:
		_acc = 0.0   # evita espiral da morte em dispositivos lentos


# ---------------------------------------------------------------------------
# Carregamento do mundo
# ---------------------------------------------------------------------------
func _load_sea_grid(dict: Dictionary) -> void:
	sea_astar = null
	sea_w = 0
	sea_h = 0
	if not dict.has("sea_grid"):
		return
	var g: Dictionary = dict["sea_grid"]
	sea_cell = int(g["cell"])
	sea_w = int(g["w"])
	sea_h = int(g["h"])
	var rows: Array = g["rows"]
	sea_astar = AStarGrid2D.new()
	sea_astar.region = Rect2i(0, 0, sea_w, sea_h)
	sea_astar.cell_size = Vector2(1, 1)
	sea_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	sea_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	sea_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	sea_astar.update()
	for y in sea_h:
		var row: String = rows[y]
		for x in sea_w:
			if row[x] != "1":
				sea_astar.set_point_solid(Vector2i(x, y), true)


func is_sea_cell(cell: int) -> bool:
	if sea_astar == null or cell < 0 or cell >= sea_w * sea_h:
		return false
	return not sea_astar.is_point_solid(Vector2i(cell % sea_w, cell / sea_w))


func cell_at(world_pos: Vector2) -> int:
	var x := int(world_pos.x) / sea_cell
	var y := int(world_pos.y) / sea_cell
	if x < 0 or y < 0 or x >= sea_w or y >= sea_h:
		return -1
	return y * sea_w + x


func cell_center(cell: int) -> Vector2:
	return Vector2(float(cell % sea_w) + 0.5, float(cell / sea_w) + 0.5) * float(sea_cell)


## Rota marítima entre células (sem incluir a de partida); vazio se não houver caminho.
func find_sea_path(from_cell: int, to_cell: int) -> Array[int]:
	var out: Array[int] = []
	if sea_astar == null or not is_sea_cell(from_cell) or not is_sea_cell(to_cell) or from_cell == to_cell:
		return out
	var pts: Array[Vector2i] = sea_astar.get_id_path(Vector2i(from_cell % sea_w, from_cell / sea_w), Vector2i(to_cell % sea_w, to_cell / sea_w))
	for i in range(1, pts.size()):
		out.append(pts[i].y * sea_w + pts[i].x)
	return out


func fleet_eta_days(f: Fleet) -> int:
	return (f.path.size() + SEA_SPEED - 1) / SEA_SPEED


## Navios novos entram na frota parada do dono naquele porto (ou criam uma).
func _add_ships(pid: int, owner: int, count: int) -> void:
	var cell: int = provinces[pid].port
	if cell < 0:
		return
	countries[owner].ships += count
	for id in fleets.keys():
		var f: Fleet = fleets[id]
		if f.owner_id == owner and f.cell == cell and not f.is_moving():
			f.ships += count
			Events.fleet_changed.emit(f.id)
			return
	var n := Fleet.new()
	n.id = next_fleet_id
	next_fleet_id += 1
	n.owner_id = owner
	n.ships = count
	n.cell = cell
	fleets[n.id] = n
	Events.fleet_changed.emit(n.id)


## Navegação, fusão de frotas paradas e batalhas navais (mesma célula, países em guerra).
@warning_ignore("integer_division")
func _advance_fleets() -> void:
	if fleets.is_empty():
		return
	var ids: Array = fleets.keys()
	ids.sort()
	for id in ids:
		var f: Fleet = fleets[id]
		var steps := SEA_SPEED
		while steps > 0 and not f.path.is_empty():
			f.cell = f.path[0]
			f.path.remove_at(0)
			steps -= 1
		Events.fleet_changed.emit(f.id)
	# fusão e batalhas por célula
	var by_cell := {}
	for id in ids:
		if not fleets.has(id):
			continue
		var f: Fleet = fleets[id]
		if not by_cell.has(f.cell):
			by_cell[f.cell] = []
		by_cell[f.cell].append(f)
	var cells: Array = by_cell.keys()
	cells.sort()
	for cell in cells:
		var list: Array = by_cell[cell]
		for i in list.size():
			for j in range(i + 1, list.size()):
				var x: Fleet = list[i]
				var y: Fleet = list[j]
				if x.ships <= 0 or y.ships <= 0:
					continue
				if x.owner_id == y.owner_id:
					if not x.is_moving() and not y.is_moving():
						x.ships += y.ships
						y.ships = 0
					continue
				if not at_war(x.owner_id, y.owner_id):
					continue
				_naval_round(x, y)
	# Combate também entre frotas em células vizinhas (alcance de canhão).
	for ia in ids.size():
		if not fleets.has(ids[ia]):
			continue
		var fa: Fleet = fleets[ids[ia]]
		for ib in range(ia + 1, ids.size()):
			if not fleets.has(ids[ib]):
				continue
			var fb: Fleet = fleets[ids[ib]]
			if fa.ships <= 0 or fb.ships <= 0 or fa.cell == fb.cell or fa.owner_id == fb.owner_id:
				continue
			if not at_war(fa.owner_id, fb.owner_id) or _cell_dist(fa.cell, fb.cell) > 1:
				continue
			_naval_round(fa, fb)
	for id in ids:
		var f: Fleet = fleets[id]
		if f.ships <= 0:
			fleets.erase(id)
			Events.fleet_removed.emit(id)


## Um round de combate naval. A força de cada navio cresce com a tecnologia do dono
## (fragata -> navio de linha -> vapor de guerra); com tecnologias iguais é a regra simples.
func _naval_round(x: Fleet, y: Fleet) -> void:
	var qx: int = 10 + 3 * countries[x.owner_id].tech_level()
	var qy: int = 10 + 3 * countries[y.owner_id].tech_level()
	var loss_x := ((y.ships * qy) * BATTLE_LOSS_PCT / 100 + qx - 1) / qx
	var loss_y := ((x.ships * qx) * BATTLE_LOSS_PCT / 100 + qy - 1) / qy
	if x.ships * qx == y.ships * qy:
		if rng.randi_range(0, 1) == 0:
			loss_y = 0
		else:
			loss_x = 0
	loss_x = maxi(1, mini(loss_x, x.ships)) if loss_x > 0 else 0
	loss_y = maxi(1, mini(loss_y, y.ships)) if loss_y > 0 else 0
	x.ships -= loss_x
	y.ships -= loss_y
	countries[x.owner_id].ships = maxi(0, countries[x.owner_id].ships - loss_x)
	countries[y.owner_id].ships = maxi(0, countries[y.owner_id].ships - loss_y)


## Nome da classe de navio que o país constrói, conforme a tecnologia.
func ship_class_name(c: Country) -> String:
	var t: int = c.tech_level()
	if t >= 2:
		return "Vapor de guerra"
	if t >= 1:
		return "Navio de linha"
	return "Fragata"


## Distância (Chebyshev) entre duas células da grade marítima.
func _cell_dist(a: int, b: int) -> int:
	if sea_w <= 0:
		return 1000
	return maxi(absi(a % sea_w - b % sea_w), absi(a / sea_w - b / sea_w))


## Frotas ociosas de um país em guerra: caçam a frota inimiga mais próxima (se não estiverem
## em desvantagem) ou bloqueiam o porto inimigo mais próximo; sem chance, voltam ao porto.
func _auto_fleets(c: Country) -> void:
	var enemies := wars_of(c.id)
	if enemies.is_empty():
		return
	var ids: Array = fleets.keys()
	ids.sort()
	for id in ids:
		var f: Fleet = fleets[id]
		if f.owner_id != c.id or f.is_moving() or f.ships <= 0:
			continue
		var foe: Fleet = null
		var foe_d := 1000000
		for eid in ids:
			var e: Fleet = fleets[eid]
			if not enemies.has(e.owner_id) or e.ships <= 0:
				continue
			var d := _cell_dist(f.cell, e.cell)
			if d < foe_d:
				foe_d = d
				foe = e
		var target := -1
		if foe != null and foe_d <= 60:
			if f.ships * 10 >= foe.ships * 8:
				target = foe.cell
			else:
				target = _nearest_own_port_cell(c, f.cell)
		elif f.ships >= 2:
			var best_d := 1000000
			for p in provinces:
				if p.port >= 0 and enemies.has(p.owner_id):
					var d2 := _cell_dist(f.cell, p.port)
					if d2 < best_d:
						best_d = d2
						target = p.port
		if target >= 0 and target != f.cell and is_sea_cell(target):
			var path := find_sea_path(f.cell, target)
			if not path.is_empty():
				f.path = path
				Events.fleet_changed.emit(f.id)


func _nearest_own_port_cell(c: Country, from_cell: int) -> int:
	var best := -1
	var best_d := 1000000
	for pid in c.province_ids:
		var p := provinces[pid]
		if p.port >= 0:
			var d := _cell_dist(from_cell, p.port)
			if d < best_d:
				best_d = d
				best = p.port
	return best


func fleets_of(cid: int) -> Array:
	var out: Array = []
	var ids: Array = fleets.keys()
	ids.sort()
	for id in ids:
		if (fleets[id] as Fleet).owner_id == cid:
			out.append(fleets[id])
	return out


func load_world(path: String = WORLD_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GeoEmpire: não foi possível abrir %s" % path)
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GeoEmpire: JSON inválido em %s" % path)
		return false
	var dict: Dictionary = data

	var ms: Array = dict["map_size"]
	map_size = Vector2(float(ms[0]), float(ms[1]))

	countries.clear()
	provinces.clear()
	armies.clear()
	fleets.clear()
	next_fleet_id = 1
	training.clear()
	wars.clear()
	sieges.clear()
	relations.clear()
	alliances.clear()
	truces.clear()
	peace_offers.clear()
	peace_cd.clear()
	embargoes.clear()
	next_army_id = 1
	_load_sea_grid(dict)
	pending_events.clear()
	fired_events.clear()
	next_event_uid = 1
	_load_event_defs()
	for cd in dict["countries"]:
		countries.append(Country.from_dict(cd))
	for pd in dict["provinces"]:
		provinces.append(Province.from_dict(pd))
	_apply_regions()
	_load_gates()

	# Os índices dos arrays precisam ser iguais aos ids (acesso O(1) em todo o código).
	for i in countries.size():
		if countries[i].id != i:
			push_error("GeoEmpire: ids de países precisam ser sequenciais")
			return false
	for i in provinces.size():
		if provinces[i].id != i:
			push_error("GeoEmpire: ids de províncias precisam ser sequenciais")
			return false

	world_seed = int(dict.get("seed", world_seed))
	rng.seed = world_seed
	var sd: Array = dict.get("start_date", [1836, 1, 1])
	clock = GameClock.new()
	clock.year = int(sd[0])
	clock.month = int(sd[1])
	clock.day = int(sd[2])
	tick = 0
	frame = 0
	speed = 1

	_load_history()
	_rebuild_all_countries()
	_init_market()
	graph = ProvinceGraph.new()
	graph.setup(provinces)

	for c in countries:
		c.literacy = int(LITERACY_START.get(c.tag, 10)) * 10
		c.tech_pts = int(TECH_START.get(c.tag, 0)) * Country.TECH_STEP
		c.lit_acc = 0
		_init_laws(c)
		# O desenvolvimento industrial histórico adianta a tecnologia inicial.
		var hh: Dictionary = history.get(c.tag, {})
		c.tech_pts = maxi(c.tech_pts, (int(hh.get("ind", 0)) * 3 / 5) * Country.TECH_STEP)
		if not hh.is_empty():
			c.tax_pct = 20 + 4 * int(hh.get("tax", 2))   # capacidade fiscal histórica
		var prof: Dictionary = hh.get("profile", {})
		if not prof.is_empty():
			# Perfil de referência (países principais): sobrepõe os valores genéricos.
			c.literacy = int(prof.get("lit", c.literacy / 10)) * 10
			c.tech_pts = int(prof.get("tech", c.tech_level())) * Country.TECH_STEP
			Laws.apply_profile(c.laws, prof.get("laws", {}))
	_apply_historical_productivity()
	for c in countries:
		var gold_months: int = int(history.get(c.tag, {}).get("profile", {}).get("gold", 8))
		c.treasury = maxi(MIN_START_TREASURY, int(estimate_monthly(c)["income"]) * gold_months)
		if c.is_alive():
			# Exército inicial na capital, proporcional à população histórica.
			var h: Dictionary = history.get(c.tag, {})
			var regs := clampi(int(c.pop_total * 0.6), 1, 40)
			if not h.is_empty():
				# Capacidade militar histórica (0-5): de 80% a 140% do exército base.
				regs = clampi(regs * (60 + 20 * int(h.get("army", 2))) / 100, 1, 50)
			_add_regiments(c.capital, c.id, regs)
			if not h.is_empty():
				var nv: int = int(h.get("navy", 1))
				if nv >= 2:
					_add_ships(_port_province_of(c), c.id, (nv - 1) * nv)

	for c in countries:
		if c.is_alive():
			var pol := politics_of(c)
			for i in 6:
				c.sat[i] = clampi(int(pol["target"][i]), 0, 100)
			c.stability = int(politics_of(c)["stability"])
	player_country = 0
	for c in countries:
		if c.tag == DEFAULT_PLAYER_TAG:
			player_country = c.id
	loaded = true
	Events.world_loaded.emit()
	return true


# ---------------------------------------------------------------------------
# Comandos
# ---------------------------------------------------------------------------
const HISTORY_PATH := "res://data/history_1836.json"


const GATES_PATH := "res://data/sea_gates.json"
const GATE_TOLL_BASE := 100


func _load_gates() -> void:
	gates = []
	gate_flow = []
	prov_zone = PackedInt32Array()
	prov_zone.resize(provinces.size())
	for p in provinces:
		prov_zone[p.id] = SeaZones.zone_of(p.lon, p.lat)
	if FileAccess.file_exists(GATES_PATH):
		var f := FileAccess.open(GATES_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Array:
				gates = parsed
	for g in gates:
		gate_flow.append(0)
	# Menor caminho (em passagens) entre cada par de zonas.
	var n := SeaZones.COUNT
	var paths: Array = []
	var cost: Array = []
	for a in n:
		paths.append([])
		cost.append([])
		for b in n:
			paths[a].append([])
			cost[a].append(0 if a == b else 1000000)
	for ed in SeaZones.EDGES:
		var gi := -1
		for i in gates.size():
			if str(gates[i]["id"]) == str(ed[2]):
				gi = i
		var seg: Array = [] if gi < 0 else [gi]
		var w: int = 1 + 100 * seg.size()
		for dir in 2:
			var a: int = int(ed[0]) if dir == 0 else int(ed[1])
			var b: int = int(ed[1]) if dir == 0 else int(ed[0])
			if w < int(cost[a][b]):
				cost[a][b] = w
				paths[a][b] = seg.duplicate()
	for k in n:
		for a in n:
			for b in n:
				var w2: int = int(cost[a][k]) + int(cost[k][b])
				if w2 < int(cost[a][b]):
					cost[a][b] = w2
					paths[a][b] = (paths[a][k] as Array) + (paths[k][b] as Array)
	_zone_paths = paths


## Dono atual da passagem (-1 = ninguém): quem controla a província-âncora.
func gate_controller(gi: int) -> int:
	if gi < 0 or gi >= gates.size():
		return -1
	var pid: int = int(gates[gi]["prov"])
	return provinces[pid].owner_id if pid >= 0 and pid < provinces.size() else -1


## Zonas em que um país tem porto (máscara de bits).
func _zone_mask_of_all() -> Array:
	var masks: Array = []
	for i in countries.size():
		masks.append(0)
	for p in provinces:
		if p.port >= 0 and p.owner_id >= 0 and p.owner_id < masks.size():
			masks[p.owner_id] = int(masks[p.owner_id]) | (1 << prov_zone[p.id])
	return masks


## Passagens que a rota marítima i <-> e precisa cruzar (a combinação de zonas com menos passagens).
func _route_gates(mi: int, me: int) -> Array:
	var best: Array = []
	var best_n := 1000
	for za in SeaZones.COUNT:
		if (mi >> za) & 1 == 0:
			continue
		for zb in SeaZones.COUNT:
			if (me >> zb) & 1 == 0:
				continue
			var gl: Array = _zone_paths[za][zb]
			if gl.size() < best_n:
				best_n = gl.size()
				best = gl
	return best


const REGIONS_PATH := "res://data/regions.json"


## Agrupa as províncias-célula em províncias históricas e dá nomes de época (dado estático).
func _apply_regions() -> void:
	if not FileAccess.file_exists(REGIONS_PATH):
		return
	var f := FileAccess.open(REGIONS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	for tag in (parsed as Dictionary).keys():
		var entry: Dictionary = parsed[tag]
		var regs: Dictionary = entry.get("regions", {})
		for rname in regs.keys():
			for pid in regs[rname]:
				if int(pid) >= 0 and int(pid) < provinces.size():
					provinces[int(pid)].region = str(rname)
		var nm: Dictionary = entry.get("names", {})
		for k in nm.keys():
			if int(k) >= 0 and int(k) < provinces.size():
				provinces[int(k)].name = str(nm[k])


## Província com porto para a frota inicial: a capital, ou a primeira do país que tenha porto.
func _port_province_of(c: Country) -> int:
	if c.capital >= 0 and c.capital < provinces.size() and provinces[c.capital].port >= 0:
		return c.capital
	for pid in c.province_ids:
		if provinces[pid].port >= 0:
			return pid
	return c.capital


func _load_history() -> void:
	history = {}
	if not FileAccess.file_exists(HISTORY_PATH):
		return
	var f := FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		history = parsed


func _init_laws(c: Country) -> void:
	var h: Dictionary = history.get(c.tag, {})
	c.laws = Laws.defaults_for(h)
	c.law_cd = []
	for i in Laws.group_count():
		c.law_cd.append(0)


## Modificadores somados das leis em vigor (ver Laws.modifiers).
func law_mods(c: Country) -> Dictionary:
	return Laws.modifiers(c.laws)


## Por que a lei não pode ser aprovada agora ("" = pode).
func law_block_reason(c: Country, gi: int, oi: int) -> String:
	if gi < 0 or gi >= Laws.group_count() or c.laws.size() != Laws.group_count():
		return "Lei inválida"
	var opts: Array = Laws.group(gi)["opts"]
	if oi < 0 or oi >= opts.size():
		return "Lei inválida"
	if int(c.laws[gi]) == oi:
		return "Já está em vigor"
	var o: Dictionary = opts[oi]
	if int(c.law_cd[gi]) > 0:
		return "Aguarde %d meses" % int(c.law_cd[gi])
	if c.tech_level() < int(o["tech"]):
		return "Requer tecnologia nível %d" % int(o["tech"])
	if c.literacy < int(o["lit"]):
		return "Requer alfabetização %.1f%%" % (float(int(o["lit"])) / 10.0)
	if c.treasury < int(o["cost"]):
		return "Libras insuficientes"
	return ""


func _enact_law(c: Country, gi: int, oi: int) -> void:
	var old: Dictionary = Laws.option(gi, int(c.laws[gi]))
	var nw: Dictionary = Laws.option(gi, oi)
	c.treasury -= int(nw["cost"])
	c.laws[gi] = oi
	c.law_cd[gi] = Laws.COOLDOWN_MONTHS
	# Choque imediato: metade da diferença de efeito sobre cada classe.
	var osd: Dictionary = old["fx"].get("sat", {})
	var nsd: Dictionary = nw["fx"].get("sat", {})
	for i in 6:
		var dv: int = int(nsd.get(i, 0)) - int(osd.get(i, 0))
		c.sat[i] = clampi(int(c.sat[i]) + dv / Laws.SAT_SHOCK_DIV, 0, 100)
	c.stability = int(politics_of(c)["stability"])
	Events.treasury_changed.emit(c.id)
	if c.id == player_country:
		Events.notice.emit("Lei aprovada: %s." % str(nw["name"]))


## Ponto de entrada de TODA ação do jogador. Online, o comando vai para o Net,
## que o distribui para todos os pares e o executa no mesmo frame em todos.
func submit_command(cmd: Dictionary) -> void:
	cmd["issuer"] = player_country
	if Net.is_online():
		Net.send_command(cmd)
	else:
		apply_command(cmd)


## Executa um comando. Chamado em todos os pares, na mesma ordem.
func apply_command(cmd: Dictionary) -> void:
	var t: String = str(cmd.get("type", ""))
	var issuer: int = int(cmd.get("issuer", -1))

	if t == Cmd.SET_SPEED:
		speed = clampi(int(cmd.get("speed", 1)), 0, MAX_SPEED)
		Events.speed_changed.emit(speed)

	elif t == Cmd.SET_TAX:
		var cid: int = int(cmd.get("country", -1))
		if cid < 0 or cid >= countries.size() or cid != issuer:
			return
		countries[cid].tax_pct = clampi(int(cmd.get("pct", 30)), 0, 100)
		Events.treasury_changed.emit(cid)

	elif t == Cmd.SET_RESEARCH:
		if issuer < 0 or issuer >= countries.size():
			return
		countries[issuer].research_pct = clampi(int(cmd.get("pct", 0)) / 5 * 5, 0, RESEARCH_MAX_PCT)
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.SET_AUTO_FRONT:
		if issuer >= 0 and issuer < countries.size():
			countries[issuer].auto_front = bool(cmd.get("enabled", true))

	elif t == Cmd.ENACT_LAW:
		if issuer < 0 or issuer >= countries.size():
			return
		var lc := countries[issuer]
		var lg: int = int(cmd.get("group", -1))
		var lo: int = int(cmd.get("option", -1))
		if law_block_reason(lc, lg, lo) != "":
			return
		_enact_law(lc, lg, lo)

	elif t == Cmd.RECRUIT:
		var pid: int = int(cmd.get("province", -1))
		if not can_recruit(pid, issuer):
			return
		_do_recruit(pid, issuer)

	elif t == Cmd.BUILD:
		var pid: int = int(cmd.get("province", -1))
		var kind: String = str(cmd.get("kind", ""))
		if not can_build(pid, issuer, kind):
			return
		var p := provinces[pid]
		countries[issuer].treasury -= build_total_cost(p, kind)
		p.set_building_level(kind, p.building_level(kind) + 1)
		Events.province_updated.emit(pid)
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.MOVE_ARMY:
		var a: Army = armies.get(int(cmd.get("army", -1)))
		var dest: int = int(cmd.get("to", -1))
		if a == null or a.owner_id != issuer or dest < 0 or dest >= provinces.size():
			return
		_order_move(a, dest)

	elif t == Cmd.STOP_ARMY:
		var a: Army = armies.get(int(cmd.get("army", -1)))
		if a == null or a.owner_id != issuer or not a.is_moving():
			return
		var next_hop: int = a.path[0]
		a.path.clear()
		a.path.append(next_hop)   # termina o trecho atual e para
		Events.army_changed.emit(a.id)

	elif t == Cmd.DISBAND_ARMY:
		var a: Army = armies.get(int(cmd.get("army", -1)))
		if a == null or a.owner_id != issuer:
			return
		# Os homens voltam para a mão de obra da província onde estão.
		var home := provinces[a.province_id]
		home.manpower = mini(home.manpower_max(), home.manpower + a.regiments * REGIMENT_SIZE)
		armies.erase(a.id)
		Events.army_removed.emit(a.id)
		Events.province_updated.emit(home.id)
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.CHOOSE_EVENT:
		var uid: int = int(cmd.get("uid", -1))
		var option: int = int(cmd.get("option", 0))
		var found := false
		for i in pending_events.size():
			var pe: Dictionary = pending_events[i]
			if int(pe["uid"]) != uid:
				continue
			if int(pe["country"]) != issuer:
				return
			pending_events.remove_at(i)
			_apply_event_option(pe, option)
			found = true
			break
		if not found:
			return
		Events.game_event_changed.emit()

	elif t == Cmd.MOVE_FLEET:
		var f: Fleet = fleets.get(int(cmd.get("fleet", -1)))
		if f == null or f.owner_id != issuer:
			return
		var to_cell: int = int(cmd.get("cell", -1))
		if not is_sea_cell(to_cell):
			return
		f.path = find_sea_path(f.cell, to_cell)
		Events.fleet_changed.emit(f.id)

	elif t == Cmd.STOP_FLEET:
		var f2: Fleet = fleets.get(int(cmd.get("fleet", -1)))
		if f2 == null or f2.owner_id != issuer:
			return
		f2.path.clear()
		Events.fleet_changed.emit(f2.id)

	elif t == Cmd.BUILD_SHIP:
		var pid: int = int(cmd.get("province", -1))
		if not can_build_ship(pid, issuer):
			return
		countries[issuer].treasury -= SHIP_COST
		training.append({"province": pid, "owner": issuer, "days": SHIP_DAYS, "kind": "ship"})
		Events.province_updated.emit(pid)
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.EMBARGO:
		var target: int = int(cmd.get("target", -1))
		if not can_embargo(issuer, target):
			return
		embargoes.append(issuer * 1000 + target)
		relations[_pair(issuer, target)] = opinion(issuer, target) - 15
		if target == player_country:
			Events.notice.emit("%s decretou embargo contra você!" % countries[issuer].name)
		Events.war_changed.emit()

	elif t == Cmd.LIFT_EMBARGO:
		var target: int = int(cmd.get("target", -1))
		if not embargoes.has(issuer * 1000 + target):
			return
		embargoes.erase(issuer * 1000 + target)
		Events.war_changed.emit()

	elif t == Cmd.DECLARE_WAR:
		var target: int = int(cmd.get("target", -1))
		if not can_declare_war(issuer, target):
			return
		_start_war(issuer, target)

	elif t == Cmd.MAKE_PEACE:
		var target: int = int(cmd.get("target", -1))
		var term := str(cmd.get("term", "white"))
		if not can_peace_term(issuer, target, term):
			if issuer == player_country:
				Events.notice.emit("Pontuação de guerra insuficiente para esses termos.")
			return
		if not is_human(target) and not AiDiplomacy.accepts(self, target, issuer, term):
			if issuer == player_country:
				Events.notice.emit("%s recusou esses termos (disposição a negociar: %s)." % [countries[target].name, AiDiplomacy.willingness(self, target, issuer)])
			return
		_apply_peace(issuer, target, term)

	elif t == Cmd.ACCEPT_PEACE:
		var idx := _offer_index(int(cmd.get("from", -1)), issuer)
		if idx < 0:
			return
		var o: Dictionary = peace_offers[idx]
		peace_offers.remove_at(idx)
		var winner: int = int(o["winner"])
		var loser: int = int(o["from"]) if winner == int(o["to"]) else int(o["to"])
		if not can_peace_term(winner, loser, str(o["term"])):
			Events.war_changed.emit()
			return
		_apply_peace(winner, loser, str(o["term"]))

	elif t == Cmd.REJECT_PEACE:
		var idx2 := _offer_index(int(cmd.get("from", -1)), issuer)
		if idx2 < 0:
			return
		peace_offers.remove_at(idx2)
		peace_cd[_pair(int(cmd.get("from", -1)), issuer)] = tick + AiDiplomacy.REFUSE_COOLDOWN
		Events.war_changed.emit()

	elif t == Cmd.RELEASE_VASSAL:
		var target: int = int(cmd.get("target", -1))
		if target < 0 or target >= countries.size() or countries[target].overlord != issuer:
			return
		_free_vassal(target, true)

	elif t == Cmd.ANNEX_VASSAL:
		var target: int = int(cmd.get("target", -1))
		if not can_annex_vassal(issuer, target):
			if issuer == player_country:
				Events.notice.emit("Não é possível anexar: tempo de vassalagem ou libras insuficientes.")
			return
		countries[issuer].treasury -= annex_cost(target)
		_annex_country(issuer, target)
		if issuer == player_country:
			Events.notice.emit("%s foi anexado ao seu país." % countries[target].name)
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.IMPROVE_RELATIONS:
		var target: int = int(cmd.get("target", -1))
		if not can_improve(issuer, target):
			return
		countries[issuer].treasury -= IMPROVE_COST
		relations[_pair(issuer, target)] = mini(100, opinion(issuer, target) + 20)
		Events.treasury_changed.emit(issuer)
		Events.war_changed.emit()

	elif t == Cmd.PROPOSE_ALLIANCE:
		var target: int = int(cmd.get("target", -1))
		if not can_ally(issuer, target):
			return
		if is_human(target):
			if issuer == player_country:
				Events.notice.emit("Alianças com jogadores ainda não existem.")
			return
		if opinion(issuer, target) < ALLIANCE_MIN_OPINION:
			if issuer == player_country:
				Events.notice.emit("%s não confia em você (opinião %d, precisa de %d)." % [countries[target].name, opinion(issuer, target), ALLIANCE_MIN_OPINION])
			return
		alliances.append(_pair(issuer, target))
		if issuer == player_country:
			Events.notice.emit("Aliança firmada com %s." % countries[target].name)
		Events.war_changed.emit()

	elif t == Cmd.BREAK_ALLIANCE:
		var target: int = int(cmd.get("target", -1))
		if not allied(issuer, target) or countries[target].overlord == issuer or countries[issuer].overlord == target:
			return
		alliances.erase(_pair(issuer, target))
		relations[_pair(issuer, target)] = opinion(issuer, target) - 20
		Events.war_changed.emit()

	elif t == Cmd.TRANSFER_PROVINCE:
		if not ALLOW_DEBUG_COMMANDS:
			return
		transfer_province(int(cmd.get("province", -1)), int(cmd.get("to", -1)))

	else:
		push_warning("GeoEmpire: comando desconhecido '%s'" % t)
		return
	Events.command_applied.emit(cmd)


func set_player_country(id: int) -> void:
	if id < 0 or id >= countries.size():
		return
	player_country = id
	Events.player_country_changed.emit(id)


func _pair(x: int, y: int) -> int:
	return mini(x, y) * 1000 + maxi(x, y)


func opinion(x: int, y: int) -> int:
	return int(relations.get(_pair(x, y), 0))


func allied(x: int, y: int) -> bool:
	return x != y and alliances.has(_pair(x, y))


func truce_left(x: int, y: int) -> int:
	return maxi(0, int(truces.get(_pair(x, y), 0)) - tick)


func is_vassal(cid: int) -> bool:
	return cid >= 0 and cid < countries.size() and countries[cid].overlord >= 0


func vassals_of(cid: int) -> Array:
	var out: Array = []
	for c in countries:
		if c.overlord == cid and c.is_alive():
			out.append(c.id)
	return out


func annex_cost(v: int) -> int:
	return countries[v].province_ids.size() * ANNEX_COST_PER_PROVINCE


func can_annex_vassal(issuer: int, v: int) -> bool:
	if v < 0 or v >= countries.size() or issuer < 0 or issuer >= countries.size():
		return false
	var c := countries[v]
	return c.overlord == issuer and c.is_alive() and tick - c.overlord_since >= ANNEX_MIN_DAYS \
		and countries[issuer].treasury >= annex_cost(v)


## Pontuação de guerra de x contra y (0-100): % das províncias de y tomadas + bônus pela capital.
@warning_ignore("integer_division")
func war_score(x: int, y: int) -> int:
	var i := _war_index(x, y)
	if i < 0:
		return 0
	var w: Dictionary = wars[i]
	var xa := x == int(w["a"])
	var gained: int = int(w.get("ga" if xa else "gb", 0))
	var base_n: int = maxi(1, int(w.get("nb" if xa else "na", 1)))
	var s: int = gained * 100 / base_n
	if bool(w.get("capa" if xa else "capb", false)):
		s += CAPITAL_SCORE
	return clampi(s, 0, 100)


## Termos de paz que `issuer` pode impor a `target` agora: [{"id","label","need","ok"}].
func peace_options(issuer: int, target: int) -> Array:
	var sc := war_score(issuer, target)
	var out: Array = []
	var defs := [["white", "Paz branca", 0], ["indemnity", "Indenização", SCORE_INDEMNITY],
		["vassal", "Vassalizar", SCORE_VASSAL], ["annex", "Anexar o país", SCORE_ANNEX]]
	for d in defs:
		out.append({"id": d[0], "label": d[1], "need": d[2], "ok": can_peace_term(issuer, target, str(d[0])), "score": sc})
	return out


func can_peace_term(issuer: int, target: int, term: String) -> bool:
	if not can_make_peace(issuer, target):
		return false
	var sc := war_score(issuer, target)
	match term:
		"white":
			return true
		"indemnity":
			return sc >= SCORE_INDEMNITY and countries[target].treasury > 0
		"vassal":
			return sc >= SCORE_VASSAL and countries[target].overlord < 0 and countries[issuer].overlord < 0
		"annex":
			return sc >= SCORE_ANNEX
	return false


func _offer_index(from: int, to: int) -> int:
	for i in peace_offers.size():
		if int(peace_offers[i]["from"]) == from and int(peace_offers[i]["to"]) == to:
			return i
	return -1


func indemnity_amount(winner: int, loser: int) -> int:
	return mini(countries[loser].treasury, 150 + war_score(winner, loser) * 10)


## Texto de um termo de paz do ponto de vista de `viewer`.
func peace_term_text(winner: int, loser: int, term: String, viewer: int) -> String:
	var wn := countries[winner].name
	var ln := countries[loser].name
	match term:
		"indemnity":
			return "%s pagará %s de indenização a %s" % [ln if loser != viewer else "você", Money.fmt(indemnity_amount(winner, loser)), wn if winner != viewer else "você"]
		"vassal":
			if loser == viewer:
				return "você se tornará vassalo de %s (tributo de %d%% da renda)" % [wn, VASSAL_TRIBUTE_PCT]
			return "%s se tornará %s vassalo" % [ln, "seu" if winner == viewer else "vassalo de " + wn]
		"annex":
			return "%s será anexado por %s" % ["você" if loser == viewer else ln, "você" if winner == viewer else wn]
	return "paz branca: ninguém perde nada"


func _apply_peace(issuer: int, target: int, term: String) -> void:
	var sc := war_score(issuer, target)
	for i in range(peace_offers.size() - 1, -1, -1):
		var of: Dictionary = peace_offers[i]
		if _pair(int(of["from"]), int(of["to"])) == _pair(issuer, target):
			peace_offers.remove_at(i)
	_end_war(issuer, target)
	truces[_pair(issuer, target)] = tick + TRUCE_DAYS
	var involves_player := issuer == player_country or target == player_country
	var msg := "%s e %s firmaram a paz." % [countries[issuer].name, countries[target].name]
	match term:
		"indemnity":
			var amt := mini(countries[target].treasury, 150 + sc * 10)
			countries[target].treasury -= amt
			countries[issuer].treasury += amt
			msg = "%s pagou %d de indenização a %s." % [countries[target].name, amt, countries[issuer].name]
		"vassal":
			_make_vassal(issuer, target)
			msg = "%s tornou-se vassalo de %s." % [countries[target].name, countries[issuer].name]
		"annex":
			_annex_country(issuer, target)
			msg = "%s foi anexado por %s." % [countries[target].name, countries[issuer].name]
	if involves_player:
		Events.notice.emit(msg)
	Events.war_changed.emit()
	Events.treasury_changed.emit(issuer)
	Events.treasury_changed.emit(target)


func _make_vassal(o: int, v: int) -> void:
	for al in allies_of(v):
		alliances.erase(_pair(v, int(al)))
	countries[v].overlord = o
	countries[v].overlord_since = tick
	alliances.append(_pair(o, v))
	relations[_pair(o, v)] = maxi(opinion(o, v), 0)


func _free_vassal(v: int, friendly: bool) -> void:
	var o: int = countries[v].overlord
	if o < 0:
		return
	countries[v].overlord = -1
	alliances.erase(_pair(o, v))
	relations[_pair(o, v)] = clampi(opinion(o, v) + (30 if friendly else -40), -100, 100)
	if v == player_country or o == player_country:
		Events.notice.emit("%s %s." % [countries[v].name, "foi libertado" if friendly else "rompeu com o suserano e tornou-se independente"])
	Events.war_changed.emit()


## Anexa o país inteiro: províncias, exércitos e frota passam ao anexador.
func _annex_country(o: int, v: int) -> void:
	for pid in countries[v].province_ids.duplicate():
		transfer_province(int(pid), o)
	for id in armies.keys():
		var a: Army = armies[id]
		if a.owner_id == v:
			a.owner_id = o
			Events.army_changed.emit(id)
	for id in fleets.keys():
		var fl: Fleet = fleets[id]
		if fl.owner_id == v:
			fl.owner_id = o
	countries[o].ships += countries[v].ships
	countries[v].ships = 0
	for al in allies_of(v):
		alliances.erase(_pair(v, int(al)))
	for q in wars_of(v):
		_end_war(v, int(q))
	for c in countries:
		if c.overlord == v:
			c.overlord = o if o != c.id else -1
			c.overlord_since = tick
			if c.overlord >= 0:
				alliances.append(_pair(o, c.id))
	countries[v].overlord = -1
	Events.war_changed.emit()


func _record_conquest(by: int, loser: int, pid: int) -> void:
	var i := _war_index(by, loser)
	if i < 0:
		return
	var w: Dictionary = wars[i]
	var by_a := by == int(w["a"])
	var k := "ga" if by_a else "gb"
	var ko := "gb" if by_a else "ga"
	var held: Dictionary = w.get("held", {})
	w["held"] = held
	if int(held.get(pid, -1)) == loser:
		# retomada de uma província que o inimigo tinha conquistado nesta guerra:
		# anula o ganho dele em vez de somar de novo ao meu (sem duplicar conquistas)
		w[ko] = maxi(0, int(w.get(ko, 0)) - 1)
		held.erase(pid)
		if countries[by].capital == pid:
			w["capb" if by_a else "capa"] = false   # recuperou a própria capital
	else:
		w[k] = int(w.get(k, 0)) + 1
		held[pid] = by
	if countries[loser].capital == pid:
		w["capa" if by_a else "capb"] = true


func _new_war(x: int, y: int) -> Dictionary:
	var lo := mini(x, y)
	var hi := maxi(x, y)
	return {"a": lo, "b": hi, "days": 0, "na": countries[lo].province_ids.size(), "nb": countries[hi].province_ids.size(),
		"ga": 0, "gb": 0, "capa": false, "capb": false, "held": {}}


func allies_of(cid: int) -> Array:
	var out: Array = []
	for pr in alliances:
		var lo: int = int(pr) / 1000
		var hi: int = int(pr) % 1000
		if lo == cid:
			out.append(hi)
		elif hi == cid:
			out.append(lo)
	out.sort()
	return out


func trade_blocked(a: int, b: int) -> bool:
	return at_war(a, b) or embargoes.has(a * 1000 + b) or embargoes.has(b * 1000 + a)


func can_embargo(issuer: int, target: int) -> bool:
	if issuer < 0 or target < 0 or issuer >= countries.size() or target >= countries.size() or issuer == target:
		return false
	return countries[target].is_alive() and not embargoes.has(issuer * 1000 + target)


func ports_of(cid: int) -> int:
	var n := 0
	for pid in countries[cid].province_ids:
		if provinces[pid].coastal:
			n += 1
	return n


func can_build_ship(pid: int, issuer: int) -> bool:
	if pid < 0 or pid >= provinces.size() or issuer < 0 or issuer >= countries.size():
		return false
	var p := provinces[pid]
	return p.owner_id == issuer and p.port >= 0 and countries[issuer].treasury >= SHIP_COST


## Capacidade de comércio marítimo: portos + navios; inimigos com mais navios bloqueiam.
func sea_capacity(cid: int) -> int:
	var enemy_ships := 0
	for o in wars_of(cid):
		enemy_ships += countries[o].ships
	var mine: int = countries[cid].ships
	var base: int = 0 if enemy_ships > mine else ports_of(cid) * PORT_CAP + dock_levels(cid) * DOCK_CAP
	return base + maxi(0, mine - enemy_ships) * SHIP_CAP


func dock_levels(cid: int) -> int:
	var n := 0
	for pid in countries[cid].province_ids:
		n += int(provinces[pid].bld.get("dock", 0))
	return n


func is_blockaded(cid: int) -> bool:
	var enemy_ships := 0
	for o in wars_of(cid):
		enemy_ships += countries[o].ships
	return enemy_ships > countries[cid].ships


func can_improve(issuer: int, target: int) -> bool:
	if issuer < 0 or target < 0 or issuer >= countries.size() or target >= countries.size() or issuer == target:
		return false
	return countries[target].is_alive() and not at_war(issuer, target) \
		and countries[issuer].treasury >= IMPROVE_COST and opinion(issuer, target) < 100


func can_ally(issuer: int, target: int) -> bool:
	if issuer < 0 or target < 0 or issuer >= countries.size() or target >= countries.size() or issuer == target:
		return false
	return countries[target].is_alive() and not at_war(issuer, target) and not allied(issuer, target) \
		and countries[issuer].overlord < 0 and countries[target].overlord < 0


## Declara a guerra e chama os aliados do alvo (defensivo).
func _start_war(attacker: int, target: int) -> void:
	wars.append(_new_war(attacker, target))
	relations[_pair(attacker, target)] = -100
	if attacker == player_country or target == player_country:
		Events.notice.emit("%s declarou guerra a %s!" % [countries[attacker].name, countries[target].name])
	for al in allies_of(target):
		if al != attacker and not at_war(al, attacker) and not allied(al, attacker) and countries[al].is_alive():
			wars.append(_new_war(al, attacker))
			if al == player_country:
				Events.notice.emit("Seu aliado %s foi atacado: você entrou na guerra." % countries[target].name)
	for v in vassals_of(attacker):
		if v != target and not at_war(v, target) and not at_war(v, attacker):
			wars.append(_new_war(v, target))
			if v == player_country:
				Events.notice.emit("Seu suserano %s entrou em guerra: você o acompanha." % countries[attacker].name)
	Events.war_changed.emit()
	# Frente automática: os exércitos do jogador marcham ao front assim que a guerra começa.
	for cid in [attacker, target]:
		if is_human(cid) and countries[cid].auto_front:
			_ai_war(countries[cid])
			_auto_fleets(countries[cid])


func _war_index(x: int, y: int) -> int:
	var lo := mini(x, y)
	var hi := maxi(x, y)
	for i in wars.size():
		if int(wars[i]["a"]) == lo and int(wars[i]["b"]) == hi:
			return i
	return -1


func at_war(x: int, y: int) -> bool:
	return x != y and _war_index(x, y) >= 0


func war_days(x: int, y: int) -> int:
	var i := _war_index(x, y)
	return int(wars[i]["days"]) if i >= 0 else 0


func can_declare_war(attacker: int, target: int) -> bool:
	if attacker < 0 or target < 0 or attacker >= countries.size() or target >= countries.size():
		return false
	if attacker == target or at_war(attacker, target) or allied(attacker, target):
		return false
	if countries[attacker].overlord >= 0 or countries[target].overlord == attacker:
		return false   # vassalo não declara guerra; suserano não ataca o próprio vassalo
	if truce_left(attacker, target) > 0:
		return false
	return countries[attacker].is_alive() and countries[target].is_alive()


func can_make_peace(issuer: int, target: int) -> bool:
	return at_war(issuer, target) and war_days(issuer, target) >= WAR_MIN_DAYS


func wars_of(cid: int) -> Array:
	var out: Array = []
	for w in wars:
		if int(w["a"]) == cid:
			out.append(int(w["b"]))
		elif int(w["b"]) == cid:
			out.append(int(w["a"]))
	return out


func _end_war(x: int, y: int) -> void:
	var i := _war_index(x, y)
	if i >= 0:
		wars.remove_at(i)
	# cercos que dependiam dessa guerra caem
	for pid in sieges.keys():
		var by: int = int(sieges[pid]["by"])
		var owner: int = provinces[int(pid)].owner_id
		if not at_war(by, owner):
			sieges.erase(pid)
			Events.province_updated.emit(int(pid))


func transfer_province(pid: int, to_country: int) -> void:
	if pid < 0 or pid >= provinces.size():
		return
	if to_country < 0 or to_country >= countries.size():
		return
	var p := provinces[pid]
	if p.owner_id == to_country:
		return
	var old := p.owner_id
	p.owner_id = to_country
	if old >= 0 and old < countries.size():
		countries[old].province_ids.erase(pid)
		_refresh_country_geometry(countries[old])
	countries[to_country].province_ids.append(pid)
	_refresh_country_geometry(countries[to_country])
	Events.province_changed.emit(pid)


# ---------------------------------------------------------------------------
# Regras de recrutamento e construção (usadas pela UI para habilitar botões)
# ---------------------------------------------------------------------------
func queued_in(pid: int) -> int:
	var n := 0
	for t in training:
		if int(t["province"]) == pid and str(t.get("kind", "reg")) != "ship":
			n += 1
	return n


func can_recruit(pid: int, issuer: int) -> bool:
	if pid < 0 or pid >= provinces.size() or issuer < 0 or issuer >= countries.size():
		return false
	var p := provinces[pid]
	if p.owner_id != issuer:
		return false
	if p.manpower < REGIMENT_SIZE or countries[issuer].treasury < RECRUIT_COST:
		return false
	return queued_in(pid) < MAX_QUEUE_PER_PROVINCE


func _do_recruit(pid: int, cid: int) -> void:
	provinces[pid].manpower -= REGIMENT_SIZE
	countries[cid].treasury -= RECRUIT_COST
	training.append({"province": pid, "owner": cid, "days": RECRUIT_DAYS})
	Events.province_updated.emit(pid)
	Events.treasury_changed.emit(cid)


func build_cost(p: Province, kind: String) -> int:
	var b: Dictionary = Province.BUILDINGS.get(kind, {})
	return int(b.get("cost", 0)) * (p.building_level(kind) + 1)


## Materiais de obra (em ouro, ao preço de mercado) do próximo nível.
func build_material_cost(p: Province, kind: String) -> int:
	return p.material_cost(kind, p.building_level(kind) + 1)


## O que o tesouro paga ao construir: custo base + materiais.
func build_total_cost(p: Province, kind: String) -> int:
	return build_cost(p, kind) + build_material_cost(p, kind)


func can_build(pid: int, issuer: int, kind: String) -> bool:
	if not Province.BUILDINGS.has(kind):
		return false
	if pid < 0 or pid >= provinces.size() or issuer < 0 or issuer >= countries.size():
		return false
	var p := provinces[pid]
	if p.owner_id != issuer or p.building_level(kind) >= Province.MAX_BUILDING:
		return false
	if not p.can_host(kind):
		return false
	if countries[issuer].tech_level() < int(Province.BUILDINGS[kind]["tech"]):
		return false
	if Province.FACTORIES.has(kind) and p.factory != "" and p.factory != kind:
		return false   # uma fábrica por província
	return countries[issuer].treasury >= build_total_cost(p, kind)


# ---------------------------------------------------------------------------
# Exércitos
# ---------------------------------------------------------------------------
func find_path(from_id: int, to_id: int) -> Array[int]:
	var out: Array[int] = []
	if graph == null or from_id < 0 or to_id < 0 or from_id >= provinces.size() or to_id >= provinces.size():
		return out
	var ids: PackedInt64Array = graph.get_id_path(from_id, to_id)
	for i in ids:
		out.append(int(i))
	return out


func regiments_of(cid: int) -> int:
	var n := 0
	for a in armies.values():
		var army: Army = a
		if army.owner_id == cid:
			n += army.regiments
	return n


func manpower_of(cid: int) -> int:
	var n := 0
	if cid < 0 or cid >= countries.size():
		return 0
	for pid in countries[cid].province_ids:
		n += provinces[pid].manpower
	return n


## Dias restantes até o destino final de um exército em marcha.
func eta_days(a: Army) -> int:
	if not a.is_moving():
		return 0
	var days: int = a.move_left
	for i in range(1, a.path.size()):
		days += ProvinceGraph.hop_days(provinces[a.path[i - 1]], provinces[a.path[i]])
	return days


func _order_move(a: Army, dest: int) -> void:
	var start := a.province_id
	if a.is_moving():
		start = a.path[0]   # só dá para redirecionar a partir da próxima província
	var ids := find_path(start, dest)
	if ids.is_empty():
		return
	if a.is_moving():
		a.path = ids        # ids[0] == start == path[0]; o trecho atual continua
	else:
		ids.remove_at(0)
		if ids.is_empty():
			return
		a.path = ids
		a.move_left = ProvinceGraph.hop_days(provinces[a.province_id], provinces[a.path[0]])
	Events.army_changed.emit(a.id)


func _add_regiments(pid: int, owner: int, count: int) -> void:
	# Junta com um exército parado do mesmo dono, se houver.
	for a in armies.values():
		var army: Army = a
		if army.owner_id == owner and army.province_id == pid and not army.is_moving():
			army.regiments += count
			Events.army_changed.emit(army.id)
			return
	var n := Army.new()
	n.id = next_army_id
	next_army_id += 1
	n.owner_id = owner
	n.province_id = pid
	n.regiments = count
	armies[n.id] = n
	Events.army_changed.emit(n.id)


## Une exércitos parados do mesmo dono na mesma província (mantém o de menor id).
func _merge_stationary(a: Army) -> void:
	var current: Army = a
	for id in armies.keys():
		if not armies.has(id):
			continue   # já fundido neste laço
		var o: Army = armies[id]
		if o.id == current.id or o.owner_id != current.owner_id:
			continue
		if o.province_id != current.province_id or o.is_moving():
			continue
		var keep: Army = o if o.id < current.id else current
		var gone: Army = current if keep == o else o
		keep.regiments += gone.regiments
		armies.erase(gone.id)
		Events.army_removed.emit(gone.id)
		current = keep
	Events.army_changed.emit(current.id)


# ---------------------------------------------------------------------------
# Passo da simulação
# ---------------------------------------------------------------------------
## Aplica os comandos do frame e, se não estiver pausado, simula um dia.
func step(cmds: Array = []) -> void:
	for c in cmds:
		apply_command(c)
	frame += 1
	if speed > 0:
		_simulate_day()


func _simulate_day() -> void:
	tick += 1
	var month_rolled := clock.advance_day()
	_advance_training()
	_advance_armies()
	_advance_fleets()
	_advance_war()
	_advance_ai()
	_advance_events()
	Events.day_changed.emit(clock.to_dict())
	if month_rolled:
		_simulate_month()
	Events.tick_advanced.emit(tick)


func _advance_training() -> void:
	if training.is_empty():
		return
	var remaining: Array = []
	for t in training:
		t["days"] = int(t["days"]) - 1
		if int(t["days"]) <= 0:
			if str(t.get("kind", "reg")) == "ship":
				_add_ships(int(t["province"]), int(t["owner"]), 1)
			else:
				_add_regiments(int(t["province"]), int(t["owner"]), 1)
			Events.province_updated.emit(int(t["province"]))
		else:
			remaining.append(t)
	training = remaining


func _advance_armies() -> void:
	for id in armies.keys():
		if not armies.has(id):
			continue   # fundido por _merge_stationary durante este laço
		var a: Army = armies[id]
		if a.path.is_empty():
			continue
		a.move_left -= 1
		if a.move_left > 0:
			continue
		a.province_id = a.path.pop_front()
		if a.path.is_empty():
			a.move_left = 0
			_merge_stationary(a)
		else:
			a.move_left = ProvinceGraph.hop_days(provinces[a.province_id], provinces[a.path[0]])
			Events.army_changed.emit(a.id)


# ---------------------------------------------------------------------------
# IA simples (determinística: só usa o estado e ids em ordem; roda igual em todos os pares)
# ---------------------------------------------------------------------------
## Países controlados por jogadores (no online, vem da lista de jogadores, igual em todos).
func is_human(cid: int) -> bool:
	if Net.is_online():
		for pid in Net.players.keys():
			if int(Net.players[pid]["country"]) == cid:
				return true
		return false
	return cid == player_country


@warning_ignore("integer_division")
func _advance_ai() -> void:
	if tick % 5 != 0:
		return
	var heg := -1
	if tick % 30 == 0:
		heg = AiBrain.hegemon(self)
	for c in countries:
		if not c.is_alive():
			continue
		if is_human(c.id):
			# Frente automática: exércitos parados do jogador marcham sozinhos em guerra.
			if c.auto_front and not wars_of(c.id).is_empty():
				_ai_war(c)
				_auto_fleets(c)
			continue
		if tick % 30 == 0:
			AiBrain.balance_drift(self, c, heg)
			var plan := AiBrain.plan(self, c, heg)
			_ai_recruit(c, plan)
			_ai_build_ship(c)
			_ai_invest(c)
			_ai_declare_war(c, plan)
		if not wars_of(c.id).is_empty():
			_ai_war(c)
			_auto_fleets(c)


const AI_BUILD_ORDER := ["farm", "mine", "logging", "school", "market", "hospital", "dock", "textile", "carpentry", "university"]
const AI_INVEST_RESERVE_MONTHS := 8


## Investimento da IA: com folga de caixa (acima de ~8 meses de despesa) constrói edifícios
## produtivos e de governo, espalhando por nível (primeiro nível 0, depois 1...). Sem isso os
## tesouros das potências cresciam sem uso e ninguém criava empregos. Determinístico:
## percorre províncias e tipos em ordem fixa, sem rng.
@warning_ignore("integer_division")
func _ai_invest(c: Country) -> void:
	var reserve: int = maxi(400, c.last_expense * AI_INVEST_RESERVE_MONTHS)
	# pesquisa: só com folga de caixa e fora de guerra
	if wars_of(c.id).is_empty() and c.treasury > reserve * 2:
		c.research_pct = 15 if c.treasury > reserve * 6 else 10
	else:
		c.research_pct = 0
	if not wars_of(c.id).is_empty():
		reserve *= 2
	var spare: int = c.treasury - reserve
	if spare < 150:
		return
	var budget: int = clampi(spare / 800, 1, 5) + clampi(spare / 100000, 0, 20)   # potências ricas investem mais por ciclo
	for level in 3:
		for kind in AI_BUILD_ORDER:
			for pid in c.province_ids:
				if budget <= 0:
					return
				var p := provinces[int(pid)]
				if p.building_level(kind) != level or not can_build(int(pid), c.id, kind):
					continue
				var cost: int = build_total_cost(p, kind)
				if c.treasury - cost < reserve:
					continue
				c.treasury -= cost
				p.set_building_level(kind, level + 1)
				budget -= 1
				Events.province_updated.emit(int(pid))


@warning_ignore("integer_division")
func _ai_recruit(c: Country, plan: Dictionary) -> void:
	var enemies := wars_of(c.id)
	var want: int = 2 + c.province_ids.size() / 6 + (2 if not enemies.is_empty() else 0)
	want = mini(want + AiBrain.recruit_bonus(plan), 30)
	if regiments_of(c.id) + _queued_for(c.id) >= want or c.treasury < RECRUIT_COST + 100:
		return
	if can_recruit(c.capital, c.id):
		_do_recruit(c.capital, c.id)
		return
	for pid in c.province_ids:
		if can_recruit(pid, c.id):
			_do_recruit(pid, c.id)
			return


## Fim das guerras entre IAs: o vencedor dita os termos conforme a pontuação; empate longo vira paz
## branca. IAs suseranas anexam vassalos quando podem pagar.
func _ai_peace() -> void:
	for w in wars.duplicate():
		var x: int = int(w["a"])
		var y: int = int(w["b"])
		if not at_war(x, y) or is_human(x) or is_human(y):
			continue
		var days: int = int(w["days"])
		if days < 120:
			continue
		var sx := war_score(x, y)
		var sy := war_score(y, x)
		var win := x
		var lose := y
		var sw := sx
		if sy > sx:
			win = y
			lose = x
			sw = sy
		var term := ""
		if sw >= SCORE_ANNEX:
			term = "annex"
		elif sw >= SCORE_VASSAL:
			term = "vassal"
		elif sw >= SCORE_INDEMNITY and days >= 180:
			term = "indemnity"
		elif days >= 360:
			term = "white"
		if term == "" or rng.randi_range(0, 1) != 0:
			continue
		if can_peace_term(win, lose, term):
			_apply_peace(win, lose, term)
	for c in countries:
		if is_human(c.id) or not c.is_alive():
			continue
		for v in vassals_of(c.id):
			if can_annex_vassal(c.id, int(v)) and c.treasury >= annex_cost(int(v)) * 2:
				c.treasury -= annex_cost(int(v))
				_annex_country(c.id, int(v))
				break


## Propostas de paz da IA aos jogadores: expiram em OFFER_DAYS; guerras acabadas as cancelam.
func _ai_offers() -> void:
	for i in range(peace_offers.size() - 1, -1, -1):
		var o: Dictionary = peace_offers[i]
		var a: int = int(o["from"])
		var b: int = int(o["to"])
		if not at_war(a, b) or tick - int(o["tick"]) >= AiDiplomacy.OFFER_DAYS:
			peace_offers.remove_at(i)
			peace_cd[_pair(a, b)] = tick + 30
	for c in countries:
		if c.is_alive() and not is_human(c.id):
			AiDiplomacy.review(self, c)


## Ciclo da IA (ver AiBrain): só declara guerra se o plano do mês for "war"; em "pressure"
## ameaça o alvo e busca coalizão. Atacar um rival forte exige razão excepcional.
func _ai_declare_war(c: Country, plan: Dictionary) -> void:
	var stage := str(plan["stage"])
	if stage == "pressure":
		AiBrain.apply_pressure(self, c, plan)
		return
	if stage == "defend":
		AiBrain.court_allies(self, c, int(plan["target"]), false)
		return
	if stage != "war":
		return
	var chance: int = AI_WAR_CHANCE if int(plan["motive"]) < 30 else 4
	if rng.randi_range(0, chance - 1) != 0:
		return
	var tgt: int = int(plan["target"])
	if is_human(tgt):
		Events.notice.emit("%s declara guerra para %s." % [c.name, AiBrain.goal_label(str(plan["goal"]))])
	_start_war(c.id, tgt)


func _ai_build_ship(c: Country) -> void:
	var ports := ports_of(c.id)
	var want: int = mini(ports / 6, 8)
	var queued := 0
	for t in training:
		if int(t["owner"]) == c.id and str(t.get("kind", "reg")) == "ship":
			queued += 1
	if c.ships + queued >= want or c.treasury < SHIP_COST + 200:
		return
	for pid in c.province_ids:
		if can_build_ship(pid, c.id):
			countries[c.id].treasury -= SHIP_COST
			training.append({"province": pid, "owner": c.id, "days": SHIP_DAYS, "kind": "ship"})
			return


func _queued_for(cid: int) -> int:
	var n := 0
	for t in training:
		if int(t["owner"]) == cid and str(t.get("kind", "reg")) != "ship":
			n += 1
	return n


func _ai_war(c: Country) -> void:
	var enemies := wars_of(c.id)
	var ids: Array = armies.keys()
	ids.sort()
	for id in ids:
		var a: Army = armies[id]
		if a.owner_id != c.id or a.is_moving():
			continue
		var here := provinces[a.province_id]
		# mantém o cerco em andamento
		if here.owner_id != c.id and sieges.has(here.id) and int(sieges[here.id]["by"]) == c.id:
			continue
		var target := _ai_pick_target(a, c, enemies)
		if target >= 0 and target != a.province_id:
			_order_move(a, target)


func _ai_pick_target(a: Army, c: Country, enemies: Array) -> int:
	var origin := provinces[a.province_id].center
	# 1) expulsa invasores que estão em terra própria (o mais próximo)
	var best := -1
	var best_d := INF
	var ids: Array = armies.keys()
	ids.sort()
	for id in ids:
		var e: Army = armies[id]
		if not enemies.has(e.owner_id) or provinces[e.province_id].owner_id != c.id:
			continue
		var d := origin.distance_squared_to(provinces[e.province_id].center)
		if d < best_d:
			best_d = d
			best = e.province_id
	if best >= 0:
		return best
	# 2) ataca a província inimiga mais próxima que seja alcançável
	var cands: Array = []
	for p in provinces:
		if enemies.has(p.owner_id):
			# Objetivos de campanha: núcleos próprios, capitais, portos e recursos raros pesam mais.
			var f := 1.0
			if p.core_owner == c.id:
				f = 0.25
			elif countries[p.owner_id].capital == p.id:
				f = 0.36
			elif p.port >= 0:
				f = 0.7
			elif AiBrain.RARE.has(str(p.resource_type)):
				f = 0.8
			cands.append({"id": p.id, "d": origin.distance_squared_to(p.center) * f})
	cands.sort_custom(func(x, y): return x["d"] < y["d"] or (x["d"] == y["d"] and x["id"] < y["id"]))
	for i in mini(cands.size(), 4):
		var pid: int = int(cands[i]["id"])
		if not find_path(a.province_id, pid).is_empty():
			return pid
	return -1


## Guerra: batalhas, cercos e conquista. Ordem fixa (ids crescentes) para ser determinístico.
@warning_ignore("integer_division")
func _advance_war() -> void:
	if wars.is_empty():
		return
	for w in wars:
		w["days"] = int(w["days"]) + 1

	# exércitos por província
	var by_prov := {}
	var ids: Array = armies.keys()
	ids.sort()
	for id in ids:
		var a: Army = armies[id]
		if not by_prov.has(a.province_id):
			by_prov[a.province_id] = []
		by_prov[a.province_id].append(a)
	var pids: Array = by_prov.keys()
	pids.sort()

	# batalhas: um round por dia por par de exércitos inimigos
	for pid in pids:
		var list: Array = by_prov[pid]
		for i in list.size():
			for j in range(i + 1, list.size()):
				var x: Army = list[i]
				var y: Army = list[j]
				if x.regiments <= 0 or y.regiments <= 0 or not at_war(x.owner_id, y.owner_id):
					continue
				var loss_x := (y.regiments * BATTLE_LOSS_PCT + 99) / 100
				var loss_y := (x.regiments * BATTLE_LOSS_PCT + 99) / 100
				if x.regiments == y.regiments:
					# empate: o sorteio decide quem sofre o round
					if rng.randi_range(0, 1) == 0:
						loss_y = 0
					else:
						loss_x = 0
				x.regiments = maxi(0, x.regiments - loss_x)
				y.regiments = maxi(0, y.regiments - loss_y)
	for id in ids:
		var a: Army = armies[id]
		if a.regiments <= 0:
			armies.erase(id)
			Events.army_removed.emit(id)
		else:
			Events.army_changed.emit(id)

	# cercos: exército parado em província inimiga, sem defensores
	var seen := {}
	for pid in pids:
		var p := provinces[int(pid)]
		if p.owner_id < 0:
			continue
		var besieger := -1
		var defended := false
		for a in by_prov[pid]:
			var army: Army = a
			if not armies.has(army.id):
				continue
			if army.owner_id == p.owner_id:
				defended = true
			elif besieger < 0 and not army.is_moving() and at_war(army.owner_id, p.owner_id):
				besieger = army.owner_id
		if besieger < 0 or defended:
			continue
		seen[pid] = true
		var s: Dictionary = sieges.get(pid, {"by": besieger, "days": 0})
		if int(s["by"]) != besieger:
			s = {"by": besieger, "days": 0}
		s["days"] = int(s["days"]) + 1
		sieges[pid] = s
		if int(s["days"]) >= SIEGE_DAYS:
			sieges.erase(pid)
			var loser := p.owner_id
			# registra ANTES de transferir: ao perder a capital o país escolhe outra e o bônus se perderia
			_record_conquest(besieger, loser, int(pid))
			transfer_province(int(pid), besieger)
			if not countries[loser].is_alive():
				for o in wars_of(loser):
					_end_war(loser, o)
		Events.province_updated.emit(int(pid))
	for pid in sieges.keys():
		if not seen.has(pid):
			sieges.erase(pid)
			Events.province_updated.emit(int(pid))


@warning_ignore("integer_division")
func _simulate_month() -> void:
	for p in provinces:
		# Crescimento demográfico: +0,1% ao mês.
		p.population += p.population / 1000 + p.population * int(p.bld.get("hospital", 0)) / 3500
		# Recuperação de mão de obra.
		var mx := p.manpower_max()
		if p.manpower < mx:
			p.manpower = mini(mx, p.manpower + maxi(1, mx * MANPOWER_REGEN_PCT / 100))
	_run_trade()
	for c in countries:
		if c.is_alive():
			var edu := edu_levels(c)
			var lmod := law_mods(c)
			var lit_base: int = 100 + (edu.x + 2 * edu.y) * 400 / maxi(1, c.province_ids.size())
			c.lit_acc += maxi(0, lit_base * (100 + int(lmod["lit"])) / 100)
			c.literacy = mini(LITERACY_MAX, c.literacy + c.lit_acc / 100)
			c.lit_acc = c.lit_acc % 100
			c.tech_pts = mini(MAX_TECH * Country.TECH_STEP + Country.TECH_STEP - 1, c.tech_pts + tech_gain(c))
			for gi in c.law_cd.size():
				if int(c.law_cd[gi]) > 0:
					c.law_cd[gi] = int(c.law_cd[gi]) - 1
	for c in countries:
		if c.is_alive():
			_update_politics(c)
	# Economia: impostos + comércio - manutenção (províncias, regimentos e navios).
	for c in countries:
		if not c.is_alive():
			continue
		var e := estimate_monthly(c)
		c.last_income = int(e["income"])
		c.last_expense = int(e["expense"])
		c.treasury += c.last_income - c.last_expense
	for c in countries:
		if c.overlord >= 0 and c.is_alive():
			var ov := countries[c.overlord]
			if not ov.is_alive() or ov.stability < 15:
				_free_vassal(c.id, false)
				continue
			var tribute: int = maxi(0, c.last_income) * VASSAL_TRIBUTE_PCT / 100
			c.treasury -= tribute
			ov.treasury += tribute
	_ai_peace()
	_ai_offers()
	for k in relations.keys():
		var v: int = int(relations[k])
		if at_war(int(k) / 1000, int(k) % 1000):
			continue
		relations[k] = v - signi(v) * mini(absi(v), 2)
	_roll_events()
	EconomyManager.record_month(self)
	Events.month_changed.emit(clock.to_dict())
	for c in countries:
		Events.treasury_changed.emit(c.id)


# ---------------------------------------------------------------------------
# Eventos (data/events.json)
# ---------------------------------------------------------------------------
const REAL_ECONOMY_PATH := "res://data/real_economy_1836.json"
var usd_per_gold: float = 0.0     # milhões de US$ de 2011 (PPP) por unidade de valor do jogo (calibração de 1836)


## Calibra o valor produzido por província para que a participação de cada país no PIB mundial
## siga o PIB per capita histórico de 1836 (Maddison). A população já é a histórica. Mantém o
## total mundial: só redistribui entre países. Estático e determinístico.
func _apply_historical_productivity() -> void:
	var file := FileAccess.open(REAL_ECONOMY_PATH, FileAccess.READ)
	if file == null:
		return
	var d: Variant = JSON.parse_string(file.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	var pcs: Dictionary = d.get("gdp_pc_1836", {})
	var def_pc: float = float(d.get("default_pc", 1100))
	var real: Array = []
	var prod: Array = []
	var real_total := 0.0
	var prod_total := 0.0
	for c in countries:
		var r: float = float(pcs.get(c.tag, def_pc)) * c.pop_total
		var pr := 0.0
		for pid in c.province_ids:
			pr += float(provinces[pid].production())
		real.append(r)
		prod.append(pr)
		real_total += r
		prod_total += pr
	if real_total <= 0.0 or prod_total <= 0.0:
		return
	usd_per_gold = real_total / prod_total
	for c in countries:
		if prod[c.id] <= 0.0 or real[c.id] <= 0.0:
			continue
		var f: float = (real[c.id] / real_total) / (prod[c.id] / prod_total)
		var pct: int = clampi(int(round(f * 100.0)), 30, 400)
		for pid in c.province_ids:
			provinces[pid].value_pct = pct


func _load_event_defs() -> void:
	event_defs = []
	var file := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if file == null:
		push_warning("GeoEmpire: sem %s; jogo segue sem eventos" % EVENTS_PATH)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) == TYPE_ARRAY:
		event_defs = data


func find_event_def(eid: String) -> Dictionary:
	for d in event_defs:
		if str(d["id"]) == eid:
			return d
	return {}


func pending_event_for(cid: int) -> Dictionary:
	for e in pending_events:
		if int(e["country"]) == cid:
			return e
	return {}


func _event_ok(d: Dictionary, c: Country) -> bool:
	if bool(d.get("once", false)) and fired_events.has("%d|%s" % [c.id, str(d["id"])]):
		return false
	if d.has("tags"):
		var tags: Array = d["tags"]
		if not tags.has(c.tag):
			return false
	if clock.year < int(d.get("min_year", 0)) or clock.year > int(d.get("max_year", 9999)):
		return false
	if d.has("date"):
		var dt: Array = d["date"]
		if clock.year != int(dt[0]) or clock.month != int(dt[1]):
			return false
	if c.province_ids.size() < int(d.get("min_provinces", 0)):
		return false
	if c.treasury > int(d.get("max_treasury", 1000000000)) or c.treasury < int(d.get("min_treasury", -1000000000)):
		return false
	if d.has("min_ideo"):
		var need: Dictionary = d["min_ideo"]
		var pol := politics_of(c)
		for k in need.keys():
			var idx := IDEOLOGIES.find(str(k))
			if idx < 0 or int(pol["ideo"][idx]) < int(need[k]):
				return false
	if d.has("max_sat"):
		var lim: Dictionary = d["max_sat"]
		for k in lim.keys():
			var ci := CLASSES.find(str(k))
			if ci < 0 or int(c.sat[ci]) > int(lim[k]):
				return false
	if d.has("min_price"):
		var mp: Dictionary = d["min_price"]
		for k in mp.keys():
			if c.id >= local_price.size() or int(local_price[c.id].get(str(k), 100)) < int(mp[k]):
				return false
	var need_regs: int = int(d.get("min_regiments", 0))
	if need_regs > 0 and regiments_of(c.id) < need_regs:
		return false
	return true


## Sorteio mensal. Usa só `rng` e itera em ordem fixa -> igual em todos os pares.
func _roll_events() -> void:
	if event_defs.is_empty():
		return
	for c in countries:
		if not c.is_alive() or not pending_event_for(c.id).is_empty():
			continue
		for d in event_defs:
			if not _event_ok(d, c):
				continue
			if not d.has("date"):
				var mtth: int = maxi(1, int(d.get("mtth_months", 120)))
				if rng.randi_range(0, mtth - 1) != 0:
					continue
			if bool(d.get("once", false)):
				fired_events["%d|%s" % [c.id, str(d["id"])]] = true
			pending_events.append({"uid": next_event_uid, "country": c.id, "event": str(d["id"]), "days": EVENT_DECISION_DAYS})
			next_event_uid += 1
			Events.game_event_changed.emit()
			break


func _advance_events() -> void:
	if pending_events.is_empty():
		return
	var remaining: Array = []
	var changed := false
	for e in pending_events:
		e["days"] = int(e["days"]) - 1
		if int(e["days"]) <= 0:
			_apply_event_option(e, 0)   # prazo esgotado: opção padrão
			changed = true
		else:
			remaining.append(e)
	pending_events = remaining
	if changed:
		Events.game_event_changed.emit()


@warning_ignore("integer_division")
func _apply_event_option(e: Dictionary, option: int) -> void:
	var d := find_event_def(str(e["event"]))
	var cid: int = int(e["country"])
	if d.is_empty() or cid < 0 or cid >= countries.size():
		return
	var options: Array = d["options"]
	var opt: Dictionary = options[clampi(option, 0, options.size() - 1)]
	var fx: Dictionary = opt.get("effects", {})
	var c := countries[cid]
	if fx.has("gold"):
		c.treasury += int(fx["gold"])
		Events.treasury_changed.emit(cid)
	if fx.has("manpower") and c.capital >= 0:
		var cap := provinces[c.capital]
		cap.manpower = clampi(cap.manpower + int(fx["manpower"]), 0, cap.manpower_max())
		Events.province_updated.emit(cap.id)
	if fx.has("literacy"):
		c.literacy = clampi(c.literacy + int(fx["literacy"]), 0, LITERACY_MAX)
	if fx.has("sat"):
		var sd: Dictionary = fx["sat"]
		for k in sd.keys():
			var ci := CLASSES.find(str(k))
			if ci >= 0:
				c.sat[ci] = clampi(int(c.sat[ci]) + int(sd[k]), 0, 100)
		c.stability = int(politics_of(c)["stability"])
	if fx.has("region_pop_pct"):
		var rp: Dictionary = fx["region_pop_pct"]
		for p in provinces:
			if p.owner_id == cid and rp.has(p.region):
				p.population += p.population * int(rp[p.region]) / 100
				Events.province_updated.emit(p.id)
	if fx.has("pop_pct"):
		var pct: int = int(fx["pop_pct"])
		for pid in c.province_ids:
			provinces[pid].population += provinces[pid].population * pct / 100


## Previsão mensal de um país (usada pela simulação e pela UI).
## Classes do país: participação (permil), satisfação-alvo, influência, correntes (permil) e
## estabilidade. Tudo derivado da economia; só `Country.sat` e `stability` são estado.
@warning_ignore("integer_division")
func politics_of(c: Country) -> Dictionary:
	var pop := maxi(1, population_of(c))
	var fl := 0
	var ml := 0
	for pid in c.province_ids:
		var p := provinces[pid]
		fl += p.factory_level
		ml += int(p.bld.get("mine", 0))
	var edu := edu_levels(c)
	var regs := regiments_of(c.id)
	var sh := [0, 0, 0, 0, 0, 0]
	sh[5] = clampi(regs * REGIMENT_SIZE * 1000 / pop, 5, 60)
	sh[1] = mini(400, 30 + (fl * 4000 + ml * 2000) * 1000 / pop)
	sh[3] = mini(120, 10 + c.literacy / 25 + fl * 1500 * 1000 / pop)
	sh[4] = mini(50, 5 + c.literacy / 50 + (edu.x + 2 * edu.y) * 500 * 1000 / pop)
	sh[2] = maxi(8, 25 - c.literacy / 50)
	sh[0] = 1000 - sh[1] - sh[2] - sh[3] - sh[4] - sh[5]

	var lp: Dictionary = local_price[c.id] if c.id < local_price.size() else {}
	var grain: int = int(lp.get("grain", 100))
	var fabric: int = int(lp.get("fabric", 100))
	var wars_n := wars_of(c.id).size()
	var emb_n := 0
	for k in embargoes:
		if int(k) % 1000 == c.id:
			emb_n += 1
	var e := estimate_monthly(c)
	var sol := standard_of_living_x10(c, e)
	var unemp := unemployment_pct(c)
	var tax := c.tax_pct
	var broke := c.treasury < 0
	var tg := [0, 0, 0, 0, 0, 0]
	tg[0] = 55 - (grain - 100) / 2 - (tax - 30) / 2 - wars_n * 4 - (unemp - UNEMP_BASE) / 4
	tg[1] = 20 + sol / 3 - (grain - 100) / 2 - (fabric - 100) / 4 - (tax - 30) / 2 - wars_n * 4 - (unemp - UNEMP_BASE) / 2
	tg[2] = 75 - (tax - 30) / 2 - c.literacy / 25
	tg[3] = 45 + clampi(int(e["trade"]) / 10, 0, 25) + clampi(int(e["industry"]) / 10, 0, 15) - emb_n * 5 - (15 if is_blockaded(c.id) else 0) - (tax - 30)
	tg[4] = 50 + (-30 if broke else 15) + c.literacy / 30
	tg[5] = 55 + (-25 if broke else 10) + wars_n * 5
	var lmp := law_mods(c)
	var hist_bias: int = (int(history.get(c.tag, {}).get("stab", 2)) - 2) * 2
	var prof_sat: Dictionary = history.get(c.tag, {}).get("profile", {}).get("sat", {})
	for i in 6:
		tg[i] = clampi(tg[i] + int(lmp["stab"]) + int(lmp["sat"][i]) + hist_bias + int(prof_sat.get(str(i), 0)), 0, 100)

	var pw := [0, 0, 0, 0, 0, 0]
	var tot_pw := 0
	for i in 6:
		pw[i] = sh[i] * CLASS_PART[i] * (1000 + (c.literacy if i < 2 else 0)) / 1000
		tot_pw += pw[i]
	tot_pw = maxi(1, tot_pw)
	var acc := [0, 0, 0, 0, 0]
	var wsum := 0
	var ssum := 0
	for i in 6:
		var sat: int = int(c.sat[i])
		var shift := clampi(50 - sat, 0, 50)
		for j in 5:
			var v: int = int(CLASS_AFF[i][j]) * (100 - shift)
			if j == int(CLASS_RADICAL[i]):
				v += shift * 100
			acc[j] += v * pw[i]
		var w: int = sh[i] + pw[i] / 50
		wsum += w
		ssum += sat * w
	var ideo := [0, 0, 0, 0, 0]
	for j in 5:
		ideo[j] = acc[j] / (10 * tot_pw)
	return {"share": sh, "target": tg, "power": pw, "power_total": tot_pw, "ideo": ideo,
		"stability": ssum / maxi(1, wsum)}


## Atualização mensal: a satisfação anda até 2 pontos rumo ao alvo; instabilidade gera revoltas.
@warning_ignore("integer_division")
func _update_politics(c: Country) -> void:
	var pol := politics_of(c)
	for i in 6:
		c.sat[i] = int(c.sat[i]) + clampi(int(pol["target"][i]) - int(c.sat[i]), -2, 2)
	c.stability = int(politics_of(c)["stability"])
	if c.stability < REVOLT_STABILITY and not c.province_ids.is_empty():
		if rng.randi_range(0, 99) < (REVOLT_STABILITY - c.stability) * 2:
			var pid: int = c.province_ids[rng.randi_range(0, c.province_ids.size() - 1)]
			var p := provinces[pid]
			p.population -= p.population * 3 / 100
			p.manpower /= 2
			c.treasury -= 40
			Events.province_updated.emit(pid)
			if c.id == player_country:
				Events.notice.emit("Revolta em %s! O país está instável." % p.name)


## Soma dos níveis de escolas (x) e universidades (y) do país.
func edu_levels(c: Country) -> Vector2i:
	var sc := 0
	var un := 0
	for pid in c.province_ids:
		sc += int(provinces[pid].bld.get("school", 0))
		un += int(provinces[pid].bld.get("university", 0))
	return Vector2i(sc, un)


## Bônus por tecnologia: imposto (+4% por nível acima de 3) e manutenção do exército (-10% por nível acima de 4).
func tech_tax_bonus(c: Country) -> int:
	return 4 * maxi(0, mini(c.tech_level(), MAX_TECH) - 3)


func tech_army_discount(c: Country) -> int:
	return 10 * maxi(0, mini(c.tech_level(), MAX_TECH) - 4)


## Pontos de tecnologia por mês SEM financiamento: base + alfabetização + escolas + universidades + leis.
func tech_gain_base(c: Country) -> int:
	var edu := edu_levels(c)
	var lmod := law_mods(c)
	return maxi(0, 6 + c.literacy / 50 + 3 * edu.x + 10 * edu.y + int(lmod["tech"]))


## Pontos por mês com o financiamento atual (cada 20% da renda dobram a pesquisa).
func tech_gain(c: Country) -> int:
	var b := tech_gain_base(c)
	return b + b * c.research_pct / 20


func estimate_monthly(c: Country) -> Dictionary:
	var tax := 0
	var flat := 0
	var prod := 0
	var industry := 0          # lucro bruto das fábricas (receita - insumos): padrão de vida e política
	var industry_state := 0    # o que o tesouro recebe das fábricas (imposto, ou lucro se estatais)
	var f_rev := 0
	var f_inputs := 0
	var f_wages := 0
	var f_tax := 0
	var up_barracks := 0
	var up_infra := 0
	for pid in c.province_ids:
		var p := provinces[pid]
		for ik in ["hospital", "market", "dock"]:
			up_infra += int(p.bld.get(ik, 0)) * int(Province.GOV_UPKEEP[ik])
		tax += p.monthly_tax(c.tax_pct)
		industry += p.factory_profit()
		up_barracks += p.barracks * int(Province.GOV_UPKEEP["barracks"])
		if p.factory != "" and p.factory_level > 0:
			var rp := p.building_report(p.factory, p.factory_level, c.tax_pct)
			industry_state += int(rp["state_income"])
			f_rev += int(rp["revenue"])
			f_inputs += int(rp["inputs_cost"])
			f_wages += int(rp["wages"])
			f_tax += int(rp["tax"])
		flat += Province.FLAT_TAX
		prod += p.production()
	var lm := law_mods(c)
	tax = tax * (1000 + c.literacy / 5) / 1000      # alfabetização: até ~+19% de imposto
	tax = tax * (100 + int(lm["tax"]) + tech_tax_bonus(c)) / 100
	if c.stability < UNREST_TAX_STABILITY:
		tax = tax * (70 + c.stability * 3 / 4) / 100       # instabilidade reduz a arrecadação
	var regs := regiments_of(c.id)
	var up_prov: int = c.province_ids.size() * EXPENSE_PER_PROVINCE
	var up_army: int = regs * REGIMENT_UPKEEP * (100 + int(lm["army"])) / 100 * (100 - tech_army_discount(c)) / 100
	var up_navy: int = c.ships * SHIP_UPKEEP
	var edu := edu_levels(c)
	var up_edu: int = edu.x * SCHOOL_UPKEEP + edu.y * UNIVERSITY_UPKEEP
	var trade: int = int(trade_bonus[c.id]) if c.id < trade_bonus.size() else 0
	trade = trade * (100 + int(lm["trade"])) / 100
	var up_research: int = maxi(0, tax + industry_state + trade) * c.research_pct / 100
	return {
		"upkeep_research": up_research,
		"income": tax + industry_state + trade, "industry": industry, "trade": trade,
		"industry_state": industry_state, "factory_revenue": f_rev, "factory_inputs": f_inputs,
		"factory_wages": f_wages, "factory_tax": f_tax, "upkeep_barracks": up_barracks,
		"expense": up_prov + up_army + up_navy + up_edu + up_barracks + up_infra + up_research, "upkeep_infra": up_infra, "upkeep_edu": up_edu, "regiments": regs,
		"flat": flat, "production": prod, "upkeep_prov": up_prov, "upkeep_army": up_army, "upkeep_navy": up_navy,
	}


## Desemprego (% da força de trabalho, 0..20). A economia de subsistência absorve 80% da força de
## trabalho; os 20% restantes procuram emprego formal (minas, fazendas, fábricas, escolas...), cuja
## capacidade vem de Province.JOBS_PER_LEVEL x JOB_SCALE. Sem empregos formais: 20%.
@warning_ignore("integer_division")
func unemployment_pct(c: Country) -> int:
	var pop := maxi(1, population_of(c))
	var surplus := pop * LABOR_FORCE_PCT / 100 * SURPLUS_LABOR_PCT / 100
	if surplus <= 0:
		return 0
	var jobs := 0
	for pid in c.province_ids:
		var p := provinces[pid]
		for kind in Province.JOBS_PER_LEVEL.keys():
			var lv := p.building_level(str(kind))
			if lv > 0:
				jobs += int(Province.JOBS_PER_LEVEL[kind]) * lv
	jobs *= JOB_SCALE
	return SURPLUS_LABOR_PCT * maxi(0, surplus - jobs) / surplus


## População total do país.
func population_of(c: Country) -> int:
	var n := 0
	for pid in c.province_ids:
		n += provinces[pid].population
	return n


## Padrão de vida em décimos de ponto: produção por habitante (com indústria) + alfabetização.
@warning_ignore("integer_division")
func standard_of_living_x10(c: Country, e: Dictionary) -> int:
	var pop := maxi(1, population_of(c))
	return 30 + (int(e["production"]) + int(e["industry"])) * 1000000 / pop + c.literacy / 10


## As N províncias do país que mais rendem imposto: [{id, tax}].
func top_provinces(c: Country, n: int) -> Array:
	var rows: Array = []
	for pid in c.province_ids:
		rows.append({"id": pid, "tax": provinces[pid].monthly_tax(c.tax_pct)})
	rows.sort_custom(func(a, b): return a["tax"] > b["tax"] or (a["tax"] == b["tax"] and a["id"] < b["id"]))
	return rows.slice(0, n)


# ---------------------------------------------------------------------------
# Derivados de país
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Mercado mundial: oferta (produção de todas as províncias) x demanda (proporcional à
# população). Preço sobe se falta, cai se sobra; ele multiplica a renda de cada província.
# ---------------------------------------------------------------------------
func goods_list() -> Array:
	var g: Array = Province.RESOURCE_PRICE.keys()
	g.append_array(Province.PROCESSED.keys())
	g.sort()
	return g


func market_supply() -> Dictionary:
	var sup := {}
	for g in goods_list():
		sup[g] = 0
	for p in provinces:
		if p.owner_id < 0:
			continue
		if sup.has(p.resource_type):
			sup[p.resource_type] = int(sup[p.resource_type]) + p.units()
		if p.side_timber() > 0:
			sup["timber"] = int(sup["timber"]) + p.side_timber()
		if p.factory != "" and p.factory_level > 0:
			var f: Dictionary = Province.FACTORIES[p.factory]
			var out: String = f["out"]
			sup[out] = int(sup[out]) + int(f["amount"]) * p.factory_level
	return sup


func market_population() -> int:
	var n := 0
	for p in provinces:
		if p.owner_id >= 0:
			n += p.population
	return maxi(1, n)


func _init_market() -> void:
	EconomyManager.reset_history()
	market_dem.clear()
	var sup := market_supply()
	for g in goods_list():
		# bens processados começam sem oferta: demanda-base fixa cria escassez e lucro
		market_dem[g] = 3000 if Province.PROCESSED.has(g) else int(sup[g])
	market_pop0 = market_population()
	local_price.clear()
	trade_imp.clear()
	trade_exp.clear()
	trade_bonus.clear()
	for c in countries:
		var tbl := {}
		for g in goods_list():
			tbl[g] = 100
		local_price.append(tbl)
		trade_imp.append({})
		trade_exp.append({})
		trade_bonus.append(0)
	Province.country_prices = local_price


## Oferta e demanda locais de cada país: [sup, dem, ports, pops] (listas por id de país).
@warning_ignore("integer_division")
func market_tables() -> Array:
	var n := countries.size()
	var goods := goods_list()
	var sup: Array = []
	var dem: Array = []
	var pops: Array = []
	for i in n:
		var sd := {}
		var dd := {}
		for g in goods:
			sd[g] = 0
			dd[g] = 0
		sup.append(sd)
		dem.append(dd)
		pops.append(0)
	for p in provinces:
		var o := p.owner_id
		if o < 0 or o >= n:
			continue
		pops[o] += p.population
		if sup[o].has(p.resource_type):
			sup[o][p.resource_type] += p.units()
		if p.side_timber() > 0:
			sup[o]["timber"] += p.side_timber()
		if p.factory != "" and p.factory_level > 0:
			var f: Dictionary = Province.FACTORIES[p.factory]
			sup[o][f["out"]] += int(f["amount"]) * p.factory_level
			var ins: Dictionary = f["inputs"]
			for g in ins.keys():
				dem[o][g] += int(ins[g]) * p.factory_level
	for i in n:
		for g in goods:
			dem[i][g] += int(market_dem[g]) * int(pops[i]) / market_pop0
	return [sup, dem, pops]


## Comércio mensal: cada país com déficit de um bem compra de quem tem sobra. Vizinhos por
## terra comerciam livre; por mar gasta capacidade (portos + navios) dos DOIS lados. Guerra e
## embargo bloqueiam. Depois, o preço local se ajusta ao saldo e o comércio rende ouro:
## exportador vende ao preço do comprador; importador ganha tarifas.
@warning_ignore("integer_division")
func _run_trade() -> void:
	var n := countries.size()
	var goods := goods_list()
	var tb := market_tables()
	var sup: Array = tb[0]
	var dem: Array = tb[1]

	var adj := {}
	for p in provinces:
		var a := p.owner_id
		if a < 0:
			continue
		for nb in p.neighbors:
			var b := provinces[int(nb)].owner_id
			if b >= 0 and b != a:
				adj[a * 1000 + b] = true
	var cap: Array = []
	for i in n:
		cap.append(sea_capacity(i) if countries[i].is_alive() else 0)

	var zmask: Array = _zone_mask_of_all()
	var route_cache := {}
	for gi in gate_flow.size():
		gate_flow[gi] = 0
	trade_imp.clear()
	trade_exp.clear()
	trade_bonus.clear()
	for i in n:
		trade_imp.append({})
		trade_exp.append({})
		trade_bonus.append(0)

	for g in goods:
		var avail: Array = []
		var exporters: Array = []
		for e in n:
			var surplus: int = int(sup[e][g]) - int(dem[e][g])
			avail.append(maxi(0, surplus))
			if surplus > 0:
				exporters.append(e)
		if exporters.is_empty():
			continue
		var base := Province.base_price(g)
		for i in n:
			var need: int = int(dem[i][g]) - int(sup[i][g])
			if need <= 0:
				continue
			for by_sea in [false, true]:
				if need <= 0:
					break
				for e in exporters:
					if need <= 0:
						break
					if e == i or int(avail[e]) <= 0 or trade_blocked(i, e):
						continue
					var land: bool = adj.has(i * 1000 + e) or adj.has(e * 1000 + i)
					if land == by_sea:
						continue
					var q: int = mini(need, int(avail[e]))
					var rgates: Array = []
					if not land:
						var rk: int = i * 1000 + e
						if not route_cache.has(rk):
							route_cache[rk] = _route_gates(int(zmask[i]), int(zmask[e]))
						rgates = route_cache[rk]
						var closed := false
						for gi in rgates:
							var gc := gate_controller(int(gi))
							if gc >= 0 and gc != i and gc != e and (trade_blocked(gc, i) or trade_blocked(gc, e)):
								closed = true
								break
						if closed:
							continue
						q = mini(q, mini(int(cap[i]), int(cap[e])))
						if q <= 0:
							continue
						cap[i] = int(cap[i]) - q
						cap[e] = int(cap[e]) - q
					need -= q
					avail[e] = int(avail[e]) - q
					trade_imp[i][g] = int(trade_imp[i].get(g, 0)) + q
					trade_exp[e][g] = int(trade_exp[e].get(g, 0)) + q
					var pi: int = int(local_price[i][g])
					var pe: int = int(local_price[e][g])
					trade_bonus[e] = int(trade_bonus[e]) + q * base * (pi - pe) / 10000
					trade_bonus[i] = int(trade_bonus[i]) + q * base * pi / 10000 * TRADE_TARIFF_PCT / 100
					for gi in rgates:
						gate_flow[int(gi)] = int(gate_flow[int(gi)]) + q
						var gc2 := gate_controller(int(gi))
						var toll_pct: int = int(gates[int(gi)].get("toll", 0))
						if gc2 >= 0 and gc2 != i and gc2 != e and toll_pct > 0:
							var toll: int = q * base * pi / 10000 * toll_pct / GATE_TOLL_BASE
							trade_bonus[gc2] = int(trade_bonus[gc2]) + toll
							trade_bonus[e] = int(trade_bonus[e]) - toll

	for i in n:
		for g in goods:
			var s: int = int(sup[i][g]) - int(trade_exp[i].get(g, 0)) + int(trade_imp[i].get(g, 0))
			var d: int = int(dem[i][g])
			var delta: int = (d - s) * 8 / maxi(1, maxi(s, d))
			local_price[i][g] = clampi(int(local_price[i][g]) + delta, PRICE_MIN, PRICE_MAX)


func _rebuild_all_countries() -> void:
	for c in countries:
		c.province_ids.clear()
	for p in provinces:
		if p.owner_id >= 0 and p.owner_id < countries.size():
			countries[p.owner_id].province_ids.append(p.id)
	for c in countries:
		_refresh_country_geometry(c)


## Calcula enquadramento e rótulo a partir do MAIOR bloco contínuo de províncias do
## país (impérios com colônias distantes ficam com o nome na metrópole).
func _refresh_country_geometry(c: Country) -> void:
	if c.province_ids.is_empty():
		c.bounds = Rect2()
		return
	var members := {}
	for pid in c.province_ids:
		members[pid] = true
	var seen := {}
	var best_comp: Array[int] = []
	var best_area := -1.0
	for start in c.province_ids:
		if seen.has(start):
			continue
		var comp: Array[int] = []
		var stack: Array[int] = [start]
		seen[start] = true
		var area := 0.0
		while not stack.is_empty():
			var u: int = stack.pop_back()
			comp.append(u)
			area += provinces[u].area
			for v in provinces[u].neighbors:
				if members.has(v) and not seen.has(v):
					seen[v] = true
					stack.append(v)
		if area > best_area:
			best_area = area
			best_comp = comp

	var rect: Rect2 = provinces[best_comp[0]].bounds
	var sum := Vector2.ZERO
	for pid in best_comp:
		rect = rect.merge(provinces[pid].bounds)
		sum += provinces[pid].center
	var mean := sum / float(best_comp.size())

	# O rótulo fica no centro da província mais próxima da média (nunca no mar).
	var best := best_comp[0]
	var best_d := INF
	for pid in best_comp:
		var d := provinces[pid].center.distance_squared_to(mean)
		if d < best_d:
			best_d = d
			best = pid
	c.bounds = rect
	c.label_pos = provinces[best].center
	c.label_size = clampi(int(rect.size.x * 0.10), 12, 48)

	if c.capital < 0 or c.capital >= provinces.size() or provinces[c.capital].owner_id != c.id:
		c.capital = _most_populous(c)


func _most_populous(c: Country) -> int:
	var best := c.province_ids[0]
	for pid in c.province_ids:
		if provinces[pid].population > provinces[best].population:
			best = pid
	return best


# ---------------------------------------------------------------------------
# Sincronização (rede) e save/load
# ---------------------------------------------------------------------------
## Hash FNV-1a do estado relevante. Todos os pares devem obter o mesmo valor
## no mesmo frame; se divergir, houve dessincronização.
func state_hash() -> int:
	var h: int = 2166136261
	h = _mix(h, tick)
	h = _mix(h, frame)
	h = _mix(h, speed)
	h = _mix(h, next_army_id)
	for p in provinces:
		h = _mix(h, p.owner_id)
		h = _mix(h, p.population)
		h = _mix(h, p.manpower)
		h = _mix(h, p.workshop * 10 + p.barracks)
		for k in Province.EXTRA_KINDS:
			h = _mix(h, int(p.bld.get(k, 0)))
		h = _mix(h, (Province.FACTORIES.keys().find(p.factory) + 1) * 10 + p.factory_level)
	for c in countries:
		h = _mix(h, c.treasury)
		h = _mix(h, c.tax_pct)
	for id in armies.keys():
		var a: Army = armies[id]
		h = _mix(h, a.id)
		h = _mix(h, a.owner_id)
		h = _mix(h, a.province_id)
		h = _mix(h, a.regiments)
		h = _mix(h, a.move_left)
		h = _mix(h, a.path.size())
	h = _mix(h, next_fleet_id)
	var fids: Array = fleets.keys()
	fids.sort()
	for id in fids:
		var fl: Fleet = fleets[id]
		h = _mix(h, fl.id)
		h = _mix(h, fl.owner_id)
		h = _mix(h, fl.ships)
		h = _mix(h, fl.cell)
		h = _mix(h, fl.path.size())
	for w in wars:
		h = _mix(h, int(w["a"]) * 1000 + int(w["b"]))
		h = _mix(h, int(w["days"]))
		h = _mix(h, int(w.get("ga", 0)) * 1000 + int(w.get("gb", 0)))
		h = _mix(h, (1 if bool(w.get("capa", false)) else 0) + (2 if bool(w.get("capb", false)) else 0))
	var sk: Array = sieges.keys()
	sk.sort()
	for pid in sk:
		h = _mix(h, int(pid))
		h = _mix(h, int(sieges[pid]["by"]) * 100 + int(sieges[pid]["days"]))
	for tbl in local_price:
		for g in goods_list():
			h = _mix(h, int(tbl.get(g, 100)))
	var rk: Array = relations.keys()
	rk.sort()
	for k in rk:
		h = _mix(h, int(k))
		h = _mix(h, int(relations[k]) + 1000)
	for pr in alliances:
		h = _mix(h, int(pr))
	for o in peace_offers:
		h = _mix(h, int(o["from"]) * 1000 + int(o["to"]))
		h = _mix(h, int(o["winner"]))
		h = _mix(h, str(o["term"]).length())
		h = _mix(h, int(o["tick"]))
	var pk: Array = peace_cd.keys()
	pk.sort()
	for k in pk:
		h = _mix(h, int(k))
		h = _mix(h, int(peace_cd[k]))
	var tk: Array = truces.keys()
	tk.sort()
	for k in tk:
		h = _mix(h, int(k))
		h = _mix(h, int(truces[k]))
	for t in training:
		h = _mix(h, int(t["province"]))
		h = _mix(h, int(t["owner"]))
		h = _mix(h, int(t["days"]))
		h = _mix(h, 1 if str(t.get("kind", "reg")) == "ship" else 0)
	for c in countries:
		h = _mix(h, c.ships)
		h = _mix(h, c.literacy)
		h = _mix(h, c.tech_pts)
		h = _mix(h, c.research_pct)
		h = _mix(h, c.lit_acc)
		h = _mix(h, c.stability)
		for v in c.sat:
			h = _mix(h, int(v))
		h = _mix(h, 1 if c.auto_front else 0)
		h = _mix(h, c.overlord)
		h = _mix(h, c.overlord_since)
		h = _mix(h, c.last_income)
		h = _mix(h, c.last_expense)
		for v in c.laws:
			h = _mix(h, int(v))
		for v in c.law_cd:
			h = _mix(h, int(v))
	for k in embargoes:
		h = _mix(h, int(k))
	for e in pending_events:
		h = _mix(h, int(e["uid"]))
		h = _mix(h, int(e["days"]))
	h = _mix(h, next_event_uid)
	h = _mix(h, rng.state & 0xFFFFFFFF)
	return h


func _mix(h: int, v: int) -> int:
	return ((h ^ (v & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF


func _prices_to_lists() -> Array:
	var out: Array = []
	for tbl in local_price:
		var row: Array = []
		for g in goods_list():
			row.append(int(tbl.get(g, 100)))
		out.append(row)
	return out


func _fleets_to_list() -> Array:
	var out: Array = []
	var ids: Array = fleets.keys()
	ids.sort()
	for id in ids:
		out.append((fleets[id] as Fleet).to_dict())
	return out


func _bld_str(p: Province) -> String:
	var parts: Array[String] = []
	for k in Province.EXTRA_KINDS:
		var lv: int = int(p.bld.get(k, 0))
		if lv > 0:
			parts.append("%s:%d" % [k, lv])
	return ",".join(parts)


func _country_ints(field: String) -> Array:
	var out: Array = []
	for c in countries:
		out.append(int(c.get(field)))
	return out


func _law_lists(field: String) -> Array:
	var out: Array = []
	for c in countries:
		out.append((c.get(field) as Array).duplicate())
	return out


func _sat_list() -> Array:
	var out: Array = []
	for c in countries:
		out.append(c.sat.duplicate())
	return out


func _literacy_list() -> Array:
	var out: Array = []
	for c in countries:
		out.append(c.literacy)
	return out


func _ships_list() -> Array:
	var out: Array = []
	for c in countries:
		out.append(c.ships)
	return out


func _dict_to_pairs(d: Dictionary) -> Array:
	var out: Array = []
	var ks: Array = d.keys()
	ks.sort()
	for k in ks:
		out.append([int(k), int(d[k])])
	return out


func _sieges_to_list() -> Array:
	var out: Array = []
	var ks: Array = sieges.keys()
	ks.sort()
	for pid in ks:
		out.append({"pid": int(pid), "by": int(sieges[pid]["by"]), "days": int(sieges[pid]["days"])})
	return out


func serialize_state() -> Dictionary:
	var owners: Array = []
	var pops: Array = []
	var mps: Array = []
	var workshops: Array = []
	var blds: Array = []
	var barracks: Array = []
	var fkinds: Array = []
	var flevels: Array = []
	for p in provinces:
		owners.append(p.owner_id)
		pops.append(p.population)
		mps.append(p.manpower)
		workshops.append(p.workshop)
		barracks.append(p.barracks)
		fkinds.append(p.factory)
		flevels.append(p.factory_level)
		blds.append(_bld_str(p))
	var treasury: Array = []
	var taxes: Array = []
	var capitals: Array = []
	for c in countries:
		treasury.append(c.treasury)
		taxes.append(c.tax_pct)
		capitals.append(c.capital)
	var army_list: Array = []
	for id in armies.keys():
		var a: Army = armies[id]
		army_list.append(a.to_dict())
	return {
		"version": 2,
		"tick": tick,
		"frame": frame,
		"speed": speed,
		"date": clock.to_dict(),
		"owners": owners,
		"cores": _province_cores(),
		"pops": pops,
		"manpower": mps,
		"workshops": workshops,
		"bld": blds,
		"tech": _country_ints("tech_pts"),
		"lit_acc": _country_ints("lit_acc"),
		"stab": _country_ints("stability"),
		"sat": _sat_list(),
		"auto_front": _country_ints("auto_front"),
		"overlord": _country_ints("overlord"),
		"overlord_since": _country_ints("overlord_since"),
		"research_pct": _country_ints("research_pct"),
		"last_income": _country_ints("last_income"),
		"last_expense": _country_ints("last_expense"),
		"laws": _law_lists("laws"),
		"law_cd": _law_lists("law_cd"),
		"barracks": barracks,
		"factory": fkinds,
		"factory_lvl": flevels,
		"treasury": treasury,
		"taxes": taxes,
		"capitals": capitals,
		"armies": army_list,
		"training": training.duplicate(true),
		"wars": wars.duplicate(true),
		"sieges": _sieges_to_list(),
		"relations": _dict_to_pairs(relations),
		"market": {"price": _prices_to_lists(), "dem": market_dem.duplicate(), "pop0": market_pop0},
		"literacy": _literacy_list(),
		"embargoes": embargoes.duplicate(),
		"alliances": alliances.duplicate(),
		"truces": _dict_to_pairs(truces),
		"peace_offers": peace_offers.duplicate(true),
		"peace_cd": _dict_to_pairs(peace_cd),
		"next_army_id": next_army_id,
		"fleets": _fleets_to_list(),
		"next_fleet_id": next_fleet_id,
		"events": pending_events.duplicate(true),
		"fired": fired_events.keys(),
		"next_event_uid": next_event_uid,
		"rng": str(rng.state),   # texto: o estado é uint64 e o JSON só guarda float
	}


func _province_cores() -> Array:
	var out: Array = []
	for p in provinces:
		out.append(p.core_owner)
	return out


func load_state(d: Dictionary) -> bool:
	var cores: Array = d.get("cores", [])
	for i in mini(cores.size(), provinces.size()):
		provinces[i].core_owner = int(cores[i])
	var owners: Array = d.get("owners", [])
	var pops: Array = d.get("pops", [])
	var mps: Array = d.get("manpower", [])
	var workshops: Array = d.get("workshops", [])
	var barracks: Array = d.get("barracks", [])
	var treasury: Array = d.get("treasury", [])
	var taxes: Array = d.get("taxes", [])
	var capitals: Array = d.get("capitals", [])
	var np := provinces.size()
	if owners.size() != np or pops.size() != np or mps.size() != np or workshops.size() != np or barracks.size() != np:
		push_error("GeoEmpire: snapshot incompatível com o mapa carregado")
		return false
	if treasury.size() != countries.size() or taxes.size() != countries.size() or capitals.size() != countries.size():
		push_error("GeoEmpire: snapshot incompatível (países)")
		return false

	for i in np:
		provinces[i].owner_id = int(owners[i])
		provinces[i].population = int(pops[i])
		provinces[i].manpower = int(mps[i])
		provinces[i].workshop = int(workshops[i])
		provinces[i].barracks = int(barracks[i])
		var fk: Array = d.get("factory", [])
		var fl: Array = d.get("factory_lvl", [])
		provinces[i].factory = str(fk[i]) if i < fk.size() else ""
		provinces[i].factory_level = int(fl[i]) if i < fl.size() else 0
		provinces[i].bld = {}
		var bs: Array = d.get("bld", [])
		if i < bs.size() and str(bs[i]) != "":
			for part in str(bs[i]).split(","):
				var kv := part.split(":")
				if kv.size() == 2 and Province.EXTRA_KINDS.has(kv[0]):
					provinces[i].bld[kv[0]] = int(kv[1])
	for i in countries.size():
		countries[i].treasury = int(treasury[i])
		countries[i].tax_pct = int(taxes[i])
		countries[i].capital = int(capitals[i])

	armies.clear()
	var raw_armies: Array = d.get("armies", [])
	for ad in raw_armies:
		var a := Army.from_dict(ad)
		armies[a.id] = a
	training.clear()
	var raw_training: Array = d.get("training", [])
	for t in raw_training:
		training.append({"province": int(t["province"]), "owner": int(t["owner"]), "days": int(t["days"]), "kind": str(t.get("kind", "reg"))})
	next_army_id = int(d.get("next_army_id", 1))
	fleets.clear()
	for fd in d.get("fleets", []):
		var fl := Fleet.from_dict(fd)
		fleets[fl.id] = fl
	next_fleet_id = int(d.get("next_fleet_id", 1))
	wars.clear()
	for w in d.get("wars", []):
		var held_in: Dictionary = {}
		var raw_held: Variant = w.get("held", {})
		if typeof(raw_held) == TYPE_DICTIONARY:
			for hk in raw_held:
				held_in[int(hk)] = int(raw_held[hk])
		wars.append({"held": held_in, "a": int(w["a"]), "b": int(w["b"]), "days": int(w["days"]),
			"na": int(w.get("na", 1)), "nb": int(w.get("nb", 1)), "ga": int(w.get("ga", 0)), "gb": int(w.get("gb", 0)),
			"capa": bool(w.get("capa", false)), "capb": bool(w.get("capb", false))})
	if d.has("market"):
		var mk: Dictionary = d["market"]
		var gl := goods_list()
		var rows: Array = mk.get("price", [])
		for i in mini(rows.size(), local_price.size()):
			for j in gl.size():
				local_price[i][gl[j]] = int(rows[i][j]) if j < rows[i].size() else 100
		for g in gl:
			market_dem[g] = int(mk["dem"].get(g, 0))
		market_pop0 = maxi(1, int(mk.get("pop0", 1)))
	var tp: Array = d.get("tech", [])
	var la: Array = d.get("lit_acc", [])
	for i in countries.size():
		countries[i].tech_pts = int(tp[i]) if i < tp.size() else countries[i].tech_pts
		countries[i].lit_acc = int(la[i]) if i < la.size() else 0
	var stb: Array = d.get("stab", [])
	var sts: Array = d.get("sat", [])
	for i in countries.size():
		countries[i].stability = int(stb[i]) if i < stb.size() else 50
		countries[i].sat = [50, 50, 50, 50, 50, 50]
		if i < sts.size():
			for j in 6:
				countries[i].sat[j] = int(sts[i][j])
	var ovl: Array = d.get("overlord", [])
	var ovs: Array = d.get("overlord_since", [])
	for i in countries.size():
		countries[i].overlord = int(ovl[i]) if i < ovl.size() else -1
		countries[i].overlord_since = int(ovs[i]) if i < ovs.size() else 0
	var rsp: Array = d.get("research_pct", [])
	for i in countries.size():
		countries[i].research_pct = int(rsp[i]) if i < rsp.size() else 0
	var lin: Array = d.get("last_income", [])
	var lex: Array = d.get("last_expense", [])
	for i in countries.size():
		countries[i].last_income = int(lin[i]) if i < lin.size() else 0
		countries[i].last_expense = int(lex[i]) if i < lex.size() else 0
	var af: Array = d.get("auto_front", [])
	for i in countries.size():
		countries[i].auto_front = (int(af[i]) != 0) if i < af.size() else true
	var lw: Array = d.get("laws", [])
	var lcd: Array = d.get("law_cd", [])
	for i in countries.size():
		_init_laws(countries[i])
		if i < lw.size() and lw[i] is Array and (lw[i] as Array).size() == Laws.group_count():
			for j in Laws.group_count():
				countries[i].laws[j] = int(lw[i][j])
				countries[i].law_cd[j] = int(lcd[i][j]) if i < lcd.size() and lcd[i] is Array and j < (lcd[i] as Array).size() else 0
	var lit: Array = d.get("literacy", [])
	for i in countries.size():
		countries[i].literacy = int(lit[i]) if i < lit.size() else countries[i].literacy
	for c in countries:
		c.ships = 0
	for id in fleets.keys():
		var fl2: Fleet = fleets[id]
		if fl2.owner_id >= 0 and fl2.owner_id < countries.size():
			countries[fl2.owner_id].ships += fl2.ships
	embargoes.clear()
	for k in d.get("embargoes", []):
		embargoes.append(int(k))
	relations.clear()
	for r in d.get("relations", []):
		relations[int(r[0])] = int(r[1])
	alliances.clear()
	for pr in d.get("alliances", []):
		alliances.append(int(pr))
	peace_offers.clear()
	for o in d.get("peace_offers", []):
		peace_offers.append({"from": int(o["from"]), "to": int(o["to"]), "winner": int(o["winner"]), "term": str(o["term"]), "tick": int(o["tick"])})
	peace_cd.clear()
	for r in d.get("peace_cd", []):
		peace_cd[int(r[0])] = int(r[1])
	truces.clear()
	for r in d.get("truces", []):
		truces[int(r[0])] = int(r[1])
	sieges.clear()
	for sd in d.get("sieges", []):
		sieges[int(sd["pid"])] = {"by": int(sd["by"]), "days": int(sd["days"])}

	pending_events.clear()
	var raw_events: Array = d.get("events", [])
	for e in raw_events:
		pending_events.append({"uid": int(e["uid"]), "country": int(e["country"]), "event": str(e["event"]), "days": int(e["days"])})
	fired_events.clear()
	var raw_fired: Array = d.get("fired", [])
	for k in raw_fired:
		fired_events[str(k)] = true
	next_event_uid = int(d.get("next_event_uid", 1))
	rng.state = str(d.get("rng", "0")).to_int()

	tick = int(d.get("tick", 0))
	frame = int(d.get("frame", 0))
	speed = clampi(int(d.get("speed", 1)), 0, MAX_SPEED)
	clock.from_dict(d.get("date", {}))
	_rebuild_all_countries()
	Events.state_loaded.emit()
	Events.speed_changed.emit(speed)
	return true


func save_game(path: String = SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(serialize_state()))
	return true


func load_game(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = data
	return load_state(dict)

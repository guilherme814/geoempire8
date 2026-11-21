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
const AUTOSAVE_PATH := "user://autosave.json"
const AUTOSAVE_PREV := "user://autosave_prev.json"
const EVENT_DECISION_DAYS := 30   # sem escolha, vale a 1ª opção (também vale para países sem jogador)

## Dias simulados por segundo em cada velocidade (0 = pausado).
const SPEED_TPS: Array[float] = [0.0, 2.0, 5.0, 10.0, 25.0]
const MAX_SPEED := 4
const FRAME_BUDGET_US := 12000
const ALLOW_DEBUG_COMMANDS := true
const DEFAULT_PLAYER_TAG := "GBR"

# Economia
const EXPENSE_PER_PROVINCE := 1
const REGIMENT_UPKEEP := 2
const MIN_START_TREASURY := 300
const MAX_TECH := 6                  # nível máximo de tecnologia
## Política de imigração inicial (0 fechada, 1 seletiva, 2 aberta): isolamento do Japão, da China
## e da Coreia; "terras novas" abertas aos imigrantes.
const IMMIGRATION_START := {
	"JAP": 0, "QNG": 0, "KOR": 0, "VNM": 0, "ETH": 0,
	"USA": 2, "TEX": 2, "ARG": 2, "URU": 2, "BRZ": 2, "CHL": 2,
}
const TECH_BANK_MAX := 600           # teto do banco de pontos de pesquisa
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
const LEGIT_FLOOR := 200                         # corrente só pesa na legitimidade acima de 20%
const LEGIT_DIV := 400
const LEGIT_MAX := 6                             # legitimidade das leis: -6..+6 na satisfação-alvo
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
const PORT_TRADE_PCT := 4
const PORT_TRADE_MAX := 30
const PORT_CAP := 40             # capacidade básica por porto (província costeira)
const PRICE_MIN := 70
const PRICE_MAX := 140
const TARIFF_MAX := 30
const TARIFF_STEP := 5
const ELECTION_MONTHS := 48          # eleições a cada 4 anos
const ELECTION_STAB_MAX := 4         # efeito máximo da eleição na estabilidade
const SEAT_TOTAL := 100
const PARTY_NAMES := ["Partido Conservador", "Partido Liberal", "Partido Socialista", "Partido Nacionalista", "Partido Reacionário"]
const PANIC_RISK := 50               # risco financeiro a partir do qual pode haver pânico
const PANIC_MONTHS := 12
const PANIC_CAPITAL_LOSS_PCT := 40   # corrida aos bancos: capital privado perdido
const PANIC_TAX_PCT := 8             # arrecadação perdida durante o pânico
const PANIC_CONTAGION := 25          # risco extra em 1837 (contágio do Pânico de 1837)
const EXCISE_MAX := 20
const EXCISE_STEP := 5
const EXCISE_BASE_PCT := 60          # parte da produção que vira consumo tributável
const EVASION_MIN := 3
const EVASION_MAX := 45
const TARIFF_VOLUME_LOSS := 3     # cada 2 pontos acima de TRADE_TARIFF_PCT cortam 3% das importações
const TRADE_TARIFF_PCT := 10     # ganho do importador (tarifas) sobre o valor importado

# Diplomacia
const IMPROVE_COST := 50
const LOAN_STEP := 500           # valor de cada empréstimo/amortização
const LOAN_RATE_PCT := 2         # juros mensais padrão sobre a dívida
const RATE_MIN := 1
const RATE_MAX := 4
const PRINT_STEP := 1000         # moeda emitida por comando
const INFLATION_MAX := 40
const DRILL_NAMES := ["Recrutas", "Regulares", "Elite"]
const DRILL_UPKEEP_PCT := 20     # +% de manutenção do exército por nível de instrução
const DRILL_LOSS_PCT := 10       # -% de perdas em batalha por nível de instrução
const AID_COST := 200            # custo da ajuda financeira
const AID_GIFT := 120            # o que o país ajudado recebe
const AID_OPINION := 25
const JUSTIFY_COST := 150         # fabricar casus belli
const JUSTIFY_DAYS := 90          # tempo até a justificativa ficar pronta
const CB_VALID_DAYS := 720        # validade depois de pronta
const TREATY_DAYS := 720          # duração dos tratados
const TREATY_COST := [0, 100]     # custo de propor: [não agressão, comercial]
const TREATY_MIN_OPINION := [20, 10]
const TREATY_NAMES := ["Pacto de não agressão", "Acordo comercial"]
const TREATY_TRADE_PCT := 6       # % de comércio por acordo comercial (máx. 3)
const PACT_BREAK_INFAMY := 15
const PACT_BREAK_OPINION := 30
const INFAMY_WAR := 20           # declarar guerra
const INFAMY_ANNEX := 30         # anexar um país na paz
const INFAMY_DECAY := 2          # queda mensal
const INFAMY_BAD := 50           # mal visto: todos perdem opinião sobre o país a cada mês
const INFAMY_PARIAH := 100       # pária: ninguém aceita aliança, ajuda ou melhora de relações
const INFAMY_MAX := 300
const HEGEMONY_PCT := 25         # % das províncias do mundo para a vitória por hegemonia
const GREAT_POWER_YEAR := 1900   # ano em que se avalia a vitória "Grande Potência" (top 5 em províncias)
const SPY_COST := 300            # custo de uma operação de espionagem
const SPY_COOLDOWN := 6          # meses entre operações
const SPY_CHANCE := [55, 50, 50] # chance de sucesso (%) por operação
const SPY_TECH_GAIN := 60        # pontos de tecnologia roubados
const SPY_SABOTAGE_PCT := 12     # % do tesouro do alvo destruído
const SPY_UNREST := 8            # queda de satisfação de todos os grupos
const SPY_CAUGHT_OPINION := 30   # perda de opinião se o agente é capturado
const SCIENCE_ALLY_PCT := 10     # +% de pesquisa por aliado mais avançado (até 3)
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
var trade_sea_use: Array = []     # comboios usados por país no último mês (derivado)
var gate_flow: Array = []          # carga que passou por cada passagem no último mês (derivado)
var prov_zone: PackedInt32Array = PackedInt32Array()
var _zone_paths: Array = []        # [zona][zona] -> lista de índices de passagens
var embargoes: Array = []          # emissor*1000+alvo
var trade_imp: Array = []          # por país: {bem -> unidades} (derivado, mostra o último mês)
var trade_exp: Array = []
var trade_bonus: Array = []
var market_dem: Dictionary = {}
var market_pop0: int = 1
var famine_regions: int = 0       # (só apresentação) províncias em região com fome no último mês
var relations: Dictionary = {}   # par -> opinião (-100..100)
var alliances: Array = []        # pares aliados
var peace_offers: Array = []       # propostas de paz pendentes (IA -> jogador): from, to, winner, term, tick
## Escalada de pressão da IA: aggressor*1000+alvo -> nível*1000000 + tick da última subida.
## Nível 1 protesto, 2 ultimato, 3 prazo esgotado (só então a IA pode declarar guerra a um humano).
var pressure: Dictionary = {}
const PRESSURE_STEP_DAYS := 45      # tempo mínimo entre os degraus
const PRESSURE_FORGET_DAYS := 180   # sem nova pressão, o nível cai um degrau
const PRESSURE_WAR_LEVEL := 2       # nível exigido para a IA atacar um jogador
var peace_cd: Dictionary = {}      # par -> tick até o qual a IA não oferece paz de novo
var truces: Dictionary = {}      # par -> tick em que a trégua acaba
var cb: Dictionary = {}          # casus belli: atacante*1000+alvo -> tick em que a justificativa fica pronta
var treaties: Dictionary = {}    # tratados: par*10+tipo (0 não agressão, 1 comercial) -> tick em que vence

var event_defs: Array = []         # definições de data/events.json (somente leitura)
var pending_events: Array = []     # [{uid, country, event, days}]
var fired_events: Dictionary = {}  # "pais|evento" -> true (eventos "once")
var next_event_uid: int = 1

var tick: int = 0     # dias simulados
var frame: int = 0    # passos executados (inclui frames com o jogo pausado)
var speed: int = 1
var player_country: int = 0
## Motivo da última ordem da IA por exército (só exibição; fora do save e do hash).
var ai_notes: Dictionary = {}
## Teatros de guerra calculados pela IA por país (só exibição; fora do save e do hash).
var ai_theaters: Dictionary = {}
var lockstep: bool = false   # true quando o Net controla o avanço do tempo
var world_seed: int = 1836
var history: Dictionary = {}       # dados históricos de 1836 por tag (data/history_1836.json)
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _acc: float = 0.0
## Turno mensal fatiado: só no jogo local (não em lockstep). -1 = nenhum pendente.
## Enquanto pendente, os dias não avançam e os comandos esperam na fila; o resultado é idêntico
## ao turno síncrono (mesma ordem das etapas), só distribuído em vários quadros.
var slice_months: bool = false
var _month_stage: int = -1
var _month_running: bool = false   # true enquanto uma etapa do mês executa (proteção contra reentrada)
var month_hook: Callable = Callable()   # só para testes: chamado ao fim da última etapa
var _month_t0: int = 0
var month_budget_us: int = 9000   # orçamento por quadro para o mês fatiado
var _deadline_us: int = 0         # 0 = sem limite (mês síncrono)
var _sub: int = 0                 # cursor dentro da etapa atual
var _ms: Dictionary = {}          # dados temporários do mês em andamento (não salvos)
var _stage_acc: int = 0
var _mt_cache: Array = []         # tabelas de mercado do mês (reaproveitadas pelo registro)
var _cmd_queue: Array = []
## Conquistas do jogador local (vitórias já alcançadas e derrota); fazem parte do save e do hash.
var victories: Array = []
var defeated: bool = false
## Contador de comandos aplicados (só para a interface saber se algo mudou; fora do save e do hash).
var cmd_seq: int = 0
var ai_heg: int = -1   # hegemon mundial calculado a cada 30 dias (usado pelo planejamento fatiado da IA)
const MONTH_STAGES := 15
const STAGE_NAMES := ["m_prov", "m_migr_a", "m_migr_b", "m_migr_c", "m_trade_a", "m_trade_b", "m_trade_c", "m_countries",
	"m_politics", "m_econ", "m_aipeace", "m_rel", "m_events", "m_record", "m_emit"]


func _ready() -> void:
	load_world()


func _process(delta: float) -> void:
	if loaded and _month_stage >= 0:
		_run_month_slice()
		return
	if not loaded or lockstep or speed <= 0:
		return
	_acc += delta
	var interval: float = 1.0 / SPEED_TPS[speed]
	var steps := 0
	var t0: int = Time.get_ticks_usec()
	while _acc >= interval and steps < 8:
		_acc -= interval
		step()
		steps += 1
		if speed <= 0:
			break
		# Orçamento de quadro: se os dias já gastaram >12 ms, devolve o controle ao render e
		# retoma no próximo quadro (a ordem dos passos não muda: continua determinístico).
		if Time.get_ticks_usec() - t0 > FRAME_BUDGET_US:
			break
	if steps >= 8 or _acc > 1.0:
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
	var qx: int = 10 + 3 * countries[x.owner_id].tech_level() + int(tech_fx(countries[x.owner_id])["nav"])
	var qy: int = 10 + 3 * countries[y.owner_id].tech_level() + int(tech_fx(countries[y.owner_id])["nav"])
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
	cb.clear()
	treaties.clear()
	peace_offers.clear()
	peace_cd.clear()
	pressure.clear()
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
		_set_tech_level(c, int(TECH_START.get(c.tag, 0)))
		c.immigration = int(IMMIGRATION_START.get(c.tag, 1))
		c.lit_acc = 0
		_init_laws(c)
		# O desenvolvimento industrial histórico adianta a tecnologia inicial.
		var hh: Dictionary = history.get(c.tag, {})
		var ind_lvl: int = int(hh.get("ind", 0)) * 3 / 5
		if ind_lvl > c.tech_level():
			_set_tech_level(c, ind_lvl)
		if not hh.is_empty():
			c.tax_pct = 20 + 4 * int(hh.get("tax", 2))   # capacidade fiscal histórica
			c.elect_cd = 6 + c.id % 42                      # eleições escalonadas entre os países
		var prof: Dictionary = hh.get("profile", {})
		if not prof.is_empty():
			# Perfil de referência (países principais): sobrepõe os valores genéricos.
			c.literacy = int(prof.get("lit", c.literacy / 10)) * 10
			_set_tech_level(c, int(prof.get("tech", c.tech_level())))
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
	_apply_start_wars()
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


func can_set_budget(issuer: int, m: int, lv: int) -> bool:
	if issuer < 0 or issuer >= countries.size() or m < 0 or m >= Government.MINISTRIES.size() or lv < 0 or lv > 2:
		return false
	return Government.level(countries[issuer].budget_code, m) != lv


## Por que o decreto não pode ser emitido agora ("" = pode).
func decree_block_reason(issuer: int, di: int) -> String:
	if issuer < 0 or issuer >= countries.size() or di < 0 or di >= Government.DECREES.size():
		return "Decreto inválido"
	var c := countries[issuer]
	if c.decree >= 0:
		return "Já há um decreto em vigor"
	if c.decree_cd > 0:
		return "Aguarde %d meses" % c.decree_cd
	if c.treasury < int(Government.DECREES[di]["cost"]):
		return "Libras insuficientes"
	return ""


func _enact_decree(cid: int, di: int) -> void:
	var c := countries[cid]
	c.treasury -= int(Government.DECREES[di]["cost"])
	c.decree = di
	c.decree_left = int(Government.DECREES[di]["dur"])
	Events.treasury_changed.emit(cid)
	if cid == player_country:
		Events.notice.emit("Decreto: %s (%d meses)." % [Government.DECREES[di]["name"], c.decree_left])


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
	if _month_stage >= 0:
		_cmd_queue.append(cmd)   # espera o fim do mês fatiado (ordem preservada)
		return
	cmd_seq += 1
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

	elif t == Cmd.SET_IMMIGRATION:
		var pol: int = int(cmd.get("policy", -1))
		if issuer >= 0 and issuer < countries.size() and pol >= 0 and pol <= 2:
			countries[issuer].immigration = pol
			Events.treasury_changed.emit(issuer)

	elif t == Cmd.SET_RESEARCH_TARGET:
		if issuer < 0 or issuer >= countries.size():
			return
		var want: int = int(cmd.get("tech", -1))
		var rcn: Country = countries[issuer]
		if want == -1 or Techs.available(rcn, want):
			rcn.researching = want
			Events.treasury_changed.emit(issuer)

	elif t == Cmd.SET_AUTO_FRONT:
		if issuer >= 0 and issuer < countries.size():
			countries[issuer].auto_front = bool(cmd.get("enabled", true))

	elif t == Cmd.SET_RATE:
		var rp: int = int(cmd.get("pct", -1))
		if not can_set_rate(issuer, rp):
			return
		countries[issuer].interest = rp
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.PRINT_MONEY:
		if not can_print(issuer):
			return
		var pc := countries[issuer]
		pc.inflation += print_inflation(pc)
		pc.treasury += PRINT_STEP
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.SET_TARIFF:
		var tp: int = int(cmd.get("pct", -1))
		if not can_set_tariff(issuer, tp):
			return
		countries[issuer].tariff = tp
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.SET_EXCISE:
		var xp: int = int(cmd.get("pct", -1))
		if not can_set_excise(issuer, xp):
			return
		countries[issuer].excise = xp
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.SET_BUDGET:
		var bm: int = int(cmd.get("ministry", -1))
		var bl: int = int(cmd.get("level", -1))
		if not can_set_budget(issuer, bm, bl):
			return
		countries[issuer].budget_code = Government.with_level(countries[issuer].budget_code, bm, bl)
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.DECREE:
		var di: int = int(cmd.get("id", -1))
		if decree_block_reason(issuer, di) != "":
			return
		_enact_decree(issuer, di)

	elif t == Cmd.JUSTIFY:
		var jt: int = int(cmd.get("target", -1))
		if not can_justify(issuer, jt):
			return
		countries[issuer].treasury -= JUSTIFY_COST
		cb[issuer * 1000 + jt] = tick + JUSTIFY_DAYS
		Events.treasury_changed.emit(issuer)
		if issuer == player_country:
			Events.notice.emit("Casus belli contra %s em preparo (%d dias)." % [countries[jt].name, JUSTIFY_DAYS])

	elif t == Cmd.PROPOSE_TREATY:
		var tt: int = int(cmd.get("target", -1))
		var tk: int = int(cmd.get("kind", -1))
		if not can_treaty(issuer, tt, tk):
			return
		if is_human(tt):
			if issuer == player_country:
				Events.notice.emit("Tratados com jogadores ainda não existem.")
			return
		if opinion(issuer, tt) < int(TREATY_MIN_OPINION[tk]):
			if issuer == player_country:
				Events.notice.emit("%s recusa: opinião %d, precisa de %d." % [countries[tt].name, opinion(issuer, tt), int(TREATY_MIN_OPINION[tk])])
			return
		countries[issuer].treasury -= int(TREATY_COST[tk])
		treaties[_pair(issuer, tt) * 10 + tk] = tick + TREATY_DAYS
		relations[_pair(issuer, tt)] = clampi(opinion(issuer, tt) + 5, -100, 100)
		Events.treasury_changed.emit(issuer)
		if issuer == player_country or tt == player_country:
			Events.notice.emit("%s firmado: %s e %s." % [TREATY_NAMES[tk], countries[issuer].name, countries[tt].name])

	elif t == Cmd.BREAK_TREATY:
		var bt: int = int(cmd.get("target", -1))
		var bk: int = int(cmd.get("kind", -1))
		if bt < 0 or bt >= countries.size() or bk < 0 or bk >= TREATY_COST.size() or not treaty_active(issuer, bt, bk):
			return
		treaties.erase(_pair(issuer, bt) * 10 + bk)
		if bk == 0:
			_add_infamy(issuer, PACT_BREAK_INFAMY)
			relations[_pair(issuer, bt)] = clampi(opinion(issuer, bt) - PACT_BREAK_OPINION, -100, 100)
		if issuer == player_country:
			Events.notice.emit("%s com %s rompido." % [TREATY_NAMES[bk], countries[bt].name])

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
		_pressure_relax(target, issuer)   # agrado diplomático acalma quem pressionava
		Events.treasury_changed.emit(issuer)
		Events.war_changed.emit()

	elif t == Cmd.TAKE_LOAN:
		if not can_take_loan(issuer):
			return
		countries[issuer].debt += LOAN_STEP
		countries[issuer].treasury += LOAN_STEP
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.REPAY_LOAN:
		if not can_repay_loan(issuer):
			return
		var pay := mini(LOAN_STEP, countries[issuer].debt)
		countries[issuer].debt -= pay
		countries[issuer].treasury -= pay
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.SET_DRILL:
		if issuer < 0 or issuer >= countries.size():
			return
		countries[issuer].drill = clampi(int(cmd.get("level", 0)), 0, 2)
		Events.treasury_changed.emit(issuer)

	elif t == Cmd.SEND_AID:
		var target: int = int(cmd.get("target", -1))
		if not can_send_aid(issuer, target):
			return
		countries[issuer].treasury -= AID_COST
		countries[target].treasury += AID_GIFT
		relations[_pair(issuer, target)] = mini(100, opinion(issuer, target) + AID_OPINION)
		Events.treasury_changed.emit(issuer)
		Events.treasury_changed.emit(target)
		Events.war_changed.emit()

	elif t == Cmd.SET_RMETHOD:
		var rp: int = int(cmd.get("province", -1))
		var rm: int = int(cmd.get("method", 0))
		if not can_set_rmethod(rp, issuer, rm):
			return
		var rprov := provinces[rp]
		countries[issuer].treasury -= rmethod_cost(rprov, rm)
		rprov.rmethod = rm
		Events.treasury_changed.emit(issuer)
		Events.province_updated.emit(rp)

	elif t == Cmd.SET_METHOD:
		var mp: int = int(cmd.get("province", -1))
		var mm: int = int(cmd.get("method", 0))
		if not can_set_method(mp, issuer, mm):
			return
		var mprov := provinces[mp]
		countries[issuer].treasury -= method_cost(mprov, mm)
		mprov.method = mm
		Events.treasury_changed.emit(issuer)
		Events.province_updated.emit(mp)

	elif t == Cmd.SPY:
		var target: int = int(cmd.get("target", -1))
		var op: int = clampi(int(cmd.get("op", 0)), 0, 2)
		if not can_spy(issuer, target):
			return
		var spy_me := countries[issuer]
		var spy_tg := countries[target]
		spy_me.treasury -= SPY_COST
		spy_me.spy_cd = SPY_COOLDOWN
		var win := rng.randi_range(0, 99) < int(SPY_CHANCE[op]) + mini(15, spy_me.literacy / 8) - mini(15, spy_tg.literacy / 8)
		if win:
			if op == 0:
				spy_me.tech_pts = mini(TECH_BANK_MAX, spy_me.tech_pts + SPY_TECH_GAIN)
			elif op == 1:
				spy_tg.treasury -= maxi(0, spy_tg.treasury) * SPY_SABOTAGE_PCT / 100
			else:
				for gi in 6:
					spy_tg.sat[gi] = clampi(int(spy_tg.sat[gi]) - SPY_UNREST, 0, 100)
				spy_tg.stability = int(politics_of(spy_tg)["stability"])
		else:
			relations[_pair(issuer, target)] = maxi(-100, opinion(issuer, target) - SPY_CAUGHT_OPINION)
		if is_human(issuer):
			Events.notice.emit(("Operação bem-sucedida contra %s." if win else "Seu agente foi capturado em %s!") % spy_tg.name)
		elif is_human(target):
			if not win:
				Events.notice.emit("Agentes de %s foram capturados em seu território." % spy_me.name)
			elif op == 1:
				Events.notice.emit("Sabotagem: parte do seu tesouro foi destruída. Suspeita-se de %s." % spy_me.name)
			elif op == 2:
				Events.notice.emit("Agitadores incitam descontentamento no país. Suspeita-se de %s." % spy_me.name)
		Events.treasury_changed.emit(issuer)
		Events.treasury_changed.emit(target)
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
	_add_infamy(o, INFAMY_ANNEX)
	for pid in countries[v].province_ids.duplicate():
		transfer_province(int(pid), o, false)   # geometria refeita uma vez no fim (resultado idêntico)
	_refresh_country_geometry(countries[v])
	_refresh_country_geometry(countries[o])
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
## Custo em comboios por unidade transportada numa rota marítima: 1 + passagens atravessadas.
func lane_cost(gate_count: int) -> int:
	return 1 + maxi(0, gate_count)


## Efeito de portos como centros comerciais: +4% do comércio por nível de cais (máx. +30%).
func port_trade_pct(c: Country) -> int:
	return mini(PORT_TRADE_MAX, PORT_TRADE_PCT * dock_levels(c.id))


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


## Aliados com mais tecnologias que o país (até 3): cooperação científica.
func science_allies(c: Country) -> int:
	var n := 0
	for a in allies_of(c.id):
		if countries[a].is_alive() and countries[a].techs.size() > c.techs.size():
			n += 1
			if n >= 3:
				break
	return n


## Teto de dívida: cresce com a renda do país.
func loan_limit(c: Country) -> int:
	return 2000 + maxi(0, c.last_income) * 8


func can_take_loan(cid: int) -> bool:
	if cid < 0 or cid >= countries.size() or not countries[cid].is_alive():
		return false
	return countries[cid].debt + LOAN_STEP <= loan_limit(countries[cid])


func can_repay_loan(cid: int) -> bool:
	if cid < 0 or cid >= countries.size():
		return false
	return countries[cid].debt > 0 and countries[cid].treasury >= mini(LOAN_STEP, countries[cid].debt)


## Custo de passar a fábrica ao método `m` (só se paga ao subir; descer é de graça).
@warning_ignore("integer_division")
func method_cost(p: Province, m: int) -> int:
	if m <= p.method:
		return 0
	return int((Province.METHODS[m] as Dictionary)["cost"]) * p.factory_level


## Custo de passar a extração (fazenda/mina/madeireira) ao método `m`.
func rmethod_cost(p: Province, m: int) -> int:
	if m <= p.rmethod:
		return 0
	return int((Province.METHODS[m] as Dictionary)["cost"]) * p.extractor_level()


func can_set_rmethod(pid: int, issuer: int, m: int) -> bool:
	if pid < 0 or pid >= provinces.size() or issuer < 0 or issuer >= countries.size():
		return false
	if m < 0 or m >= Province.METHODS.size():
		return false
	var p := provinces[pid]
	if p.owner_id != issuer or p.extractor_level() <= 0 or p.rmethod == m:
		return false
	if countries[issuer].tech_level() < int((Province.METHODS[m] as Dictionary)["tech"]):
		return false
	return countries[issuer].treasury >= rmethod_cost(p, m)


## IA: moderniza (no máximo 1 melhoria por ciclo) fábricas e extração quando sobra caixa.
func _ai_modernize(c: Country, spare: int) -> void:
	var best: int = 0
	for m in mini(AI_MAX_METHOD + 1, Province.METHODS.size()):
		if c.tech_level() >= int((Province.METHODS[m] as Dictionary)["tech"]):
			best = m
	if best <= 0:
		return
	for pid in c.province_ids:
		var p := provinces[int(pid)]
		if p.factory != "" and p.factory_level > 0 and p.method < best and method_cost(p, best) * 6 <= spare:
			apply_command({"type": "set_method", "province": int(pid), "method": best, "issuer": c.id})
			return
		if p.extractor_level() > 0 and p.rmethod < best and rmethod_cost(p, best) * 6 <= spare:
			apply_command({"type": "set_rmethod", "province": int(pid), "method": best, "issuer": c.id})
			return


func can_set_method(pid: int, issuer: int, m: int) -> bool:
	if pid < 0 or pid >= provinces.size() or issuer < 0 or issuer >= countries.size():
		return false
	if m < 0 or m >= Province.METHODS.size():
		return false
	var p := provinces[pid]
	if p.owner_id != issuer or p.factory == "" or p.factory_level <= 0 or p.method == m:
		return false
	if countries[issuer].tech_level() < int((Province.METHODS[m] as Dictionary)["tech"]):
		return false
	return countries[issuer].treasury >= method_cost(p, m)


## Casus belli: a justificativa pronta e ainda válida de `a` contra `t`.
func has_cb(a: int, t: int) -> bool:
	var key: int = a * 1000 + t
	if not cb.has(key):
		return false
	var ready: int = int(cb[key])
	return tick >= ready and tick < ready + CB_VALID_DAYS


func cb_pending_days(a: int, t: int) -> int:
	var key: int = a * 1000 + t
	return maxi(0, int(cb.get(key, 0)) - tick) if cb.has(key) else 0


func can_justify(a: int, t: int) -> bool:
	if a < 0 or t < 0 or a >= countries.size() or t >= countries.size() or a == t:
		return false
	if not countries[a].is_alive() or not countries[t].is_alive() or at_war(a, t) or allied(a, t):
		return false
	if countries[a].overlord >= 0 or countries[t].overlord == a:
		return false
	if cb.has(a * 1000 + t) and (cb_pending_days(a, t) > 0 or has_cb(a, t)):
		return false
	return countries[a].treasury >= JUSTIFY_COST


func treaty_active(x: int, y: int, kind: int) -> bool:
	return int(treaties.get(_pair(x, y) * 10 + kind, 0)) > tick


func treaty_trade_pct(cid: int) -> int:
	var n := 0
	for k in treaties.keys():
		var key: int = int(k)
		if key % 10 != 1 or int(treaties[k]) <= tick:
			continue
		var pr: int = key / 10
		if pr / 1000 == cid or pr % 1000 == cid:
			n += 1
	return mini(3, n) * TREATY_TRADE_PCT


func can_treaty(issuer: int, target: int, kind: int) -> bool:
	if issuer < 0 or target < 0 or issuer >= countries.size() or target >= countries.size() or issuer == target:
		return false
	if kind < 0 or kind >= TREATY_COST.size():
		return false
	if not countries[issuer].is_alive() or not countries[target].is_alive() or at_war(issuer, target):
		return false
	if countries[issuer].overlord >= 0 or countries[target].overlord >= 0 or countries[target].infamy >= INFAMY_PARIAH:
		return false
	return not treaty_active(issuer, target, kind) and countries[issuer].treasury >= int(TREATY_COST[kind])


func _expire_diplomacy() -> void:
	for k in treaties.keys():
		if int(treaties[k]) <= tick:
			treaties.erase(k)
	for k in cb.keys():
		if tick >= int(cb[k]) + CB_VALID_DAYS:
			cb.erase(k)


## IA: uma vez por ano busca o parceiro de maior opinião para um acordo comercial (e pacto, se confiam muito).
func _ai_treaties(c: Country) -> void:
	if (tick / 30 + c.id) % 12 != 0:
		return
	var best := -1
	var bo := -1000
	for o in countries:
		if o.id == c.id or not o.is_alive() or is_human(o.id):
			continue
		var op: int = opinion(c.id, o.id)
		if op > bo and can_treaty(c.id, o.id, 1):
			bo = op
			best = o.id
	if best < 0 or bo < int(TREATY_MIN_OPINION[1]) + 15:
		return
	apply_command({"type": "propose_treaty", "issuer": c.id, "target": best, "kind": 1})
	if bo >= 40:
		apply_command({"type": "propose_treaty", "issuer": c.id, "target": best, "kind": 0})


## Balança comercial (B8): valor exportado e importado no último mês, a preços locais.
@warning_ignore("integer_division")
func trade_balance(cid: int) -> Array:
	var ex := 0
	var im := 0
	if cid < 0 or cid >= trade_imp.size() or cid >= trade_exp.size():
		return [0, 0]
	for g in trade_exp[cid].keys():
		ex += int(trade_exp[cid][g]) * Province.base_price(str(g)) * int(local_price[cid].get(str(g), 100)) / 10000
	for g in trade_imp[cid].keys():
		im += int(trade_imp[cid][g]) * Province.base_price(str(g)) * int(local_price[cid].get(str(g), 100)) / 10000
	return [ex, im]


## Risco financeiro (0..100), derivado: juros altos, inflação, dívida sobre a renda anual e capital
## privado alavancado; em 1837 soma o contágio do pânico daquele ano.
@warning_ignore("integer_division")
func panic_risk(c: Country) -> int:
	var r: int = (c.interest - 1) * 12 + c.inflation
	if c.debt > 0:          # só calcula a renda (cara) quando há dívida
		var income: int = maxi(1, int(estimate_monthly(c)["income"]))
		r += mini(30, c.debt * 30 / (income * 24))
	r += mini(20, c.private_capital * 20 / PRIVATE_CAPITAL_MAX)
	if clock.year == 1837 and clock.month >= 3:
		r += PANIC_CONTAGION
	return clampi(r, 0, 100)


## Fase do ciclo: 0 expansão, 1 estável, 2 tensão financeira, 3 pânico.
func cycle_phase(c: Country) -> int:
	if c.panic_left > 0:
		return 3
	var r := panic_risk(c)
	if r >= PANIC_RISK:
		return 2
	return 0 if r < 25 else 1


@warning_ignore("integer_division")
func _panic_roll(c: Country) -> int:
	var h: int = (clock.year * 12 + clock.month) * 7919 + c.id * 104729
	h = (h * 1103515245 + 12345) & 0x7fffffff
	return (h >> 8) % 100


## Sufrágio (B15): 0 = sem eleições (autocracia), 1 = censitário (monarquia constitucional),
## 2 = amplo (república). Vem da lei "Sistema de governo".
func suffrage_of(c: Country) -> int:
	var gi: int = Laws.group_index("gov")
	return clampi(int(c.laws[gi]), 0, 2) if gi >= 0 and gi < c.laws.size() else 0


## Cadeiras (soma = SEAT_TOTAL) segundo o eleitorado: censitário só vota aristocratas, burguesia e
## funcionários; amplo vota todas as classes. Mesma fórmula de afinidade da ideologia nacional.
@warning_ignore("integer_division")
func election_seats(c: Country) -> Array:
	var suf: int = suffrage_of(c)
	var out := [0, 0, 0, 0, 0]
	if suf <= 0:
		return out
	var pol := politics_of(c)
	var sh: Array = pol["share"]
	var votes := [0, 0, 0, 0, 0]
	for i in 6:
		if suf == 1 and i != 2 and i != 3 and i != 4:
			continue
		var w: int = int(sh[i]) * CLASS_PART[i] * (1000 + (c.literacy if i < 2 else 0)) / 1000
		var sat: int = int(c.sat[i])
		var shift := clampi(50 - sat, 0, 50)
		for j in 5:
			var v: int = int(CLASS_AFF[i][j]) * (100 - shift)
			if j == int(CLASS_RADICAL[i]):
				v += shift * 100
			votes[j] += v * w / 100
	var tot := 0
	for j in 5:
		tot += int(votes[j])
	if tot <= 0:
		return out
	var given := 0
	var best := 0
	for j in 5:
		out[j] = int(votes[j]) * SEAT_TOTAL / tot
		given += int(out[j])
		if int(votes[j]) > int(votes[best]):
			best = j
	out[best] = int(out[best]) + (SEAT_TOTAL - given)       # sobra vai ao partido mais votado
	return out


## Apoio do governo no parlamento (% das cadeiras): partidos cuja corrente combina com as leis atuais.
func parliament_support(c: Country) -> int:
	var fit: Array = Laws.fit_all(c.laws)
	var s := 0
	for j in 5:
		if int(fit[j]) > 0:
			s += int(c.seats[j])
	return s


func _election_step(c: Country) -> void:
	c.elect_cd -= 1
	if c.elect_cd > 0:
		return
	c.elect_cd = ELECTION_MONTHS
	var seats := election_seats(c)
	var tot := 0
	for j in 5:
		tot += int(seats[j])
	if tot <= 0:
		c.seats = [0, 0, 0, 0, 0]
		return
	c.seats = seats
	var support := parliament_support(c)
	c.stability = clampi(c.stability + clampi((support - 45) / 6, -ELECTION_STAB_MAX, ELECTION_STAB_MAX), 0, 100)
	if is_human(c.id):
		var win := 0
		for j in 5:
			if int(seats[j]) > int(seats[win]):
				win = j
		Events.notice.emit("Eleições: %s venceu com %d cadeiras. Apoio ao governo: %d%%." % [PARTY_NAMES[win], int(seats[win]), support])


func _panic_step(c: Country) -> void:
	if c.panic_left > 0:
		c.panic_left -= 1
		return
	var r := panic_risk(c)
	if r >= PANIC_RISK and _panic_roll(c) < r - PANIC_RISK + 5:
		c.panic_left = PANIC_MONTHS
		c.private_capital = c.private_capital * (100 - PANIC_CAPITAL_LOSS_PCT) / 100
		c.stability = maxi(0, c.stability - 3)
		if is_human(c.id):
			Events.notice.emit("Pânico financeiro! Corrida aos bancos: capital privado e arrecadação caem por %d meses." % PANIC_MONTHS)


func can_set_excise(issuer: int, pct: int) -> bool:
	if issuer < 0 or issuer >= countries.size() or pct < 0 or pct > EXCISE_MAX or pct % EXCISE_STEP != 0:
		return false
	return countries[issuer].excise != pct


## Evasão fiscal (%, 3..45): cresce com a carga (imposto direto acima de 25%, tarifa acima de 10%,
## imposto de consumo) e cai com alfabetização (administração) e bancos. Derivada, sem estado.
@warning_ignore("integer_division")
func tax_evasion(c: Country) -> int:
	var ev: int = 14 + maxi(0, c.tax_pct - 25) * 6 / 10 + maxi(0, c.tariff - 10) * 8 / 10 + c.excise / 2
	ev -= c.literacy / 60 + mini(6, 2 * bld_total(c, "bank"))   # alfabetização vai de 0 a 1000
	return clampi(ev, EVASION_MIN, EVASION_MAX)


func can_set_tariff(issuer: int, pct: int) -> bool:
	if issuer < 0 or issuer >= countries.size() or pct < 0 or pct > TARIFF_MAX or pct % TARIFF_STEP != 0:
		return false
	return countries[issuer].tariff != pct


func can_set_rate(issuer: int, pct: int) -> bool:
	if issuer < 0 or issuer >= countries.size() or pct < RATE_MIN or pct > RATE_MAX:
		return false
	return countries[issuer].interest != pct


## Pontos de inflação gerados ao emitir PRINT_STEP de moeda (mais caro para economias pequenas).
@warning_ignore("integer_division")
func print_inflation(c: Country) -> int:
	return clampi(PRINT_STEP * 6 / maxi(500, c.last_income), 1, 10)


func can_print(issuer: int) -> bool:
	return issuer >= 0 and issuer < countries.size() and countries[issuer].inflation + print_inflation(countries[issuer]) <= INFLATION_MAX


func can_spy(issuer: int, target: int) -> bool:
	if issuer < 0 or target < 0 or issuer >= countries.size() or target >= countries.size() or issuer == target:
		return false
	return countries[issuer].is_alive() and countries[target].is_alive() \
		and countries[issuer].spy_cd <= 0 and countries[issuer].treasury >= SPY_COST


func can_send_aid(issuer: int, target: int) -> bool:
	if issuer < 0 or target < 0 or issuer >= countries.size() or target >= countries.size() or issuer == target:
		return false
	return countries[target].is_alive() and not at_war(issuer, target) and countries[target].infamy < INFAMY_PARIAH \
		and countries[issuer].treasury >= AID_COST and opinion(issuer, target) < 100


func can_improve(issuer: int, target: int) -> bool:
	if issuer < 0 or target < 0 or issuer >= countries.size() or target >= countries.size() or issuer == target:
		return false
	return countries[target].is_alive() and not at_war(issuer, target) and countries[target].infamy < INFAMY_PARIAH \
		and countries[issuer].treasury >= IMPROVE_COST and opinion(issuer, target) < 100


func can_ally(issuer: int, target: int) -> bool:
	if issuer < 0 or target < 0 or issuer >= countries.size() or target >= countries.size() or issuer == target:
		return false
	return countries[target].is_alive() and not at_war(issuer, target) and not allied(issuer, target) \
		and countries[issuer].overlord < 0 and countries[target].overlord < 0 \
		and countries[issuer].infamy < INFAMY_PARIAH and countries[target].infamy < INFAMY_PARIAH


## Declara a guerra e chama os aliados do alvo (defensivo).
func _add_infamy(cid: int, amount: int) -> void:
	if cid < 0 or cid >= countries.size():
		return
	var c := countries[cid]
	var before := c.infamy
	c.infamy = clampi(c.infamy + amount, 0, INFAMY_MAX)
	if cid == player_country and before < INFAMY_PARIAH and c.infamy >= INFAMY_PARIAH:
		Events.notice.emit("Sua infâmia chegou a %d: você é um pária internacional!" % c.infamy)
	elif cid == player_country and before < INFAMY_BAD and c.infamy >= INFAMY_BAD:
		Events.notice.emit("Sua infâmia chegou a %d: o mundo desconfia de você." % c.infamy)


func pressure_level(aggressor: int, target: int) -> int:
	return int(pressure.get(aggressor * 1000 + target, 0)) / 1000000


## Sobe um degrau da escalada se o intervalo mínimo passou. Devolve o nível atual.
func pressure_escalate(aggressor: int, target: int) -> int:
	var key := aggressor * 1000 + target
	var v: int = int(pressure.get(key, 0))
	var lvl: int = v / 1000000
	var t: int = v % 1000000
	if lvl < 3 and (v == 0 or tick - t >= PRESSURE_STEP_DAYS):
		lvl += 1
		pressure[key] = lvl * 1000000 + tick
		if is_human(target):
			var who := countries[aggressor].name
			match lvl:
				1: Events.notice.emit("%s protesta formalmente contra o seu governo." % who)
				2: Events.notice.emit("ULTIMATO: %s exige concessões e mobiliza tropas. Melhore as relações ou prepare-se para a guerra." % who)
				3: Events.notice.emit("%s esgotou a paciência: a guerra pode vir a qualquer momento!" % who)
	return lvl


func _pressure_relax(aggressor: int, target: int) -> void:
	var key := aggressor * 1000 + target
	var v: int = int(pressure.get(key, 0))
	if v == 0:
		return
	var lvl: int = v / 1000000 - 1
	if lvl <= 0:
		pressure.erase(key)
	else:
		pressure[key] = lvl * 1000000 + tick


func _start_war(attacker: int, target: int) -> void:
	pressure.erase(attacker * 1000 + target)
	pressure.erase(target * 1000 + attacker)
	if loaded and not has_cb(attacker, target):
		_add_infamy(attacker, INFAMY_WAR)
	cb.erase(attacker * 1000 + target)
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
	AiDiplomacy.rally(self, attacker, target)
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
	if truce_left(attacker, target) > 0 or treaty_active(attacker, target, 0):
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


func transfer_province(pid: int, to_country: int, refresh: bool = true) -> void:
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
		if refresh:
			_refresh_country_geometry(countries[old])
	countries[to_country].province_ids.append(pid)
	if refresh:
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
	var req: int = int(Province.BUILDINGS[kind].get("req", -1))
	if req >= 0 and not countries[issuer].techs.has(req):
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


func _order_move(a: Army, dest: int, max_hops: int = 0) -> void:
	var start := a.province_id
	if a.is_moving():
		start = a.path[0]   # só dá para redirecionar a partir da próxima província
	var ids := find_path(start, dest)
	if ids.is_empty() or (max_hops > 0 and ids.size() > max_hops):
		return   # IA: não marcha por rotas absurdamente longas
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
	if _month_stage >= 0:
		return   # mês em andamento: o tempo espera
	frame += 1
	if speed > 0:
		_simulate_day()


## Executa etapas do mês dentro de um orçamento de tempo por quadro. As etapas pesadas têm cursor
## (`_sub`) e devolvem false quando o orçamento acaba: continuam no quadro seguinte, na mesma ordem.
func _run_month_slice() -> void:
	if _month_running:
		return
	var t0: int = Time.get_ticks_usec()
	_deadline_us = t0 + month_budget_us
	while _month_stage >= 0 and not _month_running:
		_step_month_stage()
		if _month_stage < 0:
			_acc = 0.0
			break
		if Time.get_ticks_usec() >= _deadline_us:
			break
	_deadline_us = 0


func _over_budget() -> bool:
	return _deadline_us > 0 and Time.get_ticks_usec() >= _deadline_us


## Roda (um pedaço de) UMA etapa. A última etapa (aviso aos ouvintes) zera o índice ANTES de
## executar: se um ouvinte pedir finish_month()/autosave, nada reexecuta (isso causava recursão
## infinita no autosave de janeiro).
func _step_month_stage() -> void:
	var i := _month_stage
	var last := i == MONTH_STAGES - 1
	if last:
		_month_stage = -1
	_month_running = true
	var tm: int = Time.get_ticks_usec()
	var done: bool = _month_run_stage(i)
	_stage_acc += Time.get_ticks_usec() - tm
	_month_running = false
	if done:
		PerfMonitor.record(STAGE_NAMES[i], Time.get_ticks_usec() - _stage_acc)
		_stage_acc = 0
		_sub = 0
		if not last:
			_month_stage = i + 1
	if _month_stage < 0:
		PerfMonitor.record("month", _month_t0)
		_flush_cmd_queue()


## Conclui na hora o mês pendente (salvar, hash, testes). Sem efeito se chamado de dentro de uma etapa.
func finish_month() -> void:
	if _month_running:
		return
	_deadline_us = 0
	while _month_stage >= 0:
		_step_month_stage()


func month_pending() -> bool:
	return _month_stage >= 0


func _flush_cmd_queue() -> void:
	var q := _cmd_queue
	_cmd_queue = []
	for c in q:
		apply_command(c)


func _simulate_day() -> void:
	var t_day: int = PerfMonitor.begin()
	tick += 1
	var month_rolled := clock.advance_day()
	_advance_training()
	var t_ph: int = PerfMonitor.begin()
	_advance_armies()
	PerfMonitor.record("armies", t_ph)
	if tick % SUPPLY_TICK_DAYS == 0:
		t_ph = PerfMonitor.begin()
		_update_supply()
		PerfMonitor.record("supply", t_ph)
	_advance_fleets()
	t_ph = PerfMonitor.begin()
	_advance_war()
	PerfMonitor.record("war", t_ph)
	t_ph = PerfMonitor.begin()
	_advance_ai()
	PerfMonitor.record("ai", t_ph)
	_advance_events()
	Events.day_changed.emit(clock.to_dict())
	if month_rolled:
		if slice_months and not lockstep:
			_month_stage = 0
			_month_t0 = PerfMonitor.begin()
		else:
			t_ph = PerfMonitor.begin()
			_simulate_month()
			PerfMonitor.record("month", t_ph)
	Events.tick_advanced.emit(tick)
	PerfMonitor.record("day", t_day)


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
@warning_ignore("integer_division")
func _advance_ai() -> void:
	var war_day: bool = tick % 5 == 0
	if tick % 30 == 0:
		ai_heg = AiBrain.hegemon(self)
	# Planejamento da IA espalhado em 30 fatias DIÁRIAS: cada país planeja uma vez a cada 30
	# dias (id % 30), mas poucos por dia, em vez de ~13 países de uma vez a cada 5 dias
	# (isso gerava travadas de ~130 ms no celular). A guerra continua a cada 5 dias.
	var slot: int = tick % 30
	for c in countries:
		if not c.is_alive():
			continue
		if is_human(c.id):
			# Frente automática: exércitos parados do jogador marcham sozinhos em guerra.
			if war_day and c.auto_front and not wars_of(c.id).is_empty():
				_ai_war(c)
				_auto_fleets(c)
			continue
		if c.id % 30 == slot:
			AiBrain.balance_drift(self, c, ai_heg)
			var plan := AiBrain.plan(self, c, ai_heg)
			AiEconomy.review_taxes(self, c)
			_ai_recruit(c, plan)
			_ai_build_ship(c)
			_ai_finance(c)
			_ai_treaties(c)
			_ai_invest(c)
			_ai_declare_war(c, plan)
		if war_day and not wars_of(c.id).is_empty():
			_ai_war(c)
			_auto_fleets(c)


const AI_BUILD_ORDER := ["farm", "mine", "logging", "school", "market", "hospital", "dock", "textile", "carpentry", "university",
	"library", "bank", "irrigation", "sanitation", "academy", "lab", "telegraph", "power_plant", "depot", "paper", "machinery"]
const AI_INVEST_RESERVE_MONTHS := 8
const AI_MAX_METHOD := 1          # a IA só chega à Manufatura (a Mecanizada fica de vantagem do jogador)


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
	_ai_modernize(c, spare)
	var budget: int = clampi(spare / 800, 1, 5) + clampi(spare / 100000, 0, 20)   # potências ricas investem mais por ciclo
	var at_war: bool = not wars_of(c.id).is_empty()
	var order: Array = AiEconomy.build_order(AI_BUILD_ORDER, AiWar.personality_key(self, c), at_war, c.tag)
	var max_depot: int = 2 if at_war else 1
	for level in 3:
		for kind in order:
			for pid in c.province_ids:
				if budget <= 0:
					return
				var p := provinces[int(pid)]
				if p.building_level(kind) != level or not can_build(int(pid), c.id, kind):
					continue
				if kind == "depot" and (level >= max_depot or not _is_border(p)):
					continue   # depósitos só na fronteira (até 2 níveis em guerra)
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
		_ai_spy(c, int(plan["target"]))
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
		# Aviso justo: contra o jogador a IA precisa ter escalado a pressão até o ultimato.
		if pressure_level(c.id, tgt) < PRESSURE_WAR_LEVEL:
			AiBrain.apply_pressure(self, c, plan)
			return
		Events.notice.emit("%s declara guerra para %s." % [c.name, AiBrain.goal_label(str(plan["goal"]))])
	_start_war(c.id, tgt)


## Espionagem da IA contra o alvo da sua pressão (rara; usa o rng, ordem fixa).
func _ai_spy(c: Country, tid: int) -> void:
	if tid < 0 or not can_spy(c.id, tid) or c.treasury < SPY_COST * 3:
		return
	if rng.randi_range(0, 3) != 0:
		return
	var op: int = 0 if countries[tid].tech_level() > c.tech_level() else (1 if rng.randi_range(0, 1) == 0 else 2)
	apply_command({"type": "spy", "target": tid, "op": op, "issuer": c.id})


## Finanças da IA: toma empréstimo quando o caixa fica negativo e amortiza quando sobra dinheiro.
func _ai_finance(c: Country) -> void:
	if c.treasury < -200 and c.debt >= loan_limit(c) and can_print(c.id):
		apply_command({"type": "print_money", "issuer": c.id})
	if c.treasury < 0 and decree_block_reason(c.id, 0) == "":
		apply_command({"type": "decree", "id": 0, "issuer": c.id})
	if c.treasury < 0 and can_take_loan(c.id):
		apply_command({"type": "take_loan", "issuer": c.id})
	elif c.debt > 0 and c.treasury > maxi(600, c.last_expense * 6) + LOAN_STEP:
		apply_command({"type": "repay_loan", "issuer": c.id})


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
	AiWar.think(self, c)


# Fachada para testes headless (que não compilam referências diretas a classes que usam autoloads).
func ai_should_retreat(mine: int, enemy_here: int, ring: int, supply: int, doctrine_key: String = "strategic") -> bool:
	return AiWar.should_retreat(mine, enemy_here, ring, supply, AiWar.doctrine(doctrine_key))


func ai_personality(cid: int) -> String:
	return AiWar.personality_key(self, countries[cid])


func ai_doctrine_value(key: String, field: String) -> int:
	return int(AiWar.doctrine(key)[field])


func ai_target_score(value: int, hops: int, garrison: int, doctrine_key: String = "strategic") -> int:
	return AiWar.target_score(value, hops, garrison, AiWar.doctrine(doctrine_key))


func ai_province_value(pid: int, commander: int) -> int:
	return AiWar.province_value(self, provinces[pid], countries[commander])


func ai_tax_step(tax: int, net: int, treasury: int, expense: int, stability: int, at_war: bool, pers: String) -> int:
	return AiEconomy.tax_step(tax, net, treasury, expense, stability, at_war, pers)


func ai_build_order(base: Array, pers: String, at_war: bool, tag: String) -> Array:
	return AiEconomy.build_order(base, pers, at_war, tag)


func ai_ally_joins(pers: String, op: int, ready: bool, motive: int) -> bool:
	return AiDiplomacy.ally_joins(pers, op, ready, motive)


func ai_coalition_joins(pers: String, balance: bool, op_target: int, op_aggressor: int, ratio: int, ready: bool) -> bool:
	return AiDiplomacy.coalition_joins(pers, balance, op_target, op_aggressor, ratio, ready)


func ai_neighbors(cid: int) -> Array:
	return AiBrain.neighbors(self, countries[cid])


func ai_think(cid: int, doctrine_key: String = "") -> void:
	AiWar.think(self, countries[cid], doctrine_key)


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
				var fx_x: Dictionary = tech_fx(countries[x.owner_id])
				var fx_y: Dictionary = tech_fx(countries[y.owner_id])
				var mod_x: int = clampi((100 + int(fx_y["atk"]) - int(fx_x["def"]) + (100 - x.supply) * 35 / 100) * (100 - DRILL_LOSS_PCT * countries[x.owner_id].drill) / 100, 40, 250)   # perdas de x
				var mod_y: int = clampi((100 + int(fx_x["atk"]) - int(fx_y["def"]) + (100 - y.supply) * 35 / 100) * (100 - DRILL_LOSS_PCT * countries[y.owner_id].drill) / 100, 40, 250)
				var loss_x := (y.regiments * BATTLE_LOSS_PCT * mod_x + 9999) / 10000
				var loss_y := (x.regiments * BATTLE_LOSS_PCT * mod_y + 9999) / 10000
				if x.regiments == y.regiments and loss_x == loss_y:
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


func _simulate_month() -> void:
	_deadline_us = 0
	for i in MONTH_STAGES:
		while not _month_run_stage(i):
			pass
		_sub = 0


## Condições de vitória e derrota do jogador local (determinísticas, inteiras).
func _check_outcome() -> Array:
	var fresh: Array = []
	if lockstep or player_country < 0 or player_country >= countries.size():
		return fresh
	var me := countries[player_country]
	if not me.is_alive():
		if not defeated:
			defeated = true
			fresh.append("defeat")
			Events.outcome_reached.emit("defeat")
		return fresh
	var owned := 0
	for p in provinces:
		if p.owner_id >= 0:
			owned += 1
	if "hegemony" not in victories and owned > 0 and me.province_ids.size() * 100 >= owned * HEGEMONY_PCT:
		victories.append("hegemony")
		fresh.append("hegemony")
		Events.outcome_reached.emit("hegemony")
	if "science" not in victories and me.tech_level() >= MAX_TECH:
		victories.append("science")
		fresh.append("science")
		Events.outcome_reached.emit("science")
	if "great_power" not in victories and clock.year >= GREAT_POWER_YEAR and clock.month == 1:
		var rank := 1
		for c in countries:
			if c.id != me.id and c.is_alive() and c.province_ids.size() > me.province_ids.size():
				rank += 1
		if rank <= 5:
			victories.append("great_power")
			fresh.append("great_power")
			Events.outcome_reached.emit("great_power")
	return fresh


@warning_ignore("integer_division")
func _month_run_stage(i: int) -> bool:
	match i:
		0:
			var food := region_food()
			var pool := food_pool(food)
			famine_regions = 0
			for p in provinces:
				# Crescimento demográfico: +0,1% ao mês (metade, em região com fome).
				var own: int = p.owner_id
				var pfx: Dictionary = tech_fx(countries[own]) if own >= 0 else {}
				var grow: int = p.population / 1000 + p.population * int(p.bld.get("hospital", 0)) / 3500 + p.population * int(pfx.get("pop", 0)) / 10000 + p.population * int(p.bld.get("sanitation", 0)) / 2500
				if own >= 0 and region_famine(food, p, pool):
					grow /= FAMINE_GROWTH_DIV
					famine_regions += 1
				p.population += grow
				# Recuperação de mão de obra.
				var mx := p.manpower_max() * (100 + int(pfx.get("mp", 0))) / 100
				if p.manpower < mx:
					p.manpower = mini(mx, p.manpower + maxi(1, mx * MANPOWER_REGEN_PCT / 100))
		1:
			_migr_init()
		2:
			return _migr_step()
		3:
			_migr_apply()
			_supply_attrition()
		4:
			_trade_init()
		5:
			return _trade_goods_step()
		6:
			_trade_prices()
		7:
			while _sub < countries.size():
				var c := countries[_sub]
				_sub += 1
				if c.is_alive():
					_country_month(c)
				if _over_budget():
					return false
		8:
			while _sub < countries.size():
				var c := countries[_sub]
				_sub += 1
				if c.is_alive():
					_update_politics(c)
				if _over_budget():
					return false
		9:
			# Economia: impostos + comércio - manutenção (províncias, regimentos e navios).
			while _sub < countries.size():
				var c := countries[_sub]
				_sub += 1
				if c.is_alive():
					var e := estimate_monthly(c)
					c.last_income = int(e["income"])
					c.last_expense = int(e["expense"])
					c.treasury += c.last_income - c.last_expense
				if _over_budget():
					return false
			for c in countries:
				if c.overlord >= 0 and c.is_alive():
					var ov := countries[c.overlord]
					if not ov.is_alive() or ov.stability < 15:
						_free_vassal(c.id, false)
						continue
					var tribute: int = maxi(0, c.last_income) * VASSAL_TRIBUTE_PCT / 100
					c.treasury -= tribute
					ov.treasury += tribute
		10:
			_ai_peace()
			_ai_offers()
		11:
			_expire_diplomacy()
			for k in relations.keys():
				var v: int = int(relations[k])
				if at_war(int(k) / 1000, int(k) % 1000):
					continue
				relations[k] = v - signi(v) * mini(absi(v), 2)
			for k in pressure.keys():
				if tick - int(pressure[k]) % 1000000 >= PRESSURE_FORGET_DAYS:
					_pressure_relax(int(k) / 1000, int(k) % 1000)
			for c in countries:
				if c.is_alive() and c.infamy >= INFAMY_BAD:
					for o in countries:
						if o.id != c.id and o.is_alive():
							relations[_pair(c.id, o.id)] = maxi(-100, opinion(c.id, o.id) - 1)
		12:
			if _sub == 0:
				_ev_prepare()
			var defs: Array = _ms.get("ev", [])
			while _sub < countries.size():
				var c := countries[_sub]
				_sub += 1
				_roll_events_for(c, defs)
				if _over_budget():
					return false
		13:
			# Histórico econômico (só apresentação): o jogador todo mês, os demais em rodízio de 6 meses.
			if _sub == 0:
				EconomyManager.record_begin(self, _mt_cache)
			while _sub < countries.size():
				var c := countries[_sub]
				_sub += 1
				if c.is_alive() and (c.id == player_country or c.id % 6 == clock.month % 6):
					EconomyManager.record_country(self, c)
				if _over_budget():
					return false
		14:
			_ms.clear()
			_mt_cache = []
			_check_outcome()
			Events.month_changed.emit(clock.to_dict())
			if month_hook.is_valid():
				month_hook.call()
			for c in countries:
				Events.treasury_changed.emit(c.id)
	return true


## Evolução mensal de um país vivo: alfabetização, tecnologia, pesquisa e esperas.
@warning_ignore("integer_division")
## Propriedade (B7): parte dos lucros das fábricas (após salários e imposto) vira capital privado,
## que financia sozinho +1 nível na fábrica mais lucrativa, sem gastar o tesouro. A política
## econômica define a fração reinvestida.
const PRIVATE_INVEST_PCT := [40, 25, 60]     # mercantilismo, intervencionismo, livre mercado
const PRIVATE_NET_PCT := 60                   # lucro após salários (aprox.), % do lucro operacional
const PRIVATE_CAPITAL_MAX := 200000


@warning_ignore("integer_division")
func _private_invest(c: Country) -> void:
	if c.panic_left > 0:
		return          # crédito congelado durante o pânico
	var gi: int = Laws.group_index("economy")
	var opt: int = int(c.laws[gi]) if gi >= 0 and gi < c.laws.size() else 1
	var pct: int = int(PRIVATE_INVEST_PCT[clampi(opt, 0, PRIVATE_INVEST_PCT.size() - 1)])
	pct = clampi(pct * (100 - (c.interest - LOAN_RATE_PCT) * 20) / 100, 5, 90)    # juros altos freiam o investimento
	var profit := 0
	var best: Province = null
	var best_fp := 0
	for pid in c.province_ids:
		var p := provinces[int(pid)]
		if p.factory == "" or p.factory_level <= 0:
			continue
		var fp: int = p.factory_profit()
		if fp > 0:
			profit += fp
		if p.factory_level < Province.MAX_BUILDING and fp > best_fp:
			best_fp = fp
			best = p
	profit = profit * PRIVATE_NET_PCT / 100 * (100 - c.tax_pct) / 100
	c.private_capital = mini(PRIVATE_CAPITAL_MAX, c.private_capital + profit * pct / 100)
	if best != null:
		var cost: int = build_total_cost(best, best.factory)
		if c.private_capital >= cost:
			c.private_capital -= cost
			best.factory_level += 1
			if c.id == player_country:
				Events.notice.emit("Capitalistas ampliaram a fábrica de %s (nível %d)." % [best.name, best.factory_level])


func _country_month(c: Country) -> void:
	_election_step(c)
	_panic_step(c)
	_private_invest(c)
	c.inflation = maxi(0, c.inflation - (2 if c.interest >= 3 else 1))
	var edu := edu_levels(c)
	var lmod := law_mods(c)
	var lit_base: int = 100 + (edu.x + 2 * edu.y + bld_total(c, "library")) * 400 / maxi(1, c.province_ids.size())
	c.lit_acc += maxi(0, lit_base * (100 + int(lmod["lit"]) + int(tech_fx(c)["lit"]) + Government.eff(c.budget_code, 0) + Government.decree_field(c.decree, "lit")) / 100)
	c.literacy = mini(LITERACY_MAX, c.literacy + c.lit_acc / 100)
	c.lit_acc = c.lit_acc % 100
	c.tech_pts = mini(TECH_BANK_MAX, c.tech_pts + tech_gain(c))
	_research_step(c)
	c.spy_cd = maxi(0, c.spy_cd - 1)
	c.decree_cd = maxi(0, c.decree_cd - 1)
	if c.decree >= 0:
		c.decree_left -= 1
		if c.decree_left <= 0:
			c.decree = -1
			c.decree_left = 0
			c.decree_cd = Government.DECREE_COOLDOWN
	c.infamy = maxi(0, c.infamy - INFAMY_DECAY)
	for gi in c.law_cd.size():
		if int(c.law_cd[gi]) > 0:
			c.law_cd[gi] = int(c.law_cd[gi]) - 1


# ---------------------------------------------------------------------------
# Eventos (data/events.json)
# ---------------------------------------------------------------------------
const REAL_ECONOMY_PATH := "res://data/real_economy_1836.json"
var usd_per_gold: float = 0.0     # milhões de US$ de 2011 (PPP) por unidade de valor do jogo (calibração de 1836)


## Calibra o valor produzido por província para que a participação de cada país no PIB mundial
## siga o PIB per capita histórico de 1836 (Maddison). A população já é a histórica. Mantém o
## total mundial: só redistribui entre países. Estático e determinístico.
## Guerras já em curso em 1/1/1836 (data/history_1836.json: "_start_wars" = [[atacante, alvo], ...]).
func _apply_start_wars() -> void:
	var tag_id: Dictionary = {}
	for c in countries:
		tag_id[c.tag] = c.id
	for pair in history.get("_start_wars", []):
		if pair.size() != 2 or not tag_id.has(str(pair[0])) or not tag_id.has(str(pair[1])):
			continue
		var a: int = tag_id[str(pair[0])]
		var b: int = tag_id[str(pair[1])]
		if a != b and not at_war(a, b):
			_start_war(a, b)
			var wi := _war_index(a, b)
			if wi >= 0:
				wars[wi]["days"] = 120   # já dura há meses: a paz pode ser negociada


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


func _event_ok(d: Dictionary, c: Country, ctx: Dictionary = {}) -> bool:
	if clock.year < int(d.get("min_year", 0)) or clock.year > int(d.get("max_year", 9999)):
		return false
	if d.has("tags"):
		var tags: Array = d["tags"]
		if not tags.has(c.tag):
			return false
	if bool(d.get("once", false)) and fired_events.has("%d|%s" % [c.id, str(d["id"])]):
		return false
	if d.has("date"):
		var dt: Array = d["date"]
		if clock.year != int(dt[0]) or clock.month != int(dt[1]):
			return false
	if c.province_ids.size() < int(d.get("min_provinces", 0)):
		return false
	if c.treasury > int(d.get("max_treasury", 1000000000)) or c.treasury < int(d.get("min_treasury", -1000000000)):
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
	if need_regs > 0:
		if not ctx.has("regs"):
			ctx["regs"] = regiments_of(c.id)
		if int(ctx["regs"]) < need_regs:
			return false
	if d.has("min_ideo"):
		var need: Dictionary = d["min_ideo"]
		if not ctx.has("pol"):
			ctx["pol"] = politics_of(c)
		var pol: Dictionary = ctx["pol"]
		for k in need.keys():
			var idx := IDEOLOGIES.find(str(k))
			if idx < 0 or int(pol["ideo"][idx]) < int(need[k]):
				return false
	return true


## Eventos possíveis neste mês (filtro só por data, igual para todos os países).
func _ev_prepare() -> void:
	var act: Array = []
	for d in event_defs:
		if clock.year < int(d.get("min_year", 0)) or clock.year > int(d.get("max_year", 9999)):
			continue
		if d.has("date"):
			var dt: Array = d["date"]
			if clock.year != int(dt[0]) or clock.month != int(dt[1]):
				continue
		act.append(d)
	_ms["ev"] = act


## Sorteio mensal. Usa só `rng` e itera em ordem fixa -> igual em todos os pares.
func _roll_events() -> void:
	_ev_prepare()
	for c in countries:
		_roll_events_for(c, _ms["ev"])


func _roll_events_for(c: Country, defs: Array) -> void:
	if not c.is_alive() or not pending_event_for(c.id).is_empty():
		return
	var ectx: Dictionary = {}   # politics_of/regiments_of caros: calculados no máximo uma vez por país
	for d in defs:
		if not _event_ok(d, c, ectx):
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


## Mercados regionais (B4): alimento (grãos, peixe, gado) de cada região histórica de cada país.
## Retorna {"dono|região": [oferta, demanda]}. Derivado da produção e da população, não é estado.
const FOOD := ["grain", "fish", "livestock"]
const FAMINE_PCT := 50           # abaixo disso (oferta/demanda) a região passa fome
const FAMINE_GROWTH_DIV := 2     # fome corta o crescimento populacional pela metade


@warning_ignore("integer_division")
func region_food() -> Dictionary:
	var out: Dictionary = {}
	var dem_unit := 0
	for g in FOOD:
		dem_unit += int(market_dem.get(g, 0))
	for p in provinces:
		if p.owner_id < 0:
			continue
		var key := "%d|%s" % [p.owner_id, p.region]
		var row: Array = out.get(key, [0, 0])
		if FOOD.has(p.resource_type):
			row[0] += p.units()
		row[1] += dem_unit * p.population / maxi(1, market_pop0)
		out[key] = row
	return out


## Rede de transporte (B11): % da sobra de alimento do país que chega a uma região em falta.
## Estradas dão 25%; cada nível de ferrovia por província soma 50 pontos (máx. 90%).
@warning_ignore("integer_division")
func transport_pct(c: Country) -> int:
	var n := maxi(1, c.province_ids.size())
	var rails := 0
	for pid in c.province_ids:
		rails += int(provinces[pid].bld.get("railway", 0))
	return clampi(25 + rails * 50 / n, 25, 90)


## Sobra de alimento por dono ({dono: unidades}), somando as regiões com excedente.
func food_pool(food: Dictionary) -> Dictionary:
	var pool: Dictionary = {}
	for k in food.keys():
		var parts: PackedStringArray = str(k).split("|")
		var r: Array = food[k]
		var o := int(parts[0])
		pool[o] = int(pool.get(o, 0)) + maxi(0, int(r[0]) - int(r[1]))
	return pool


## Oferta efetiva de alimento (% da demanda) de uma região: produção local + parte da sobra do
## país, limitada pela rede de transporte. Sem `pool`, só a produção local.
@warning_ignore("integer_division")
func region_ratio(food: Dictionary, owner: int, region: String, pool: Dictionary = {}) -> int:
	var row: Array = food.get("%d|%s" % [owner, region], [0, 0])
	if int(row[1]) <= 0:
		return 100
	var supply: int = int(row[0])
	if not pool.is_empty() and owner >= 0 and owner < countries.size():
		supply += maxi(0, int(pool.get(owner, 0)) - maxi(0, int(row[0]) - int(row[1]))) * transport_pct(countries[owner]) / 100
	return supply * 100 / int(row[1])


func region_famine(food: Dictionary, p: Province, pool: Dictionary = {}) -> bool:
	return region_ratio(food, p.owner_id, p.region, pool) < FAMINE_PCT


## Pops (B1): população de cada província por profissão/classe [camponeses, operários, aristocratas,
## burguesia, funcionários, soldados], em pessoas. Derivado (não é estado): reparte os totais
## nacionais de `politics_of` entre as províncias por pesos (empregos, mercados, escolas, quartéis).
## Soma de cada província = população da província. Retorna {pid: [6 ints]}.
@warning_ignore("integer_division")
func country_pops(c: Country) -> Dictionary:
	var out: Dictionary = {}
	if c.province_ids.is_empty():
		return out
	var pop_nat := maxi(1, population_of(c))
	var sh: Array = politics_of(c)["share"]
	var w: Array = []        # pesos por classe 1..5 e província
	var wsum := [0, 0, 0, 0, 0, 0]
	for pid in c.province_ids:
		var p := provinces[pid]
		var jobs := 0
		for kind in Province.JOBS_PER_LEVEL.keys():
			var lv := p.building_level(str(kind))
			if lv > 0:
				var jp: int = p.method_pct("jobs") if Province.FACTORIES.has(str(kind)) else (p.rmethod_pct("jobs") if str(kind) == p.primary_extractor() else 100)
				jobs += int(Province.JOBS_PER_LEVEL[kind]) * lv * jp / 100
		var wt := [0, jobs, maxi(1, p.population / 1000),
			1 + int(p.bld.get("market", 0)) + int(p.bld.get("bank", 0)) + p.factory_level,
			1 + int(p.bld.get("school", 0)) + 2 * int(p.bld.get("university", 0)) + (4 if pid == c.capital else 0),
			1 + p.barracks]
		w.append(wt)
		for i in range(1, 6):
			wsum[i] += int(wt[i])
	var idx := 0
	for pid in c.province_ids:
		var p := provinces[pid]
		var wt: Array = w[idx]
		idx += 1
		var v := [0, 0, 0, 0, 0, 0]
		for i in range(1, 6):
			var total: int = pop_nat * int(sh[i]) / 1000
			v[i] = total * int(wt[i]) / maxi(1, int(wsum[i])) if int(wsum[i]) > 0 else total / c.province_ids.size()
		var remaining: int = p.population
		for i in [5, 4, 3, 2, 1]:
			v[i] = mini(int(v[i]), remaining)
			remaining -= int(v[i])
		v[0] = remaining
		out[pid] = v
	return out


## Renda por classe (B2): quanto cada classe recebe por mês, por mil habitantes e relativa à média
## nacional (100 = média). Derivado da economia; não é estado. Retorna {pool, people, pc, rel, gini}.
@warning_ignore("integer_division")
func class_income(c: Country) -> Dictionary:
	var e := estimate_monthly(c)
	var people := [0, 0, 0, 0, 0, 0]
	for v in country_pops(c).values():
		for i in 6:
			people[i] += int(v[i])
	var keep: int = 100 - c.tax_pct
	var prod: int = int(e["production"])
	var pool := [0, 0, 0, 0, 0, 0]
	pool[0] = prod * 55 / 100 * keep / 100
	pool[2] = prod * 25 / 100 * keep / 100
	pool[1] = int(e["factory_wages"]) + prod * 20 / 100 * keep / 100
	pool[3] = maxi(0, int(e["industry"]) - int(e["factory_wages"]) - int(e["factory_tax"])) + int(e["trade"]) / 2
	pool[4] = int(e["upkeep_edu"]) + int(e["upkeep_prov"]) + int(e["upkeep_infra"])
	pool[5] = int(e["upkeep_army"]) * 6 / 10 + int(e["upkeep_barracks"])
	var pc := [0, 0, 0, 0, 0, 0]
	var tot_pool := 0
	var tot_people := 0
	for i in 6:
		pc[i] = int(pool[i]) * 1000 / maxi(1, int(people[i]))
		tot_pool += int(pool[i])
		tot_people += int(people[i])
	var avg: int = maxi(1, tot_pool * 1000 / maxi(1, tot_people))
	var rel := [0, 0, 0, 0, 0, 0]
	for i in 6:
		rel[i] = int(pc[i]) * 100 / avg
	# Gini (0..1000) pelos 6 grupos, ordenados por renda per capita
	var order := [0, 1, 2, 3, 4, 5]
	order.sort_custom(func(x, y): return int(pc[x]) < int(pc[y]) or (int(pc[x]) == int(pc[y]) and x < y))
	var cum_p := 0
	var cum_i := 0
	var area2 := 0       # 2 x área sob a curva de Lorenz, em milésimos
	for k in order:
		var dp: int = int(people[k]) * 1000 / maxi(1, tot_people)
		var di: int = int(pool[k]) * 1000 / maxi(1, tot_pool)
		area2 += dp * (2 * cum_i + di) / 1000
		cum_p += dp
		cum_i += di
	var gini: int = clampi(1000 - area2, 0, 1000)
	return {"pool": pool, "people": people, "pc": pc, "rel": rel, "gini": gini}


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
	var gsh: Array = Government.sat_shift(c.budget_code, c.decree)
	var cterm: Array = []
	for ci in 6:
		cterm.append(Consumption.comfort_term(lp, ci))
	for ci in [0, 1, 4]:
		cterm[ci] = int(cterm[ci]) - c.inflation / 2          # renda fixa perde com a inflação
		cterm[ci] = int(cterm[ci]) - c.excise / 2             # imposto de consumo pesa nos pobres
	var fit: Array = Laws.fit_all(c.laws)
	var legit := 0
	for j in 5:
		legit += maxi(0, int(ideo[j]) - LEGIT_FLOOR) * int(fit[j])
	legit = clampi(legit / LEGIT_DIV, -LEGIT_MAX, LEGIT_MAX)
	var lmp := law_mods(c)
	var hist_bias: int = (int(history.get(c.tag, {}).get("stab", 2)) - 2) * 2
	var prof_sat: Dictionary = history.get(c.tag, {}).get("profile", {}).get("sat", {})
	for i in 6:
		tg[i] = clampi(tg[i] + int(lmp["stab"]) + int(tech_fx(c)["stab"]) + int(lmp["sat"][i]) + legit + int(gsh[i]) + int(cterm[i]) + hist_bias + int(prof_sat.get(str(i), 0)), 0, 100)

	return {"share": sh, "target": tg, "power": pw, "power_total": tot_pw, "ideo": ideo,
		"fit": fit, "legit": legit, "stability": ssum / maxi(1, wsum)}


## Reformas que a corrente dominante exige: [{group, option, gain}] das 3 maiores melhorias de afinidade.
func law_demands(c: Country, pol: Dictionary) -> Array:
	var ideo: Array = pol["ideo"]
	var best := 0
	for j in 5:
		if int(ideo[j]) > int(ideo[best]):
			best = j
	var out: Array = []
	for gi in Laws.group_count():
		var cur: int = int(c.laws[gi])
		var bo := cur
		var bl: int = Laws.lean(gi, cur, best)
		for oi in (Laws.group(gi)["opts"] as Array).size():
			if Laws.lean(gi, oi, best) > bl:
				bl = Laws.lean(gi, oi, best)
				bo = oi
		if bo != cur:
			out.append({"group": gi, "option": bo, "gain": bl - Laws.lean(gi, cur, best), "ideo": best})
	out.sort_custom(func(x, y): return int(x["gain"]) > int(y["gain"]) or (int(x["gain"]) == int(y["gain"]) and int(x["group"]) < int(y["group"])))
	return out.slice(0, 3)


## Estabilidade a partir de uma previsão já calculada (pesos e poder não dependem de `sat`).
## Idêntica ao campo "stability" de politics_of com a satisfação atual, sem refazer a economia.
@warning_ignore("integer_division")
func _stability_from(c: Country, pol: Dictionary) -> int:
	var sh: Array = pol["share"]
	var pw: Array = pol["power"]
	var wsum := 0
	var ssum := 0
	for i in 6:
		var w: int = int(sh[i]) + int(pw[i]) / 50
		wsum += w
		ssum += int(c.sat[i]) * w
	return ssum / maxi(1, wsum)


## Atualização mensal: a satisfação anda até 2 pontos rumo ao alvo; instabilidade gera revoltas.
@warning_ignore("integer_division")
func _update_politics(c: Country) -> void:
	var pol := politics_of(c)
	for i in 6:
		c.sat[i] = int(c.sat[i]) + clampi(int(pol["target"][i]) - int(c.sat[i]), -2, 2)
	c.stability = _stability_from(c, pol)
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


## Soma dos níveis de um tipo de construção em todas as províncias do país.
func bld_total(c: Country, kind: String) -> int:
	var n := 0
	for pid in c.province_ids:
		n += int(provinces[pid].bld.get(kind, 0))
	return n


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
	return 4 * maxi(0, mini(c.tech_level(), MAX_TECH) - 3) + int(tech_fx(c)["tax"])


func tech_army_discount(c: Country) -> int:
	return mini(70, 10 * maxi(0, mini(c.tech_level(), MAX_TECH) - 4) + int(tech_fx(c)["army"]))


## Efeitos acumulados das tecnologias dominadas (cache por país).
func tech_fx(c: Country) -> Dictionary:
	if c.fx_dirty:
		var f: Dictionary = {}
		for k in Techs.FX_KEYS:
			f[k] = 0
		for tid in c.techs:
			var fx: Dictionary = Techs.ALL[int(tid)]["fx"]
			for k in fx.keys():
				f[k] = int(f[k]) + int(fx[k])
		c.fx = f
		c.fx_dirty = false
	return c.fx


## Dá ao país exatamente as eras 1..lvl completas (e zera banco e pesquisa em curso).
func _set_tech_level(c: Country, lvl: int) -> void:
	c.techs = []
	c.researching = -1
	c.tech_pts = 0
	c.fx_dirty = true
	for tid in range(mini(lvl, Techs.MAX_ERA) * Techs.PER_ERA):
		c.techs.append(tid)


## Escolha determinística da IA: a tecnologia disponível de maior pontuação (empate: menor id).
func _ai_pick_tech(c: Country) -> int:
	var war: bool = not wars_of(c.id).is_empty()
	var low_lit: bool = c.literacy < 300
	var best: int = -1
	var best_s: int = -1
	for tid in Techs.ALL.size():
		if not Techs.available(c, tid):
			continue
		var sc: int = Techs.score(tid, war, low_lit)
		if sc > best_s:
			best_s = sc
			best = tid
	return best


## Passo mensal da pesquisa: gasta o banco na tecnologia em estudo e, concluída, aplica seus efeitos.
func _research_step(c: Country) -> void:
	if c.techs.size() >= Techs.ALL.size():
		c.researching = -1
		return
	if c.researching >= 0 and not Techs.available(c, c.researching):
		c.researching = -1
	if c.researching < 0 and not is_human(c.id):
		c.researching = _ai_pick_tech(c)
	if c.researching < 0:
		return
	var cost: int = Techs.cost(c.researching)
	if c.tech_pts < cost:
		return
	c.tech_pts -= cost
	var done: int = c.researching
	c.techs.append(done)
	c.techs.sort()
	c.fx_dirty = true
	c.researching = -1
	if not is_human(c.id):
		c.researching = _ai_pick_tech(c)
	if c.id == player_country:
		Events.notice.emit("Pesquisa concluída: %s" % str(Techs.ALL[done]["name"]))


## Pontos de tecnologia por mês SEM financiamento: base + alfabetização + escolas + universidades + leis.
func tech_gain_base(c: Country) -> int:
	var edu := edu_levels(c)
	var lmod := law_mods(c)
	return maxi(0, (6 + c.literacy / 50 + 3 * edu.x + 10 * edu.y + 6 * bld_total(c, "lab") + int(lmod["tech"])) * (100 + int(tech_fx(c)["tech"])) / 100)


## Pontos por mês com o financiamento atual (cada 20% da renda dobram a pesquisa).
func tech_gain(c: Country) -> int:
	var b := tech_gain_base(c)
	return b + b * c.research_pct / 20 + b * SCIENCE_ALLY_PCT * science_allies(c) / 100


const INFRA_UPKEEP_KINDS := ["hospital", "market", "dock", "library", "sanitation", "academy", "arsenal", "lab", "bank", "shipyard", "telegraph", "depot"]


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
		for ik in INFRA_UPKEEP_KINDS:
			var lv: int = int(p.bld.get(ik, 0))
			if lv > 0:
				up_infra += lv * int(Province.GOV_UPKEEP[ik])
		var pprod: int = p.production()
		var base_tax: int = pprod * c.tax_pct / 100
		tax += Province.FLAT_TAX + base_tax * (100 + 8 * int(p.bld.get("market", 0)) + 6 * int(p.bld.get("bank", 0))) / 100
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
		prod += pprod
	var lm := law_mods(c)
	var tf: Dictionary = tech_fx(c)
	tax = tax * (100 + int(tf["prod"])) / 100       # tecnologias de produção
	prod = prod * (100 + int(tf["prod"])) / 100
	industry_state = industry_state * (100 + int(tf["ind"])) / 100
	industry = industry * (100 + int(tf["ind"])) / 100
	tax = tax * (1000 + c.literacy / 5) / 1000      # alfabetização: até ~+19% de imposto
	tax = tax * (100 + int(lm["tax"]) + tech_tax_bonus(c)) / 100
	if c.stability < UNREST_TAX_STABILITY:
		tax = tax * (70 + c.stability * 3 / 4) / 100       # instabilidade reduz a arrecadação
	tax = tax * (100 + Government.eff(c.budget_code, 2) + Government.decree_field(c.decree, "tax")) / 100
	tax = tax * (100 - c.inflation / 2) / 100                  # inflação corrói a arrecadação real
	var evasion: int = tax_evasion(c)
	tax = tax * (100 - evasion) / 100                          # evasão fiscal
	if c.panic_left > 0:
		tax = tax * (100 - PANIC_TAX_PCT) / 100                # pânico financeiro
	industry_state = industry_state * (100 + Government.decree_field(c.decree, "ind")) / 100
	var regs := regiments_of(c.id)
	var up_prov: int = c.province_ids.size() * EXPENSE_PER_PROVINCE
	var arsenal_pct: int = mini(20, 2 * bld_total(c, "arsenal"))
	var up_army: int = regs * REGIMENT_UPKEEP * (100 + int(lm["army"])) / 100 * (100 - mini(80, tech_army_discount(c) + arsenal_pct)) / 100
	up_army = up_army * (100 + DRILL_UPKEEP_PCT * c.drill) / 100
	var up_navy: int = c.ships * SHIP_UPKEEP * (100 - mini(50, 10 * bld_total(c, "shipyard"))) / 100
	var edu := edu_levels(c)
	var up_edu: int = edu.x * SCHOOL_UPKEEP + edu.y * UNIVERSITY_UPKEEP
	var trade: int = int(trade_bonus[c.id]) if c.id < trade_bonus.size() else 0
	trade = trade * (100 + treaty_trade_pct(c.id) + int(lm["trade"]) + int(tf["trade"]) + mini(30, 5 * bld_total(c, "telegraph")) + port_trade_pct(c)) / 100
	var bc: int = c.budget_code
	var dexp: int = 100 + Government.decree_field(c.decree, "exp")
	up_prov = up_prov * Government.pct(bc, 2) / 100 * dexp / 100
	up_army = up_army * Government.pct(bc, 1) / 100 * dexp / 100
	up_edu = up_edu * Government.pct(bc, 0) / 100 * dexp / 100
	var up_welfare: int = c.province_ids.size() * Government.WELFARE_PER_PROVINCE * Government.pct(bc, 3) / 100
	var excise_rev: int = prod * EXCISE_BASE_PCT / 100 * c.excise / 100 * (100 - evasion) / 100
	excise_rev = excise_rev * (100 - c.inflation / 2) / 100
	var up_research: int = maxi(0, tax + excise_rev + industry_state + trade) * c.research_pct / 100
	var up_debt: int = c.debt * c.interest / 100
	return {
		"upkeep_research": up_research,
		"income": tax + excise_rev + industry_state + trade, "tax": tax, "excise": excise_rev, "evasion": evasion, "industry": industry, "trade": trade,
		"industry_state": industry_state, "factory_revenue": f_rev, "factory_inputs": f_inputs,
		"factory_wages": f_wages, "factory_tax": f_tax, "upkeep_barracks": up_barracks,
		"expense": up_prov + up_army + up_navy + up_edu + up_barracks + up_infra + up_research + up_debt + up_welfare, "upkeep_welfare": up_welfare, "upkeep_debt": up_debt, "upkeep_infra": up_infra, "upkeep_edu": up_edu, "regiments": regs,
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
				var jp: int = p.method_pct("jobs") if Province.FACTORIES.has(str(kind)) else (p.rmethod_pct("jobs") if str(kind) == p.primary_extractor() else 100)
				jobs += int(Province.JOBS_PER_LEVEL[kind]) * lv * jp / 100
	jobs *= JOB_SCALE
	return SURPLUS_LABOR_PCT * maxi(0, surplus - jobs) / surplus


# ---------------------------------------------------------------------------
# Logística e abastecimento (inspirado no módulo Logistics & Supply V1, em inteiros)
# ---------------------------------------------------------------------------
const SUPPLY_TICK_DAYS := 5
const SUPPLY_BASE_RANGE := 6000      # alcance da capital (custo de marcha)
const SUPPLY_DEPOT_RANGE := 2000     # por nível de depósito (base 4000 do depósito)
const SUPPLY_BASE_CAP := 12          # regimentos que a capital abastece
const SUPPLY_DEPOT_CAP := 8          # por nível de depósito
const SUPPLY_LIMIT := 15000          # raio máximo da busca


func supply_label(ratio: int) -> String:
	if ratio >= 75:
		return "normal"
	if ratio >= 35:
		return "baixo"
	return "crítico"


## Abastecimento (0..100) a um custo de rota `cost` de uma fonte com alcance `rng_`.
@warning_ignore("integer_division")
func _supply_ratio(cost: int, rng_: int) -> int:
	if rng_ <= 0:
		return 0
	var pct: int = cost * 100 / rng_
	if pct <= 60:
		return 100
	if pct <= 100:
		return 100 - (pct - 60) * 50 / 40
	if pct <= 150:
		return 150 - pct
	return 0


## Alcance de abastecimento de uma província para o dono (0 = não é fonte): capital e depósitos.
func _supply_range_at(pid: int, owner: int) -> int:
	var p := provinces[pid]
	if p.owner_id != owner:
		return 0
	var best: int = 0
	if countries[owner].capital == pid:
		best = SUPPLY_BASE_RANGE
	var dl: int = int(p.bld.get("depot", 0))
	if dl > 0:
		best = maxi(best, 4000 + SUPPLY_DEPOT_RANGE * dl)
	return best


@warning_ignore("integer_division")
func _supply_cap_at(pid: int) -> int:
	var p := provinces[pid]
	var cap: int = SUPPLY_DEPOT_CAP * int(p.bld.get("depot", 0))
	if countries[p.owner_id].capital == pid:
		# Cresce com o tamanho do país: o Japão (15 províncias) começa com 16 regimentos e a capital
		# fixa em 12 fazia o próprio exército inicial passar fome em casa.
		cap += SUPPLY_BASE_CAP + countries[p.owner_id].province_ids.size() / 2
	return cap


## Custo de a linha de suprimento entrar na província q: metade em terra própria (menos com
## ferrovia), o dobro em terra alheia.
@warning_ignore("integer_division")
func _supply_step_cost(q: Province, owner: int) -> int:
	var mult: int = int(Province.MOVE_MULT.get(q.terrain, 1000))
	if q.owner_id == owner:
		return maxi(150, mult / 2 * (100 - mini(55, 8 * int(q.bld.get("railway", 0)))) / 100)
	return mult * 2


func _heap_push(h: Array, v: int) -> void:
	h.append(v)
	var i: int = h.size() - 1
	while i > 0:
		var parent: int = (i - 1) / 2
		if int(h[parent]) <= v:
			break
		h[i] = h[parent]
		i = parent
	h[i] = v


func _heap_pop(h: Array) -> int:
	var top: int = int(h[0])
	var last: int = int(h.pop_back())
	var n: int = h.size()
	if n > 0:
		var i: int = 0
		while true:
			var l: int = 2 * i + 1
			if l >= n:
				break
			var r: int = l + 1
			var m: int = r if (r < n and int(h[r]) < int(h[l])) else l
			if int(h[m]) >= last:
				break
			h[i] = h[m]
			i = m
		h[i] = last
	return top


## Fontes de abastecimento de um dono: {província: alcance} (capital e depósitos).
func _supply_sources(owner: int) -> Dictionary:
	var out: Dictionary = {}
	for pid in countries[owner].province_ids:
		var r: int = _supply_range_at(int(pid), owner)
		if r > 0:
			out[int(pid)] = r
	return out


## Melhor fonte para um exército que está em `start`: Dijkstra com heap saindo dele, limitado a 1,5x
## o maior alcance e encerrado assim que acha uma fonte com abastecimento pleno (100%).
## Devolve [razão 0..100, província da fonte ou -1]. Desempate: primeira fonte no menor custo/id.
@warning_ignore("integer_division")
func _supply_route(start: int, owner: int, srcs: Dictionary) -> Array:
	var maxr: int = 0
	for r in srcs.values():
		maxr = maxi(maxr, int(r))
	var limit: int = mini(SUPPLY_LIMIT, maxr * 3 / 2)
	var best_ratio: int = 0
	var best_src: int = -1
	var dist: Dictionary = {start: 0}
	var heap: Array = []
	_heap_push(heap, start)
	var done: Dictionary = {}
	while not heap.is_empty():
		var top: int = _heap_pop(heap)
		var cur: int = top & 0xFFFF
		var cd: int = top >> 16
		if done.has(cur):
			continue
		done[cur] = true
		if srcs.has(cur):
			var r2: int = _supply_ratio(cd, int(srcs[cur]))
			if r2 > best_ratio:
				best_ratio = r2
				best_src = cur
				if r2 >= 100:
					break
		for qi in provinces[cur].neighbors:
			var qn: int = int(qi)
			var nd: int = cd + _supply_step_cost(provinces[qn], owner)
			if nd <= limit and nd < int(dist.get(qn, 1 << 30)):
				dist[qn] = nd
				_heap_push(heap, (nd << 16) | qn)
		for qi in provinces[cur].sea_links:
			var qs: int = int(qi)
			var nd2: int = cd + 2 * _supply_step_cost(provinces[qs], owner)
			if nd2 <= limit and nd2 < int(dist.get(qs, 1 << 30)):
				dist[qs] = nd2
				_heap_push(heap, (nd2 << 16) | qs)
	return [best_ratio, best_src]


## Recalcula o abastecimento de todos os exércitos (a cada 5 dias). Exércitos que dividem a mesma
## fonte repartem a capacidade dela. Resultados por (dono, província) são reaproveitados.
@warning_ignore("integer_division")
func _update_supply() -> void:
	var rows: Array = []
	var demand: Dictionary = {}
	var srcs_by_owner: Dictionary = {}
	var cache: Dictionary = {}
	var ids: Array = armies.keys()
	ids.sort()
	for id in ids:
		var a: Army = armies[id]
		if not srcs_by_owner.has(a.owner_id):
			srcs_by_owner[a.owner_id] = _supply_sources(a.owner_id)
		var key: int = a.owner_id * 65536 + a.province_id
		if not cache.has(key):
			cache[key] = _supply_route(a.province_id, a.owner_id, srcs_by_owner[a.owner_id])
		var hit: Array = cache[key]
		rows.append([a, int(hit[1]), int(hit[0])])
		if int(hit[1]) >= 0:
			demand[int(hit[1])] = int(demand.get(int(hit[1]), 0)) + a.regiments
	for row in rows:
		var ar: Army = row[0]
		var ratio: int = int(row[2])
		var src: int = int(row[1])
		if src >= 0:
			var dem: int = int(demand[src])
			var cp: int = _supply_cap_at(src)
			if dem > cp and dem > 0:
				ratio = ratio * cp / dem
		var changed: bool = ar.supply != ratio
		ar.supply = clampi(ratio, 0, 100)
		if changed:
			Events.army_changed.emit(ar.id)


## Desgaste mensal por falta de suprimentos: abaixo de 75% o exército perde regimentos.
@warning_ignore("integer_division")
func _supply_attrition() -> void:
	for id in armies.keys():
		if not armies.has(id):
			continue
		var a: Army = armies[id]
		if a.supply >= 75:
			continue
		var pct: int = (75 - a.supply) / 5
		var loss: int = a.regiments * pct / 100
		if rng.randi_range(0, 99) < (a.regiments * pct) % 100:
			loss += 1
		if loss <= 0:
			continue
		a.regiments = maxi(0, a.regiments - loss)
		if a.owner_id == player_country:
			Events.notice.emit("Exército #%d sem suprimentos (%d%%): perdeu %d regimento(s)." % [a.id, a.supply, loss])
		if a.regiments <= 0:
			armies.erase(id)
			Events.army_removed.emit(id)
		else:
			Events.army_changed.emit(id)


func _is_border(p: Province) -> bool:
	for qi in p.neighbors:
		var o: int = provinces[int(qi)].owner_id
		if o >= 0 and o != p.owner_id:
			return true
	return false


## Densidade média mundial (habitantes por província com dono).
func world_density() -> int:
	var pop: int = 0
	var n: int = 0
	for p in provinces:
		if p.owner_id >= 0:
			pop += p.population
			n += 1
	return pop / maxi(1, n)


## Atratividade de um país para migrantes. Chaves: total e cada parcela (para a interface).
@warning_ignore("integer_division")
func attractiveness(c: Country, avg_density: int) -> Dictionary:
	var unemp: int = unemployment_pct(c)
	var jobs_b: int = (20 - unemp) * 3
	var stab_b: int = (c.stability - 50) / 2
	var lit_b: int = mini(30, c.literacy / 25)
	var dens: int = population_of(c) / maxi(1, c.province_ids.size())
	var front_b: int = 20 if dens * 100 < avg_density * 60 else 0
	var war_b: int = -30 if not wars_of(c.id).is_empty() else 0
	var tech_b: int = int(tech_fx(c)["mig"])
	var total: int = maxi(40, 100 + jobs_b + stab_b + lit_b + front_b + war_b + tech_b)
	return {"total": total, "jobs": jobs_b, "stab": stab_b, "lit": lit_b, "front": front_b, "war": war_b, "tech": tech_b}


## Migração mensal (determinística, sem rng; a população total se conserva):
## 1) interna, de províncias menos para mais desenvolvidas; 2) entre países vizinhos (terra e
## estreitos), rumo ao mais atrativo, conforme a política de imigração do destino; 3) transoceânica,
## de portos para os 3 países mais atrativos que aceitam imigrantes.
@warning_ignore("integer_division")
func _migr_init() -> void:
	var avg: int = world_density()
	var att: Array = []
	for c in countries:
		c.migr_in = 0
		c.migr_out = 0
		att.append(int(attractiveness(c, avg)["total"]) if c.is_alive() else 0)
	var delta: Array = []
	delta.resize(provinces.size())
	delta.fill(0)
	var port_of: Dictionary = {}     # país -> província portuária menos povoada (assentamento)
	for p in provinces:
		if p.owner_id >= 0 and p.port >= 0:
			if not port_of.has(p.owner_id) or p.population < provinces[int(port_of[p.owner_id])].population:
				port_of[p.owner_id] = p.id
	# destinos transoceânicos: os 3 países mais atrativos que aceitam imigrantes e têm porto
	var dests: Array = []
	for _n in 3:
		var best: int = -1
		for c in countries:
			if c.is_alive() and c.immigration > 0 and port_of.has(c.id) and not dests.has(c.id):
				if best < 0 or att[c.id] > att[best]:
					best = c.id
		if best >= 0:
			dests.append(best)
	_ms["att"] = att
	_ms["delta"] = delta
	_ms["port_of"] = port_of
	_ms["dests"] = dests


func _migr_step() -> bool:
	var att: Array = _ms["att"]
	var delta: Array = _ms["delta"]
	var port_of: Dictionary = _ms["port_of"]
	var dests: Array = _ms["dests"]
	while _sub < provinces.size():
		var p: Province = provinces[_sub]
		_sub += 1
		var a: int = p.owner_id
		if a < 0 or p.population < 20000:
			continue
		var cap: int = p.population / 50
		var sent: int = 0
		var links: Array = []
		for q in p.neighbors:
			links.append(q)
		for q in p.sea_links:
			links.append(q)
		for qi in links:
			var q: Province = provinces[int(qi)]
			var b: int = q.owner_id
			if b < 0 or sent >= cap:
				continue
			var m: int = 0
			if a == b:
				var diff: int = q.pull() - p.pull()
				if diff > 15:
					m = p.population * diff / 100000
			else:
				var gap: int = int(att[b]) - int(att[a])
				if gap > 10 and not at_war(a, b):
					m = p.population * gap / 40000 * countries[b].immigration
			m = mini(m, cap - sent)
			if m <= 0:
				continue
			sent += m
			delta[p.id] = int(delta[p.id]) - m
			delta[q.id] = int(delta[q.id]) + m
			if a != b:
				countries[a].migr_out += m
				countries[b].migr_in += m
		if p.port >= 0 and p.population >= 50000 and sent < cap:
			for d in dests:
				var di: int = int(d)
				if di == a or at_war(a, di) or int(att[di]) <= int(att[a]) + 15:
					continue
				var m2: int = p.population * (int(att[di]) - int(att[a])) / 200000 * countries[di].immigration
				m2 = mini(m2, cap - sent)
				if m2 <= 0:
					continue
				var dst: int = int(port_of[di])
				delta[p.id] = int(delta[p.id]) - m2
				delta[dst] = int(delta[dst]) + m2
				countries[a].migr_out += m2
				countries[di].migr_in += m2
				break
		if _over_budget():
			return false
	return true


func _migr_apply() -> void:
	var delta: Array = _ms["delta"]
	for i in provinces.size():
		var dv: int = int(delta[i])
		if dv != 0:
			provinces[i].population = maxi(0, provinces[i].population + dv)


func _simulate_migration() -> void:
	_migr_init()
	_sub = 0
	_deadline_us = 0
	_migr_step()
	_sub = 0
	_migr_apply()


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
			sup[out] = int(sup[out]) + p.factory_units()
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
		market_dem[g] = int(Province.PROCESSED_DEM.get(g, 3000)) if Province.PROCESSED.has(g) else int(sup[g])
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
## Versão em cache para a interface (válida no mesmo dia e sem comandos novos): painéis que pedem
## mercado várias vezes não recalculam tudo a cada abertura.
var _mt_ui: Array = []
var _mt_ui_key: Array = []


func market_tables_cached() -> Array:
	var key := [clock.year, clock.month, clock.day, cmd_seq]
	if _mt_ui.is_empty() or key != _mt_ui_key:
		_mt_ui = market_tables()
		_mt_ui_key = key
	return _mt_ui


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
			sup[o][f["out"]] += p.factory_units()
			var ins: Dictionary = f["inputs"]
			for g in ins.keys():
				dem[o][g] += p.factory_input(str(g))
	for i in n:
		for g in goods:
			dem[i][g] += int(market_dem[g]) * int(pops[i]) / market_pop0
	return [sup, dem, pops]


## Comércio mensal: cada país com déficit de um bem compra de quem tem sobra. Vizinhos por
## terra comerciam livre; por mar gasta capacidade (portos + navios) dos DOIS lados. Guerra e
## embargo bloqueiam. Depois, o preço local se ajusta ao saldo e o comércio rende ouro:
## exportador vende ao preço do comprador; importador ganha tarifas.
@warning_ignore("integer_division")
func _trade_init() -> void:
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
	trade_sea_use = []
	for i in n:
		trade_sea_use.append(0)
	for i in n:
		trade_imp.append({})
		trade_exp.append({})
		trade_bonus.append(0)
	_mt_cache = tb
	_ms["n"] = n
	_ms["goods"] = goods
	_ms["sup"] = sup
	_ms["dem"] = dem
	_ms["adj"] = adj
	_ms["cap"] = cap
	_ms["zmask"] = zmask
	_ms["route_cache"] = route_cache


@warning_ignore("integer_division")
func _trade_goods_step() -> bool:
	var n: int = _ms["n"]
	var goods: Array = _ms["goods"]
	var sup: Array = _ms["sup"]
	var dem: Array = _ms["dem"]
	var adj: Dictionary = _ms["adj"]
	var cap: Array = _ms["cap"]
	var zmask: Array = _ms["zmask"]
	var route_cache: Dictionary = _ms["route_cache"]
	while _sub < goods.size():
		var g: String = goods[_sub]
		_sub += 1
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
			need = need * (100 - maxi(0, countries[i].tariff - TRADE_TARIFF_PCT) * TARIFF_VOLUME_LOSS / 2) / 100
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
						# Custo da rota (Victoria 3): cada passagem/estreito atravessado encarece o frete.
						var lane: int = lane_cost(rgates.size())
						q = mini(q, mini(int(cap[i]), int(cap[e])) / lane)
						if q <= 0:
							continue
						cap[i] = int(cap[i]) - q * lane
						cap[e] = int(cap[e]) - q * lane
						trade_sea_use[i] = int(trade_sea_use[i]) + q * lane
						trade_sea_use[e] = int(trade_sea_use[e]) + q * lane
					need -= q
					avail[e] = int(avail[e]) - q
					trade_imp[i][g] = int(trade_imp[i].get(g, 0)) + q
					trade_exp[e][g] = int(trade_exp[e].get(g, 0)) + q
					var pi: int = int(local_price[i][g])
					var pe: int = int(local_price[e][g])
					trade_bonus[e] = int(trade_bonus[e]) + q * base * (pi - pe) / 10000
					trade_bonus[i] = int(trade_bonus[i]) + q * base * pi / 10000 * countries[i].tariff / 100
					for gi in rgates:
						gate_flow[int(gi)] = int(gate_flow[int(gi)]) + q
						var gc2 := gate_controller(int(gi))
						var toll_pct: int = int(gates[int(gi)].get("toll", 0))
						if gc2 >= 0 and gc2 != i and gc2 != e and toll_pct > 0:
							var toll: int = q * base * pi / 10000 * toll_pct / GATE_TOLL_BASE
							trade_bonus[gc2] = int(trade_bonus[gc2]) + toll
							trade_bonus[e] = int(trade_bonus[e]) - toll
		if _over_budget():
			return false
	return true


@warning_ignore("integer_division")
func _trade_prices() -> void:
	var n: int = _ms["n"]
	var goods: Array = _ms["goods"]
	var sup: Array = _ms["sup"]
	var dem: Array = _ms["dem"]
	for i in n:
		for g in goods:
			var s: int = int(sup[i][g]) - int(trade_exp[i].get(g, 0)) + int(trade_imp[i].get(g, 0))
			var d: int = int(dem[i][g])
			var delta: int = (d - s) * 8 / maxi(1, maxi(s, d))
			local_price[i][g] = clampi(int(local_price[i][g]) + delta, PRICE_MIN, PRICE_MAX)


func _run_trade() -> void:
	_trade_init()
	_sub = 0
	_deadline_us = 0
	_trade_goods_step()
	_sub = 0
	_trade_prices()


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
	finish_month()
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
		h = _mix(h, p.method * 10 + p.rmethod)
	for c in countries:
		h = _mix(h, c.treasury)
		h = _mix(h, c.tax_pct)
	for id in armies.keys():
		var a: Army = armies[id]
		h = _mix(h, a.id)
		h = _mix(h, a.supply)
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
	var prk: Array = pressure.keys()
	prk.sort()
	for k in prk:
		h = _mix(h, int(k))
		h = _mix(h, int(pressure[k]))
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
	for dk in [cb, treaties]:
		var dks: Array = dk.keys()
		dks.sort()
		for k in dks:
			h = _mix(h, int(k))
			h = _mix(h, int(dk[k]))
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
		h = _mix(h, c.debt * 5 + c.drill)
		h = _mix(h, c.spy_cd * 7 + c.infamy)
		h = _mix(h, c.budget_code * 1000 + (c.decree + 1) * 100 + c.decree_left)
		h = _mix(h, c.decree_cd)
		h = _mix(h, c.private_capital)
		h = _mix(h, c.tariff)
		h = _mix(h, c.excise * 100 + c.panic_left)
		h = _mix(h, c.elect_cd)
		for sj in 5:
			h = _mix(h, int(c.seats[sj]))
		h = _mix(h, c.interest * 1000 + c.inflation)
		h = _mix(h, c.researching)
		h = _mix(h, c.immigration * 7 + c.migr_in * 3 + c.migr_out)
		for tt in c.techs:
			h = _mix(h, int(tt))
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
	h = _mix(h, victories.size() * 2 + (1 if defeated else 0))
	h = _mix(h, ai_heg + 1)
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


func _country_seats() -> Array:
	var out: Array = []
	for c in countries:
		out.append(c.seats.duplicate())
	return out


func _country_ints(field: String) -> Array:
	var out: Array = []
	for c in countries:
		out.append(int(c.get(field)))
	return out


func _tech_lists() -> Array:
	var out: Array = []
	for c in countries:
		out.append(c.techs.duplicate())
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
	var fmethods: Array = []
	var rmethods: Array = []
	for p in provinces:
		owners.append(p.owner_id)
		pops.append(p.population)
		mps.append(p.manpower)
		workshops.append(p.workshop)
		barracks.append(p.barracks)
		fkinds.append(p.factory)
		flevels.append(p.factory_level)
		fmethods.append(p.method)
		rmethods.append(p.rmethod)
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
		"player": player_country,
		"owners": owners,
		"cores": _province_cores(),
		"pops": pops,
		"manpower": mps,
		"workshops": workshops,
		"bld": blds,
		"tech": _country_ints("tech_pts"),
		"techs": _tech_lists(),
		"researching": _country_ints("researching"),
		"lit_acc": _country_ints("lit_acc"),
		"stab": _country_ints("stability"),
		"sat": _sat_list(),
		"auto_front": _country_ints("auto_front"),
		"overlord": _country_ints("overlord"),
		"overlord_since": _country_ints("overlord_since"),
		"research_pct": _country_ints("research_pct"),
		"debt": _country_ints("debt"),
		"drill": _country_ints("drill"),
		"spy_cd": _country_ints("spy_cd"),
		"budget_code": _country_ints("budget_code"),
		"decree": _country_ints("decree"),
		"decree_left": _country_ints("decree_left"),
		"decree_cd": _country_ints("decree_cd"),
		"private_capital": _country_ints("private_capital"),
		"tariff": _country_ints("tariff"),
		"excise": _country_ints("excise"),
		"panic_left": _country_ints("panic_left"),
		"elect_cd": _country_ints("elect_cd"),
		"seats": _country_seats(),
		"interest": _country_ints("interest"),
		"inflation": _country_ints("inflation"),
		"infamy": _country_ints("infamy"),
		"ai_heg": ai_heg,
		"victories": victories.duplicate(),
		"defeated": defeated,
		"immigration": _country_ints("immigration"),
		"migr_in": _country_ints("migr_in"),
		"migr_out": _country_ints("migr_out"),
		"last_income": _country_ints("last_income"),
		"last_expense": _country_ints("last_expense"),
		"laws": _law_lists("laws"),
		"law_cd": _law_lists("law_cd"),
		"barracks": barracks,
		"factory": fkinds,
		"factory_lvl": flevels,
		"factory_method": fmethods,
		"res_method": rmethods,
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
		"cb": _dict_to_pairs(cb),
		"treaties": _dict_to_pairs(treaties),
		"peace_offers": peace_offers.duplicate(true),
		"peace_cd": _dict_to_pairs(peace_cd),
		"pressure": _dict_to_pairs(pressure),
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
	_month_stage = -1
	_month_running = false
	_sub = 0
	_ms.clear()
	_stage_acc = 0
	_mt_ui = []
	_cmd_queue.clear()
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
		var fme: Array = d.get("factory_method", [])
		provinces[i].method = int(fme[i]) if i < fme.size() else 0
		var rme: Array = d.get("res_method", [])
		provinces[i].rmethod = int(rme[i]) if i < rme.size() else 0
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
	var imm: Array = d.get("immigration", [])
	var mig_i: Array = d.get("migr_in", [])
	var mig_o: Array = d.get("migr_out", [])
	for i in countries.size():
		countries[i].immigration = int(imm[i]) if i < imm.size() else 1
		countries[i].migr_in = int(mig_i[i]) if i < mig_i.size() else 0
		countries[i].migr_out = int(mig_o[i]) if i < mig_o.size() else 0
	if d.has("techs"):
		var tl: Array = d["techs"]
		var rs: Array = d.get("researching", [])
		for i in countries.size():
			var lst: Array = []
			if i < tl.size():
				for v in tl[i]:
					lst.append(int(v))
			countries[i].techs = lst
			countries[i].researching = int(rs[i]) if i < rs.size() else -1
			countries[i].fx_dirty = true
	else:
		# salvamento antigo: o nível vinha dos pontos (400 por nível)
		for i in countries.size():
			var old_pts: int = countries[i].tech_pts
			_set_tech_level(countries[i], old_pts / Country.TECH_STEP)
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
	var dbt: Array = d.get("debt", [])
	var drl: Array = d.get("drill", [])
	var spc: Array = d.get("spy_cd", [])
	var inf: Array = d.get("infamy", [])
	var bcs: Array = d.get("budget_code", [])
	var dcs: Array = d.get("decree", [])
	var dls: Array = d.get("decree_left", [])
	var dcd: Array = d.get("decree_cd", [])
	var pcs: Array = d.get("private_capital", [])
	var trs: Array = d.get("tariff", [])
	var exs: Array = d.get("excise", [])
	var pls: Array = d.get("panic_left", [])
	var ecs: Array = d.get("elect_cd", [])
	var parl: Array = d.get("seats", [])
	var ints: Array = d.get("interest", [])
	var infl: Array = d.get("inflation", [])
	ai_heg = int(d.get("ai_heg", -1))
	victories = (d.get("victories", []) as Array).duplicate()
	defeated = bool(d.get("defeated", false))
	for i in countries.size():
		countries[i].debt = int(dbt[i]) if i < dbt.size() else 0
		countries[i].drill = int(drl[i]) if i < drl.size() else 0
		countries[i].spy_cd = int(spc[i]) if i < spc.size() else 0
		countries[i].infamy = int(inf[i]) if i < inf.size() else 0
		countries[i].budget_code = int(bcs[i]) if i < bcs.size() else Government.DEFAULT_CODE
		countries[i].decree = int(dcs[i]) if i < dcs.size() else -1
		countries[i].decree_left = int(dls[i]) if i < dls.size() else 0
		countries[i].decree_cd = int(dcd[i]) if i < dcd.size() else 0
		countries[i].private_capital = int(pcs[i]) if i < pcs.size() else 0
		countries[i].tariff = int(trs[i]) if i < trs.size() else TRADE_TARIFF_PCT
		countries[i].excise = int(exs[i]) if i < exs.size() else 0
		countries[i].panic_left = int(pls[i]) if i < pls.size() else 0
		countries[i].elect_cd = int(ecs[i]) if i < ecs.size() else 6 + i % 42
		var sv: Array = [0, 0, 0, 0, 0]
		if i < parl.size() and parl[i] is Array and (parl[i] as Array).size() == 5:
			for sj in 5:
				sv[sj] = int(parl[i][sj])
		countries[i].seats = sv
		countries[i].interest = int(ints[i]) if i < ints.size() else LOAN_RATE_PCT
		countries[i].inflation = int(infl[i]) if i < infl.size() else 0
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
	pressure.clear()
	for r in d.get("pressure", []):
		pressure[int(r[0])] = int(r[1])
	peace_cd.clear()
	for r in d.get("peace_cd", []):
		peace_cd[int(r[0])] = int(r[1])
	truces.clear()
	for r in d.get("truces", []):
		truces[int(r[0])] = int(r[1])
	cb.clear()
	for r in d.get("cb", []):
		cb[int(r[0])] = int(r[1])
	treaties.clear()
	for r in d.get("treaties", []):
		treaties[int(r[0])] = int(r[1])
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
	player_country = int(d.get("player", player_country))
	_rebuild_all_countries()
	Events.state_loaded.emit()
	Events.speed_changed.emit(speed)
	return true


func save_game(path: String = SAVE_PATH) -> bool:
	finish_month()
	var t0 := Time.get_ticks_usec()
	# Gravação atômica: escreve num arquivo temporário e só então troca pelo definitivo; um
	# fechamento no meio da escrita nunca corrompe o save existente.
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		Events.trace.emit("save", "FALHA ao abrir %s para gravar (erro %d)" % [tmp, FileAccess.get_open_error()])
		return false
	var text := JSON.stringify(serialize_state())
	file.store_string(text)
	var werr := file.get_error()
	file.flush()
	file.close()
	if werr != OK:
		Events.trace.emit("save", "FALHA ao gravar %s (erro %d)" % [tmp, werr])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	var rerr := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if rerr != OK:
		# alguns sistemas não sobrescrevem no rename: remove o antigo e tenta de novo
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		rerr = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
		if rerr != OK:
			Events.trace.emit("save", "FALHA ao trocar %s (erro %d)" % [path, rerr])
			return false
	Events.trace.emit("save", "Gravado %s: %d KB em %.0f ms" % [path, text.length() / 1024, float(Time.get_ticks_usec() - t0) / 1000.0])
	return true


## Save mais recente entre o manual e os dois autosaves (rodízio). "" se não houver.
func latest_save_path() -> String:
	var best := ""
	var best_t := -1
	for p in [SAVE_PATH, AUTOSAVE_PATH, AUTOSAVE_PREV]:
		if FileAccess.file_exists(p):
			var mt: int = int(FileAccess.get_modified_time(p))
			if mt > best_t:
				best_t = mt
				best = p
	return best


## Autosave com rodízio de 2 arquivos: o anterior vira _prev (troca de nome, sem copiar), então
## nunca falta um save íntegro, mesmo se o app fechar no meio.
func autosave() -> bool:
	var had := FileAccess.file_exists(AUTOSAVE_PATH)
	if had:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(AUTOSAVE_PATH), ProjectSettings.globalize_path(AUTOSAVE_PREV))
	var ok := save_game(AUTOSAVE_PATH)
	if not ok and had and not FileAccess.file_exists(AUTOSAVE_PATH):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(AUTOSAVE_PREV), ProjectSettings.globalize_path(AUTOSAVE_PATH))
	return ok


func load_game(path: String = SAVE_PATH) -> bool:
	var t0 := Time.get_ticks_usec()
	if not FileAccess.file_exists(path):
		Events.trace.emit("load", "Save inexistente: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		Events.trace.emit("load", "FALHA ao abrir %s (erro %d)" % [path, FileAccess.get_open_error()])
		return false
	var raw := file.get_as_text()
	var data: Variant = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		Events.trace.emit("load", "FALHA: save corrompido ou não é JSON (%d KB)" % [raw.length() / 1024])
		return false
	var dict: Dictionary = data
	var ok := load_state(dict)
	Events.trace.emit("load", "%s: %d KB em %.0f ms" % ["Carregado" if ok else "FALHA em load_state", raw.length() / 1024, float(Time.get_ticks_usec() - t0) / 1000.0])
	return ok

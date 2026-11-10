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
const BUILD_COSTS := {"workshop": 120, "barracks": 100, "textile": 150, "smithy": 180, "carpentry": 130}   # x (nível atual + 1)

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

# Marinha e comércio
const SHIP_COST := 80
const SHIP_DAYS := 40
const SHIP_UPKEEP := 3
const SHIP_CAP := 120            # unidades de comércio marítimo por navio por mês
const PORT_CAP := 40             # capacidade básica por porto (província costeira)
const PRICE_MIN := 70
const PRICE_MAX := 140
const TRADE_TARIFF_PCT := 10     # ganho do importador (tarifas) sobre o valor importado

# Diplomacia
const IMPROVE_COST := 50
const ALLIANCE_MIN_OPINION := 40
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
var wars: Array = []             # [{a, b, days}] com a < b
var sieges: Dictionary = {}      # província -> {by, days}
# Mercado mundial: preço (% do base) por recurso, demanda-base e população de referência.
var local_price: Array = []        # por país: {bem -> % do preço-base}
var embargoes: Array = []          # emissor*1000+alvo
var trade_imp: Array = []          # por país: {bem -> unidades} (derivado, mostra o último mês)
var trade_exp: Array = []
var trade_bonus: Array = []
var market_dem: Dictionary = {}
var market_pop0: int = 1
var relations: Dictionary = {}   # par -> opinião (-100..100)
var alliances: Array = []        # pares aliados
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
	training.clear()
	wars.clear()
	sieges.clear()
	relations.clear()
	alliances.clear()
	truces.clear()
	embargoes.clear()
	next_army_id = 1
	pending_events.clear()
	fired_events.clear()
	next_event_uid = 1
	_load_event_defs()
	for cd in dict["countries"]:
		countries.append(Country.from_dict(cd))
	for pd in dict["provinces"]:
		provinces.append(Province.from_dict(pd))

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

	_rebuild_all_countries()
	_init_market()
	graph = ProvinceGraph.new()
	graph.setup(provinces)

	for c in countries:
		c.treasury = maxi(MIN_START_TREASURY, int(estimate_monthly(c)["income"]) * 8)
		if c.is_alive():
			# Exército inicial na capital, proporcional à população histórica.
			var regs := clampi(int(c.pop_total * 0.6), 1, 40)
			_add_regiments(c.capital, c.id, regs)

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
		countries[issuer].treasury -= build_cost(p, kind)
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
		if not can_make_peace(issuer, target):
			return
		if not is_human(target) and regiments_of(target) > regiments_of(issuer):
			if issuer == player_country:
				Events.notice.emit("%s recusou a paz: ainda se sente mais forte." % countries[target].name)
			return
		_end_war(issuer, target)
		truces[_pair(issuer, target)] = tick + TRUCE_DAYS
		Events.war_changed.emit()

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
		if not allied(issuer, target):
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
	return p.owner_id == issuer and p.coastal and countries[issuer].treasury >= SHIP_COST


## Capacidade de comércio marítimo: portos + navios; inimigos com mais navios bloqueiam.
func sea_capacity(cid: int) -> int:
	var enemy_ships := 0
	for o in wars_of(cid):
		enemy_ships += countries[o].ships
	var mine: int = countries[cid].ships
	var base: int = 0 if enemy_ships > mine else ports_of(cid) * PORT_CAP
	return base + maxi(0, mine - enemy_ships) * SHIP_CAP


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
	return countries[target].is_alive() and not at_war(issuer, target) and not allied(issuer, target)


## Declara a guerra e chama os aliados do alvo (defensivo).
func _start_war(attacker: int, target: int) -> void:
	wars.append({"a": mini(attacker, target), "b": maxi(attacker, target), "days": 0})
	relations[_pair(attacker, target)] = -100
	if attacker == player_country or target == player_country:
		Events.notice.emit("%s declarou guerra a %s!" % [countries[attacker].name, countries[target].name])
	for al in allies_of(target):
		if al != attacker and not at_war(al, attacker) and not allied(al, attacker) and countries[al].is_alive():
			wars.append({"a": mini(al, attacker), "b": maxi(al, attacker), "days": 0})
			if al == player_country:
				Events.notice.emit("Seu aliado %s foi atacado: você entrou na guerra." % countries[target].name)
	Events.war_changed.emit()


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
	return int(BUILD_COSTS.get(kind, 0)) * (p.building_level(kind) + 1)


func can_build(pid: int, issuer: int, kind: String) -> bool:
	if not BUILD_COSTS.has(kind):
		return false
	if pid < 0 or pid >= provinces.size() or issuer < 0 or issuer >= countries.size():
		return false
	var p := provinces[pid]
	if p.owner_id != issuer or p.building_level(kind) >= Province.MAX_BUILDING:
		return false
	if Province.FACTORIES.has(kind) and p.factory != "" and p.factory != kind:
		return false   # uma fábrica por província
	return countries[issuer].treasury >= build_cost(p, kind)


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
				countries[int(t["owner"])].ships += 1
			else:
				_add_regiments(int(t["province"]), int(t["owner"]), 1)
			Events.province_updated.emit(int(t["province"]))
		else:
			remaining.append(t)
	training = remaining


func _advance_armies() -> void:
	for id in armies.keys():
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
	for c in countries:
		if not c.is_alive() or is_human(c.id):
			continue
		if tick % 30 == 0:
			_ai_recruit(c)
			_ai_build_ship(c)
			_ai_declare_war(c)
		if not wars_of(c.id).is_empty():
			_ai_war(c)


@warning_ignore("integer_division")
func _ai_recruit(c: Country) -> void:
	var enemies := wars_of(c.id)
	var want: int = 2 + c.province_ids.size() / 6 + (2 if not enemies.is_empty() else 0)
	want = mini(want, 30)
	if regiments_of(c.id) + _queued_for(c.id) >= want or c.treasury < RECRUIT_COST + 100:
		return
	if can_recruit(c.capital, c.id):
		_do_recruit(c.capital, c.id)
		return
	for pid in c.province_ids:
		if can_recruit(pid, c.id):
			_do_recruit(pid, c.id)
			return


## A IA ataca o vizinho mais fraco que não seja aliado, em trégua nem de boa relação.
@warning_ignore("integer_division")
func _ai_declare_war(c: Country) -> void:
	if tick < AI_WAR_GRACE_TICKS or not wars_of(c.id).is_empty():
		return
	var mine := regiments_of(c.id)
	if mine < 3 or c.treasury < 200:
		return
	var nbrs := {}
	for pid in c.province_ids:
		var p := provinces[pid]
		for n in p.neighbors:
			var o := provinces[int(n)].owner_id
			if o >= 0 and o != c.id:
				nbrs[o] = true
		for n in p.sea_links:
			var o2 := provinces[int(n)].owner_id
			if o2 >= 0 and o2 != c.id:
				nbrs[o2] = true
	var keys: Array = nbrs.keys()
	keys.sort()
	var best := -1
	var best_regs := 1 << 30
	for o in keys:
		var oc := countries[int(o)]
		if not oc.is_alive() or not can_declare_war(c.id, oc.id) or opinion(c.id, oc.id) >= 20:
			continue
		var r := regiments_of(oc.id)
		if r * 2 > mine:
			continue
		if r < best_regs:
			best_regs = r
			best = oc.id
	if best < 0 or rng.randi_range(0, AI_WAR_CHANCE - 1) != 0:
		return
	_start_war(c.id, best)


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
			cands.append({"id": p.id, "d": origin.distance_squared_to(p.center)})
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
		p.population += p.population / 1000
		# Recuperação de mão de obra.
		var mx := p.manpower_max()
		if p.manpower < mx:
			p.manpower = mini(mx, p.manpower + maxi(1, mx * MANPOWER_REGEN_PCT / 100))
	_run_trade()
	# Economia: impostos + comércio - manutenção (províncias, regimentos e navios).
	for c in countries:
		if not c.is_alive():
			continue
		var e := estimate_monthly(c)
		c.last_income = int(e["income"])
		c.last_expense = int(e["expense"])
		c.treasury += c.last_income - c.last_expense
	for k in relations.keys():
		var v: int = int(relations[k])
		if at_war(int(k) / 1000, int(k) % 1000):
			continue
		relations[k] = v - signi(v) * mini(absi(v), 2)
	_roll_events()
	Events.month_changed.emit(clock.to_dict())
	for c in countries:
		Events.treasury_changed.emit(c.id)


# ---------------------------------------------------------------------------
# Eventos (data/events.json)
# ---------------------------------------------------------------------------
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
	if fx.has("pop_pct"):
		var pct: int = int(fx["pop_pct"])
		for pid in c.province_ids:
			provinces[pid].population += provinces[pid].population * pct / 100


## Previsão mensal de um país (usada pela simulação e pela UI).
func estimate_monthly(c: Country) -> Dictionary:
	var tax := 0
	var flat := 0
	var prod := 0
	var industry := 0
	for pid in c.province_ids:
		var p := provinces[pid]
		tax += p.monthly_tax(c.tax_pct)
		industry += p.factory_profit()
		flat += Province.FLAT_TAX
		prod += p.production()
	var regs := regiments_of(c.id)
	var up_prov: int = c.province_ids.size() * EXPENSE_PER_PROVINCE
	var up_army: int = regs * REGIMENT_UPKEEP
	var up_navy: int = c.ships * SHIP_UPKEEP
	var trade: int = int(trade_bonus[c.id]) if c.id < trade_bonus.size() else 0
	return {
		"income": tax + industry + trade, "industry": industry, "trade": trade,
		"expense": up_prov + up_army + up_navy, "regiments": regs,
		"flat": flat, "production": prod, "upkeep_prov": up_prov, "upkeep_army": up_army, "upkeep_navy": up_navy,
	}


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
					if not land:
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
	c.label_size = clampi(int(rect.size.x * 0.14), 14, 64)

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
	for w in wars:
		h = _mix(h, int(w["a"]) * 1000 + int(w["b"]))
		h = _mix(h, int(w["days"]))
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
		"pops": pops,
		"manpower": mps,
		"workshops": workshops,
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
		"ships": _ships_list(),
		"embargoes": embargoes.duplicate(),
		"alliances": alliances.duplicate(),
		"truces": _dict_to_pairs(truces),
		"next_army_id": next_army_id,
		"events": pending_events.duplicate(true),
		"fired": fired_events.keys(),
		"next_event_uid": next_event_uid,
		"rng": str(rng.state),   # texto: o estado é uint64 e o JSON só guarda float
	}


func load_state(d: Dictionary) -> bool:
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
	wars.clear()
	for w in d.get("wars", []):
		wars.append({"a": int(w["a"]), "b": int(w["b"]), "days": int(w["days"])})
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
	var sh: Array = d.get("ships", [])
	for i in countries.size():
		countries[i].ships = int(sh[i]) if i < sh.size() else 0
	embargoes.clear()
	for k in d.get("embargoes", []):
		embargoes.append(int(k))
	relations.clear()
	for r in d.get("relations", []):
		relations[int(r[0])] = int(r[1])
	alliances.clear()
	for pr in d.get("alliances", []):
		alliances.append(int(pr))
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

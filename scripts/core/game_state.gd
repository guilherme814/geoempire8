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
const BUILD_COSTS := {"workshop": 120, "barracks": 100}   # x (nível atual + 1)

# Exército
const REGIMENT_SIZE := 1000
const RECRUIT_COST := 30
const RECRUIT_DAYS := 30
const MAX_QUEUE_PER_PROVINCE := 3
const MANPOWER_REGEN_PCT := 10   # % do máximo recuperado por mês

var loaded: bool = false
var map_size: Vector2 = Vector2(3072.0, 1394.0)
var provinces: Array[Province] = []
var countries: Array[Country] = []
var clock: GameClock = GameClock.new()
var graph: ProvinceGraph

var armies: Dictionary = {}      # id -> Army
var training: Array = []         # [{province, owner, days}]
var next_army_id: int = 1

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
		provinces[pid].manpower -= REGIMENT_SIZE
		countries[issuer].treasury -= RECRUIT_COST
		training.append({"province": pid, "owner": issuer, "days": RECRUIT_DAYS})
		Events.province_updated.emit(pid)
		Events.treasury_changed.emit(issuer)

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
		if int(t["province"]) == pid:
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


@warning_ignore("integer_division")
func _simulate_month() -> void:
	for p in provinces:
		# Crescimento demográfico: +0,1% ao mês.
		p.population += p.population / 1000
		# Recuperação de mão de obra.
		var mx := p.manpower_max()
		if p.manpower < mx:
			p.manpower = mini(mx, p.manpower + maxi(1, mx * MANPOWER_REGEN_PCT / 100))
	# Economia: impostos - manutenção (províncias e regimentos).
	for c in countries:
		if not c.is_alive():
			continue
		var e := estimate_monthly(c)
		c.last_income = int(e["income"])
		c.last_expense = int(e["expense"])
		c.treasury += c.last_income - c.last_expense
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
	for pid in c.province_ids:
		var p := provinces[pid]
		tax += p.monthly_tax(c.tax_pct)
		flat += Province.FLAT_TAX
		prod += p.production()
	var regs := regiments_of(c.id)
	var up_prov: int = c.province_ids.size() * EXPENSE_PER_PROVINCE
	var up_army: int = regs * REGIMENT_UPKEEP
	return {
		"income": tax, "expense": up_prov + up_army, "regiments": regs,
		"flat": flat, "production": prod, "upkeep_prov": up_prov, "upkeep_army": up_army,
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
	for t in training:
		h = _mix(h, int(t["province"]))
		h = _mix(h, int(t["owner"]))
		h = _mix(h, int(t["days"]))
	for e in pending_events:
		h = _mix(h, int(e["uid"]))
		h = _mix(h, int(e["days"]))
	h = _mix(h, next_event_uid)
	h = _mix(h, rng.state & 0xFFFFFFFF)
	return h


func _mix(h: int, v: int) -> int:
	return ((h ^ (v & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF


func serialize_state() -> Dictionary:
	var owners: Array = []
	var pops: Array = []
	var mps: Array = []
	var workshops: Array = []
	var barracks: Array = []
	for p in provinces:
		owners.append(p.owner_id)
		pops.append(p.population)
		mps.append(p.manpower)
		workshops.append(p.workshop)
		barracks.append(p.barracks)
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
		"treasury": treasury,
		"taxes": taxes,
		"capitals": capitals,
		"armies": army_list,
		"training": training.duplicate(true),
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
		training.append({"province": int(t["province"]), "owner": int(t["owner"]), "days": int(t["days"])})
	next_army_id = int(d.get("next_army_id", 1))

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

extends Node
## Estado global e motor da simulação (autoload "Game").
##
## Regras de ouro (necessárias para o multiplayer P2P determinístico):
##  1. O estado de jogo só muda via apply_command() e _simulate_*().
##  2. Nada de randf()/Time/OS dentro da simulação: use `rng` (semente fixa) e inteiros.
##  3. A UI nunca altera o estado direto: ela chama submit_command().
##  4. step() é a ÚNICA função que avança o jogo. Offline ela é chamada por _process();
##     online (lockstep) quem chama é o Net, com a lista de comandos de cada frame.

const WORLD_PATH := "res://data/world.json"
const SAVE_PATH := "user://savegame.json"

## Dias simulados por segundo em cada velocidade (0 = pausado).
const SPEED_TPS: Array[float] = [0.0, 2.0, 5.0, 10.0, 25.0]
const MAX_SPEED := 4
const START_TREASURY := 1000
const EXPENSE_PER_PROVINCE := 5
const ALLOW_DEBUG_COMMANDS := true

var loaded: bool = false
var map_size: Vector2 = Vector2(2400.0, 1200.0)
var provinces: Array[Province] = []
var countries: Array[Country] = []
var clock: GameClock = GameClock.new()

var tick: int = 0     # dias simulados
var frame: int = 0    # passos executados (inclui frames com o jogo pausado)
var speed: int = 1
var player_country: int = 0
var lockstep: bool = false   # true quando o Net controla o avanço do tempo
var world_seed: int = 1850
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
	for cd in dict["countries"]:
		countries.append(Country.from_dict(cd))
	for pd in dict["provinces"]:
		provinces.append(Province.from_dict(pd))

	# Os índices dos arrays precisam ser iguais aos ids (acesso O(1) em todo o código).
	for i in countries.size():
		if countries[i].id != i:
			push_error("GeoEmpire: ids de países precisam ser sequenciais")
			return false
		countries[i].treasury = START_TREASURY
	for i in provinces.size():
		if provinces[i].id != i:
			push_error("GeoEmpire: ids de províncias precisam ser sequenciais")
			return false

	world_seed = int(dict.get("seed", world_seed))
	rng.seed = world_seed
	clock = GameClock.new()
	tick = 0
	frame = 0
	speed = 1
	_rebuild_all_countries()
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
	Events.day_changed.emit(clock.to_dict())
	if month_rolled:
		_simulate_month()
	Events.tick_advanced.emit(tick)


@warning_ignore("integer_division")
func _simulate_month() -> void:
	# Crescimento demográfico: +0,1% ao mês.
	for p in provinces:
		p.population += p.population / 1000
	# Economia básica: renda de impostos - manutenção.
	for c in countries:
		if not c.is_alive():
			continue
		var e := estimate_monthly(c)
		c.last_income = int(e["income"])
		c.last_expense = int(e["expense"])
		c.treasury += c.last_income - c.last_expense
	Events.month_changed.emit(clock.to_dict())
	for c in countries:
		Events.treasury_changed.emit(c.id)


## Previsão mensal de um país (usada pela simulação e pela UI).
func estimate_monthly(c: Country) -> Dictionary:
	var income := 0
	for pid in c.province_ids:
		income += provinces[pid].monthly_income(c.tax_pct)
	var expense: int = c.province_ids.size() * EXPENSE_PER_PROVINCE
	return {"income": income, "expense": expense}


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


func _refresh_country_geometry(c: Country) -> void:
	if c.province_ids.is_empty():
		c.bounds = Rect2()
		return
	var rect: Rect2 = provinces[c.province_ids[0]].bounds
	var sum := Vector2.ZERO
	for pid in c.province_ids:
		var p := provinces[pid]
		rect = rect.merge(p.bounds)
		sum += p.center
	var mean := sum / float(c.province_ids.size())

	# O rótulo fica no centro da província mais próxima da média (nunca no mar).
	var best := c.province_ids[0]
	var best_d := INF
	for pid in c.province_ids:
		var d := provinces[pid].center.distance_squared_to(mean)
		if d < best_d:
			best_d = d
			best = pid
	c.bounds = rect
	c.label_pos = provinces[best].center
	c.label_size = clampi(int(rect.size.x * 0.12), 14, 72)

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
	for p in provinces:
		h = _mix(h, p.owner_id)
		h = _mix(h, p.population)
	for c in countries:
		h = _mix(h, c.treasury)
		h = _mix(h, c.tax_pct)
	return h


func _mix(h: int, v: int) -> int:
	return ((h ^ (v & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF


func serialize_state() -> Dictionary:
	var owners: Array = []
	var pops: Array = []
	for p in provinces:
		owners.append(p.owner_id)
		pops.append(p.population)
	var treasury: Array = []
	var taxes: Array = []
	var capitals: Array = []
	for c in countries:
		treasury.append(c.treasury)
		taxes.append(c.tax_pct)
		capitals.append(c.capital)
	return {
		"version": 1,
		"tick": tick,
		"frame": frame,
		"speed": speed,
		"date": clock.to_dict(),
		"owners": owners,
		"pops": pops,
		"treasury": treasury,
		"taxes": taxes,
		"capitals": capitals,
	}


func load_state(d: Dictionary) -> bool:
	var owners: Array = d.get("owners", [])
	var pops: Array = d.get("pops", [])
	var treasury: Array = d.get("treasury", [])
	var taxes: Array = d.get("taxes", [])
	var capitals: Array = d.get("capitals", [])
	if owners.size() != provinces.size() or pops.size() != provinces.size():
		push_error("GeoEmpire: snapshot incompatível com o mapa carregado")
		return false
	if treasury.size() != countries.size() or taxes.size() != countries.size() or capitals.size() != countries.size():
		push_error("GeoEmpire: snapshot incompatível (países)")
		return false

	for i in provinces.size():
		provinces[i].owner_id = int(owners[i])
		provinces[i].population = int(pops[i])
	for i in countries.size():
		countries[i].treasury = int(treasury[i])
		countries[i].tax_pct = int(taxes[i])
		countries[i].capital = int(capitals[i])

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

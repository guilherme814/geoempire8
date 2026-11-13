class_name AiBrain
extends RefCounted
## Cérebro estratégico da IA (V0.15, fase 1). Ciclo mensal, sem estado próprio:
##   1. Avaliação nacional  - força militar própria (exata), reservas, estabilidade.
##   2. Interesses          - alvos vizinhos, reivindicações (territórios núcleo), hostilidade.
##   3. Preparação          - recruta mais e junta reservas quando o alvo é viável.
##   4. Pressão diplomática - ameaças (relação cai), cortejo e coalizões contra o alvo.
## A IA NÃO enxerga o estado real do rival: estima a força por soldados e navios visíveis,
## sem tecnologia nem tesouro, com incerteza determinística (ruído por par e semestre) que
## diminui com a tecnologia e a alfabetização. Tudo em inteiros, sem usar `rng`, para manter o
## lockstep P2P; o estado que muda (relações, alianças) já é salvo e entra no hash.

const MAX_SPREAD := 45          # incerteza máxima (± %) sobre a força do rival
const MIN_SPREAD := 15
const CLAIM_PTS := 40           # motivo por província núcleo em mãos do rival
const PREP_MAX_BONUS := 4       # regimentos extras que a IA aceita recrutar ao se preparar
const PRESSURE_BAND := 25       # % abaixo da razão exigida que ainda gera pressão
const RESERVE_MONTHS := 6       # reservas mínimas (meses de despesa) para iniciar guerra


static func _noise(a: int, b: int, salt: int) -> int:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (salt * 83492791)
	h = h & 0x7fffffff
	return h % 201 - 100


## Força que qualquer observador consegue ver: regimentos e navios (sem tecnologia nem tesouro).
static func _visible_power(g: Node, cid: int) -> int:
	return g.regiments_of(cid) * 100 + int(g.countries[cid].ships) * 40


## Força própria (a IA conhece o próprio país, incluindo tecnologia).
static func own_power(g: Node, cid: int) -> int:
	return _visible_power(g, cid) + int(g.countries[cid].tech_level()) * 15


## Estimativa da força do alvo: ruído determinístico + aliados vistos com peso menor e mais névoa.
@warning_ignore("integer_division")
static func perceived_power(g: Node, observer: int, target: int) -> int:
	var o = g.countries[observer]
	var spread: int = clampi(MAX_SPREAD - int(o.tech_level()) * 4 - int(o.literacy) / 40, MIN_SPREAD, MAX_SPREAD)
	var salt: int = (int(g.clock.year) * 12 + int(g.clock.month)) / 6
	var p: int = _visible_power(g, target) * (100 + _noise(observer, target, salt) * spread / 100) / 100
	for al in g.allies_of(target):
		if int(al) == observer or not g.countries[int(al)].is_alive():
			continue
		p += _visible_power(g, int(al)) * (100 + _noise(observer, int(al), salt) * MAX_SPREAD / 100) / 200
	return maxi(0, p)


@warning_ignore("integer_division")
static func ready_for_war(g: Node, c) -> bool:
	if int(c.stability) < 35 or g.regiments_of(c.id) < 3:
		return false
	return int(c.treasury) >= maxi(200, int(c.last_expense) * RESERVE_MONTHS)


static func claims(g: Node, c, t) -> int:
	var n := 0
	for pid in t.province_ids:
		if int(g.provinces[pid].core_owner) == c.id:
			n += 1
	return n


## Razão de forças (x100: própria / estimada do rival) exigida para atacar.
## Só uma razão excepcional (reivindicação ou hostilidade) permite atacar um rival forte.
static func required_ratio(g: Node, c, t) -> int:
	var cl := claims(g, c, t)
	var op: int = g.opinion(c.id, t.id)
	if cl >= 2:
		return 75
	if cl == 1:
		return 90
	if op <= -40:
		return 130
	if op <= -15:
		return 180
	return 250   # oportunismo: só contra alvo claramente mais fraco


static func motive(g: Node, c, t) -> int:
	var m := mini(3, claims(g, c, t)) * CLAIM_PTS
	var op: int = g.opinion(c.id, t.id)
	if op <= -40:
		m += 30
	elif op <= -15:
		m += 12
	return m


static func neighbors(g: Node, c) -> Array:
	var nbrs := {}
	for pid in c.province_ids:
		var p = g.provinces[pid]
		for n in p.neighbors:
			var o: int = g.provinces[int(n)].owner_id
			if o >= 0 and o != c.id:
				nbrs[o] = true
		for n in p.sea_links:
			var o2: int = g.provinces[int(n)].owner_id
			if o2 >= 0 and o2 != c.id:
				nbrs[o2] = true
	var keys: Array = nbrs.keys()
	keys.sort()
	return keys


## Plano do mês: {"stage": "none|prepare|pressure|war", "target", "ratio", "motive"}.
@warning_ignore("integer_division")
static func plan(g: Node, c) -> Dictionary:
	var best := {"stage": "none", "target": -1, "ratio": 0, "motive": 0}
	if not g.wars_of(c.id).is_empty() or int(g.tick) < int(g.AI_WAR_GRACE_TICKS):
		return best
	var mine := own_power(g, c.id)
	var best_score := -1
	for o in neighbors(g, c):
		var t = g.countries[int(o)]
		if not t.is_alive() or not g.can_declare_war(c.id, t.id):
			continue
		var seen := maxi(1, perceived_power(g, c.id, t.id))
		var ratio: int = mine * 100 / seen
		var need := required_ratio(g, c, t)
		var mot := motive(g, c, t)
		var stage := "none"
		if ratio >= need and ready_for_war(g, c):
			stage = "war"
		elif mot > 0 and ratio * 100 >= need * (100 - PRESSURE_BAND):
			stage = "pressure"
		elif mot > 0 and (mine + PREP_MAX_BONUS * 100) * 100 / seen >= need:
			stage = "prepare"
		elif ratio >= need:
			stage = "prepare"   # forte o bastante, mas sem reservas: junta dinheiro
		if stage == "none":
			continue
		var rank := {"war": 3, "pressure": 2, "prepare": 1}[stage]
		var score: int = rank * 100000 + mot * 100 + mini(ratio, 99)
		if score > best_score:
			best_score = score
			best = {"stage": stage, "target": t.id, "ratio": ratio, "motive": mot}
	return best


## Regimentos extras desejados enquanto a IA se prepara para uma guerra.
static func recruit_bonus(plan_d: Dictionary) -> int:
	match str(plan_d["stage"]):
		"prepare":
			return 2
		"pressure":
			return PREP_MAX_BONUS
		"war":
			return PREP_MAX_BONUS
	return 0


## Pressão diplomática: ameaça o alvo (relação cai), avisa o jogador e busca coalizão.
static func apply_pressure(g: Node, c, plan_d: Dictionary) -> void:
	var tid: int = int(plan_d["target"])
	if tid < 0:
		return
	var key: int = g._pair(c.id, tid)
	g.relations[key] = maxi(-100, g.opinion(c.id, tid) - 3)
	if g.is_human(tid) and (int(g.clock.month) + c.id) % 3 == 0:
		Events.notice.emit("%s concentra tropas e faz exigências a você." % c.name)
	var formed := false
	for o in g.countries:
		if formed or o.id == c.id or o.id == tid or not o.is_alive():
			continue
		if g.allied(o.id, tid) or g.at_war(c.id, o.id) or g.opinion(o.id, tid) > -10:
			continue
		if g.allied(c.id, o.id):
			continue
		if g.opinion(c.id, o.id) >= g.ALLIANCE_MIN_OPINION:
			g.alliances.append(g._pair(c.id, o.id))
			formed = true
			if g.is_human(tid):
				Events.notice.emit("%s e %s formam uma aliança." % [c.name, o.name])
		else:
			g.relations[g._pair(c.id, o.id)] = mini(100, g.opinion(c.id, o.id) + 3)

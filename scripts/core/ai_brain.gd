class_name AiBrain
extends RefCounted
## Cérebro estratégico da IA (V0.15). Ciclo mensal, sem estado próprio (tudo deriva do estado do
## jogo + dados estáticos de data/ai_profiles.json, então segue determinístico no P2P):
##   1. Avaliação nacional  - força própria (exata), reservas, estabilidade.
##   2. Interesses          - cada vizinho (e inimigos de protegidos) recebe um OBJETIVO de guerra,
##                            escolhido entre vários ramos: reconquista, unificação, reivindicação
##                            histórica, intervenção, rivalidade, estreitos, contenção do
##                            hegemon, oportunismo, recursos e expansão.
##   3. Preparação / defesa - recruta mais; se ameaçada por um vizinho forte e hostil, se arma e
##                            procura aliados.
##   4. Pressão diplomática - objetivos "frios" exigem tensão (relação abaixo de um limite) antes da
##                            guerra: a relação cai 3/mês e o jogador recebe avisos com o motivo.
## A IA NÃO enxerga o estado real do rival: estima a força por soldados e navios visíveis (sem
## tecnologia nem tesouro), com incerteza determinística. Ambição, ousadia e pesos por objetivo
## vêm da personalidade do país (inspirado nas "estratégias" e "desejos" de Victoria 3).

const GOALS := {
	"reclaim": {"label": "reconquistar territórios perdidos", "need": 90, "tension": 100},
	"unify": {"label": "unificar a nação", "need": 100, "tension": 100},
	"intervene": {"label": "intervir em defesa de um protegido", "need": 90, "tension": 100},
	"claim": {"label": "reivindicar território histórico", "need": 110, "tension": 0},
	"rivalry": {"label": "rivalidade regional", "need": 130, "tension": -30},
	"straits": {"label": "controlar passagens estratégicas", "need": 140, "tension": -20},
	"contain": {"label": "conter a potência dominante", "need": 100, "tension": -20},
	"opportunism": {"label": "explorar a fraqueza do vizinho", "need": 160, "tension": -10},
	"resources": {"label": "obter recursos estratégicos", "need": 200, "tension": -25},
	"expansion": {"label": "expansão territorial", "need": 220, "tension": -25},
}
const RARE := ["gold", "coal", "iron", "spices", "silk", "opium", "tea", "salt"]
const MAX_SPREAD := 45          # incerteza máxima (± %) sobre a força do rival
const MIN_SPREAD := 15
const CLAIM_PTS := 40           # motivo por província núcleo em mãos do rival
const PREP_MAX_BONUS := 4       # regimentos extras ao se preparar
const PRESSURE_BAND := 25       # % abaixo da razão exigida que ainda gera pressão
const RESERVE_MONTHS := 6       # reservas mínimas (meses de despesa) para iniciar guerra
const MIN_MOTIVE := 15          # abaixo disto o país não tem interesse em guerra

static var _profiles: Dictionary = {}
static var _loaded: bool = false


static func _noise(a: int, b: int, salt: int) -> int:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (salt * 83492791)
	h = h & 0x7fffffff
	return h % 201 - 100


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open("res://data/ai_profiles.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_profiles = parsed


## Personalidade do país: ambição, ousadia, pesos por objetivo, rivais, reivindicações, protegidos.
@warning_ignore("integer_division")
static func profile_of(c) -> Dictionary:
	_load()
	var d: Dictionary = {}
	if _profiles.has(c.tag):
		d = _profiles[c.tag]
	return {
		"ambition": int(d.get("ambition", 25 + (c.id * 37) % 25 + mini(15, c.province_ids.size() / 5))),
		"boldness": int(d.get("boldness", 40 + (c.id * 53) % 30)),
		"rivals": d.get("rivals", []),
		"claims": d.get("claims", []),
		"unify": d.get("unify", []),
		"protect": d.get("protect", []),
		"balance": bool(d.get("balance", false)),
		"weights": d.get("weights", {}),
	}


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


## Potência dominante: ≥160% do segundo e ≥250% da mediana. -1 se não há.
@warning_ignore("integer_division")
static func hegemon(g: Node) -> int:
	var pw: Array = []
	var top := -1
	var top_p := 0
	var second := 0
	for c in g.countries:
		if not c.is_alive():
			continue
		var p := own_power(g, c.id)
		pw.append(p)
		if p > top_p:
			second = top_p
			top_p = p
			top = c.id
		elif p > second:
			second = p
	if pw.size() < 4:
		return -1
	pw.sort()
	var median: int = int(pw[pw.size() / 2])
	if top_p * 100 >= second * 160 and top_p * 100 >= median * 250:
		return top
	return -1


## Deriva mensal do equilíbrio de poder: países "balance" passam a desconfiar do hegemon.
static func balance_drift(g: Node, c, heg: int) -> void:
	if heg < 0 or heg == c.id or not bool(profile_of(c)["balance"]):
		return
	if g.allied(c.id, heg) or g.at_war(c.id, heg):
		return
	var key: int = g._pair(c.id, heg)
	g.relations[key] = maxi(-60, g.opinion(c.id, heg) - 1)


static func _distracted(g: Node, t) -> bool:
	if int(t.stability) < 25:
		return true
	return not g.wars_of(t.id).is_empty() and (int(t.stability) < 40 or g.regiments_of(t.id) <= 2)


static func _has_tag(list: Variant, tag: String) -> bool:
	return list is Array and (list as Array).has(tag)


## Escolhe o objetivo de guerra de `c` contra `t`:
## {"goal","motive","need","tension"} (motive 0 = sem interesse).
@warning_ignore("integer_division")
static func evaluate(g: Node, c, t, heg: int, intervening: bool) -> Dictionary:
	var pr := profile_of(c)
	var w: Dictionary = pr["weights"]
	var scale: int = 50 + int(pr["ambition"])
	var op: int = g.opinion(c.id, t.id)
	var base := {}   # objetivo -> motivo bruto
	var cl := claims(g, c, t)
	if cl > 0:
		base["reclaim"] = mini(3, cl) * CLAIM_PTS
	if _has_tag(pr["unify"], t.tag):
		base["unify"] = 60
	if _has_tag(pr["claims"], t.tag):
		base["claim"] = 45
	if intervening:
		base["intervene"] = 50
	if _has_tag(pr["rivals"], t.tag):
		base["rivalry"] = 30
	elif op <= -40:
		base["rivalry"] = 30
	elif op <= -15:
		base["rivalry"] = 12
	if g.ports_of(c.id) > 0:
		for gi in g.gates.size():
			if g.gate_controller(gi) == t.id:
				base["straits"] = 25 + 5 * int(g.gates[gi].get("toll", 0))
	if t.id == heg and bool(pr["balance"]):
		base["contain"] = 40
	if _distracted(g, t):
		base["opportunism"] = 22
	var rare_n := 0
	for pid in t.province_ids:
		var rt: String = str(g.provinces[pid].resource_type)
		if RARE.has(rt) and not _owns_resource(g, c, rt):
			rare_n += 1
	if rare_n > 0:
		base["resources"] = mini(40, rare_n * 8)
	base["expansion"] = mini(45, 10 + t.province_ids.size() * 2)
	var best := {"goal": "", "motive": 0, "need": 0, "tension": 0}
	var keys: Array = base.keys()
	keys.sort()
	for k in keys:
		var m: int = int(base[k]) * int(w.get(k, 100)) / 100 * scale / 100
		if m > int(best["motive"]):
			var gd: Dictionary = GOALS[k]
			var need: int = int(gd["need"])
			if k == "reclaim":
				need = 75 if cl >= 2 else 90
			best = {"goal": k, "motive": m, "need": need, "tension": int(gd["tension"])}
	if int(best["motive"]) < MIN_MOTIVE:
		return {"goal": "", "motive": 0, "need": 0, "tension": 0}
	# Ousadia + ruído por par/ano: país ousado exige menos vantagem; o covarde, mais.
	var salt: int = int(g.clock.year)
	var adj: int = (50 - int(pr["boldness"])) * 3 / 10 + _noise(c.id, t.id, salt) * 8 / 100
	best["need"] = maxi(60, int(best["need"]) * (100 + adj) / 100)
	return best


static func _owns_resource(g: Node, c, rt: String) -> bool:
	for pid in c.province_ids:
		if str(g.provinces[pid].resource_type) == rt:
			return true
	return false


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


## Plano do mês: {"stage": none|defend|prepare|pressure|war, "target", "ratio", "motive", "goal"}.
@warning_ignore("integer_division")
static func plan(g: Node, c, heg: int) -> Dictionary:
	var best := {"stage": "none", "target": -1, "ratio": 0, "motive": 0, "goal": ""}
	if not g.wars_of(c.id).is_empty() or int(g.tick) < int(g.AI_WAR_GRACE_TICKS) or int(c.overlord) >= 0:
		return best
	var mine := own_power(g, c.id)
	var best_score := -1
	var pr := profile_of(c)
	# alvos: vizinhos + inimigos dos protegidos (intervenção)
	var targets := {}
	for o in neighbors(g, c):
		targets[int(o)] = false
	for cc in g.countries:
		if cc.id != c.id and cc.is_alive() and _has_tag(pr["protect"], cc.tag):
			for q in g.wars_of(cc.id):
				if int(q) != c.id and not g.allied(c.id, int(q)):
					targets[int(q)] = true
	var tkeys: Array = targets.keys()
	tkeys.sort()
	var threat := -1
	var threat_ratio := 0
	for o in tkeys:
		var t = g.countries[int(o)]
		if not t.is_alive():
			continue
		var seen := maxi(1, perceived_power(g, c.id, t.id))
		var ratio: int = mine * 100 / seen
		# ameaça defensiva: vizinho hostil bem mais forte
		if g.opinion(c.id, t.id) <= -15 and seen * 100 >= mine * 150 and seen > threat_ratio:
			threat = t.id
			threat_ratio = seen
		if not g.can_declare_war(c.id, t.id):
			continue
		var ev := evaluate(g, c, t, heg, bool(targets[int(o)]))
		var mot: int = int(ev["motive"])
		if mot <= 0:
			continue
		var need: int = int(ev["need"])
		var cold: bool = g.opinion(c.id, t.id) > int(ev["tension"])   # ainda sem tensão suficiente
		var stage := "none"
		if ratio >= need and ready_for_war(g, c):
			stage = "pressure" if cold else "war"
		elif ratio * 100 >= need * (100 - PRESSURE_BAND):
			stage = "pressure"
		elif (mine + PREP_MAX_BONUS * 100) * 100 / seen >= need:
			stage = "prepare"
		elif ratio >= need:
			stage = "prepare"   # forte o bastante, mas sem reservas: junta dinheiro
		if stage == "none":
			continue
		var rank: int = int({"war": 3, "pressure": 2, "prepare": 1}[stage])
		var score: int = rank * 100000 + mot * 100 + mini(ratio, 99)
		if score > best_score:
			best_score = score
			best = {"stage": stage, "target": t.id, "ratio": ratio, "motive": mot, "goal": str(ev["goal"])}
	if best_score < 0 and threat >= 0:
		best = {"stage": "defend", "target": threat, "ratio": 0, "motive": 0, "goal": ""}
	return best


## Regimentos extras desejados enquanto a IA se prepara.
static func recruit_bonus(plan_d: Dictionary) -> int:
	match str(plan_d["stage"]):
		"prepare":
			return 2
		"pressure", "war":
			return PREP_MAX_BONUS
		"defend":
			return 3
	return 0


static func goal_label(goal: String) -> String:
	if GOALS.has(goal):
		return str((GOALS[goal] as Dictionary)["label"])
	return "interesses estratégicos"


## Pressão diplomática: ameaça o alvo (relação cai), avisa o jogador e busca coalizão.
static func apply_pressure(g: Node, c, plan_d: Dictionary) -> void:
	var tid: int = int(plan_d["target"])
	if tid < 0:
		return
	if str(plan_d["goal"]) != "intervene":
		g.relations[g._pair(c.id, tid)] = maxi(-100, g.opinion(c.id, tid) - 3)
	if g.is_human(tid) and (int(g.clock.month) + c.id) % 3 == 0:
		Events.notice.emit("%s concentra tropas e faz exigências a você (%s)." % [c.name, goal_label(str(plan_d["goal"]))])
	court_allies(g, c, tid, g.is_human(tid))


## Corteja países que também desconfiam do alvo e forma uma aliança com quem já gosta de `c`.
static func court_allies(g: Node, c, tid: int, announce: bool) -> void:
	for o in g.countries:
		if o.id == c.id or o.id == tid or not o.is_alive():
			continue
		if g.allied(o.id, tid) or g.at_war(c.id, o.id) or g.opinion(o.id, tid) > -10 or g.allied(c.id, o.id):
			continue
		if g.opinion(c.id, o.id) >= g.ALLIANCE_MIN_OPINION:
			g.alliances.append(g._pair(c.id, o.id))
			if announce:
				Events.notice.emit("%s e %s formam uma aliança." % [c.name, o.name])
			return
		g.relations[g._pair(c.id, o.id)] = mini(100, g.opinion(c.id, o.id) + 3)

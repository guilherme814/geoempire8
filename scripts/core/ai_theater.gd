class_name AiTheater
extends RefCounted
## Teatros de guerra da IA: um teatro por país inimigo, com
##   enemy, region (províncias próprias na linha de contato + províncias inimigas vizinhas),
##   objective (província inimiga mais valiosa e alcançável), hold (ponto de contenção própria),
##   threat (regimentos inimigos na região), risk (valor próprio exposto, capital pesa muito),
##   priority, needed_off / needed_def (regimentos), assigned (regimentos), supply (pior
##   abastecimento atribuído), plan ("offensive" | "defensive" | "hold"), why e conditions.
## Os exércitos são atribuídos por prioridade: primeiro cobre-se a defesa mínima de cada teatro
## em ordem de prioridade, e o excedente (reserva) reforça o teatro ofensivo mais prioritário.
## Função pura do estado do jogo: sem rng, ids em ordem, sem estado guardado.

const CAPITAL_RISK := 300
const OFFENSE_MIN := 3


@warning_ignore("integer_division")
static func build(g: Node, c, doc: Dictionary, enemy_regs: Dictionary) -> Array:
	var theaters: Array = []
	var enemies: Array = g.wars_of(c.id)
	enemies.sort()
	for ev in enemies:
		var e: int = int(ev)
		if not g.countries[e].is_alive():
			continue
		var t := _theater_against(g, c, e, doc, enemy_regs)
		if not t.is_empty():
			theaters.append(t)
	theaters.sort_custom(func(x, y): return int(x["priority"]) > int(y["priority"]) or (int(x["priority"]) == int(y["priority"]) and int(x["enemy"]) < int(y["enemy"])))
	_assign(g, c, theaters, doc)
	return theaters


@warning_ignore("integer_division")
static func _theater_against(g: Node, c, e: int, doc: Dictionary, enemy_regs: Dictionary) -> Dictionary:
	var mine_front: Array = []
	var foe_front := {}
	for pid in c.province_ids:
		var p = g.provinces[pid]
		var touches := false
		for q in p.neighbors:
			if g.provinces[int(q)].owner_id == e:
				touches = true
				foe_front[int(q)] = true
		for q in p.sea_links:
			if g.provinces[int(q)].owner_id == e:
				touches = true
				foe_front[int(q)] = true
		if touches:
			mine_front.append(int(pid))
	if foe_front.is_empty():
		foe_front[int(g.countries[e].capital)] = true   # sem contato: mira a capital inimiga
	var threat := 0
	var risk := 0
	var capital_exposed := false
	var hold := -1
	var hold_score := -1
	for pid in mine_front:
		var p = g.provinces[pid]
		var near: int = int(enemy_regs.get(pid, 0)) + AiWar.ring_threat(g, pid, enemy_regs)
		threat += int(enemy_regs.get(pid, 0))
		var val: int = AiWar.province_value(g, p, c)
		if c.capital == pid:
			capital_exposed = true
			val += CAPITAL_RISK
		risk += val
		var hs: int = val + near * 20
		if hs > hold_score or (hs == hold_score and pid < hold):
			hold_score = hs
			hold = pid
	var fkeys: Array = foe_front.keys()
	fkeys.sort()
	var obj := -1
	var obj_s := -1000000
	var obj_garr := 0
	for q in fkeys:
		var garr: int = int(enemy_regs.get(int(q), 0))
		threat += garr
		var s: int = AiWar.province_value(g, g.provinces[int(q)], c) * int(doc["vm"]) / 100 - garr * int(doc["gc"])
		if int(g.countries[e].stability) < 40:
			s += int(doc["weak"])
		if s > obj_s:
			obj_s = s
			obj = int(q)
			obj_garr = garr
	var need_def: int = maxi(2, threat * 110 / 100)
	var need_off: int = maxi(OFFENSE_MIN, obj_garr * 130 / 100 + threat * 60 / 100 + 2)
	# vizinhança da capital: inimigo a 1 salto dela eleva a prioridade ao máximo
	var cap_near := 0
	if c.capital >= 0:
		cap_near = int(enemy_regs.get(int(c.capital), 0)) + AiWar.ring_threat(g, int(c.capital), enemy_regs)
	var prio: int = risk / 4 + threat * 15 + (obj_s if obj_s > 0 else 0) / 4 + cap_near * 40 + (CAPITAL_RISK if capital_exposed else 0)
	return {
		"enemy": e, "region": mine_front, "objective": obj, "hold": hold, "threat": threat, "risk": risk,
		"priority": prio, "needed_def": need_def, "needed_off": need_off, "assigned": 0, "supply": 100,
		"plan": "hold", "armies": [], "capital_exposed": capital_exposed, "why": "", "conditions": [],
	}


## Atribui exércitos aos teatros e define o plano de cada um.
@warning_ignore("integer_division")
static func _assign(g: Node, c, theaters: Array, doc: Dictionary) -> void:
	if theaters.is_empty():
		return
	var list: Array = []
	var ids: Array = g.armies.keys()
	ids.sort()
	for id in ids:
		var a = g.armies[id]
		if a.owner_id == c.id:
			list.append(a)
	list.sort_custom(func(x, y): return x.regiments > y.regiments or (x.regiments == y.regiments and x.id < y.id))
	# passo 1: defesa mínima, por prioridade (cada exército vai ao teatro de maior prioridade com déficit,
	# desde que esteja a distância razoável: usa o mais próximo entre os que têm déficit)
	var leftover: Array = []
	for a in list:
		var best := -1
		var best_d := INF
		for i in theaters.size():
			var t: Dictionary = theaters[i]
			if int(t["assigned"]) >= int(t["needed_def"]):
				continue
			var d: float = g.provinces[a.province_id].center.distance_to(g.provinces[int(t["hold"] if int(t["hold"]) >= 0 else t["objective"])].center)
			# prioridade vence distância: o teatro mais prioritário entra com folga de 40%
			d = d * (1.0 - minf(0.4, float(int(t["priority"])) / 5000.0))
			if best < 0 or (i == 0 and best != 0 and d < best_d * 2.5) or d < best_d:
				best = i
				best_d = d
		if best < 0:
			leftover.append(a)
			continue
		_give(theaters[best], a)
	# passo 2: reserva reforça o teatro com objetivo mais prioritário
	for a in leftover:
		var pick := 0
		for i in theaters.size():
			if int(theaters[i]["objective"]) >= 0:
				pick = i
				break
		_give(theaters[pick], a)
	for t in theaters:
		_decide_plan(g, c, t, doc)


static func _give(t: Dictionary, a) -> void:
	t["assigned"] = int(t["assigned"]) + a.regiments
	t["supply"] = mini(int(t["supply"]), a.supply)
	(t["armies"] as Array).append(a.id)


@warning_ignore("integer_division")
static func _decide_plan(g: Node, c, t: Dictionary, doc: Dictionary) -> void:
	var conds: Array = []
	var ratio: int = int(t["assigned"]) * 100 / maxi(1, int(t["needed_off"]))
	var plan := "hold"
	var why := ""
	if int(t["assigned"]) == 0:
		plan = "hold"
		why = "sem tropas atribuídas"
	elif int(t["supply"]) < int(doc["supply"]):
		plan = "defensive"
		why = "logística crítica (%d%%)" % int(t["supply"])
	elif ratio >= int(doc["offense"]) and int(t["objective"]) >= 0:
		plan = "offensive"
		why = "tropas %d%% do necessário (limite %d%%)" % [ratio, int(doc["offense"])]
	elif int(t["threat"]) > 0 or bool(t["capital_exposed"]):
		plan = "defensive"
		why = "ameaça de %d regimento(s)" % int(t["threat"])
	else:
		why = "frente tranquila"
	conds.append("vai à ofensiva com %d%% das tropas necessárias" % int(doc["offense"]))
	conds.append("recua se o inimigo local ≥ %d%% do exército" % int(doc["retreat"]))
	conds.append("suspende avanço com suprimento < %d%%" % int(doc["supply"]))
	t["plan"] = plan
	t["why"] = why
	t["conditions"] = conds


static func theater_for(theaters: Array, army_id: int) -> Dictionary:
	for t in theaters:
		if (t["armies"] as Array).has(army_id):
			return t
	return {}

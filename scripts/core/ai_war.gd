class_name AiWar
extends RefCounted
## Camada OPERACIONAL da IA em guerra (utility AI), subordinada aos TEATROS (AiTheater).
## Cada exército pesa, nesta ordem:
##   1. Autopreservação - recua diante de força superior, de vizinhança esmagadora ou com
##                        suprimentos críticos (para um aliado forte ou para a retaguarda).
##   2. Concentração    - exércitos pequenos se juntam a um maior próximo.
##   3. Defesa          - expulsa invasores da própria terra quando tem vantagem.
##   4. Missão do teatro- ofensiva ao objetivo do teatro, ou defesa do ponto de contenção,
##                        ou manutenção de posição, conforme o plano do teatro.
## A DOUTRINA do comandante (personalidade militar) altera limiares, pesos de alvo e plano.
## Sem estado próprio e sem rng: determinístico no P2P. O motivo da ordem fica em
## Game.ai_notes (só exibição; fora do save e do hash).

const SUPPLY_CRITICAL := 35
const HOP_COST := 8
const CONCENTRATE_HOPS := 3

## Doutrinas: retreat/ring (% do meu exército que o inimigo precisa ter para eu recuar),
## supply (suprimento mínimo), below (exércitos menores que isto se juntam a outro),
## attack (% mínimo do inimigo que aceito enfrentar), garrison (guarnição máxima aceita num alvo,
## % do meu exército), offense (% das tropas necessárias para o teatro ir à ofensiva),
## gc (custo por regimento de guarnição na pontuação do alvo), vm (peso do valor do alvo, %),
## weak (bônus por inimigo fragilizado), stand (defesa teimosa: não abandona o ponto de contenção).
const PERSONALITIES := {
	"aggressive": {"label": "agressivo", "retreat": 200, "ring": 260, "supply": 25, "below": 2, "attack": 60, "garrison": 180, "offense": 80, "gc": 25, "vm": 100, "weak": 0, "stand": false},
	"cautious": {"label": "cauteloso", "retreat": 120, "ring": 160, "supply": 45, "below": 6, "attack": 100, "garrison": 100, "offense": 140, "gc": 45, "vm": 100, "weak": 0, "stand": false},
	"defensive": {"label": "defensivo", "retreat": 140, "ring": 180, "supply": 40, "below": 5, "attack": 70, "garrison": 110, "offense": 170, "gc": 40, "vm": 80, "weak": 0, "stand": true},
	"opportunist": {"label": "oportunista", "retreat": 150, "ring": 200, "supply": 35, "below": 3, "attack": 80, "garrison": 130, "offense": 100, "gc": 70, "vm": 100, "weak": 40, "stand": false},
	"strategic": {"label": "estratégico", "retreat": 140, "ring": 190, "supply": 40, "below": 5, "attack": 85, "garrison": 120, "offense": 115, "gc": 35, "vm": 150, "weak": 10, "stand": false},
}
const CHAOS_POOL := ["aggressive", "cautious", "opportunist", "strategic", "defensive"]


## Chave da personalidade EFETIVA do comandante. "unpredictable" muda de tempos em tempos
## (determinístico por país e semestre): sorteia uma das outras a cada ~6 meses.
@warning_ignore("integer_division")
static func personality_key(g: Node, c) -> String:
	var pr := AiBrain.profile_of(c)
	var k: String = str(pr.get("doctrine", ""))
	if k == "":
		var b: int = int(pr["boldness"])
		if b < 35:
			k = "cautious"
		elif b > 65:
			k = "aggressive"
		else:
			k = ["strategic", "opportunist", "defensive"][c.id % 3]
	if k == "unpredictable":
		var semester: int = int(g.clock.year) * 2 + int(g.clock.month) / 7
		var h: int = ((c.id + 1) * 73856093) ^ (semester * 19349663)
		k = CHAOS_POOL[(h & 0x7fffffff) % CHAOS_POOL.size()]
	return k


static func doctrine(key: String) -> Dictionary:
	var d: Dictionary = PERSONALITIES.get(key, PERSONALITIES["strategic"])
	var out := d.duplicate()
	out["key"] = key
	return out


static func doctrine_of(g: Node, c) -> Dictionary:
	return doctrine(personality_key(g, c))


## Pura: o exército deve recuar? (inimigo na própria província e na vizinhança).
static func should_retreat(mine: int, enemy_here: int, enemy_ring: int, supply: int, doc: Dictionary = {}) -> bool:
	var d: Dictionary = doc if not doc.is_empty() else doctrine("strategic")
	if supply < int(d["supply"]):
		return true
	if enemy_here > 0 and enemy_here * 100 >= mine * int(d["retreat"]):
		return true
	return enemy_ring > 0 and enemy_ring * 100 >= mine * int(d["ring"])


## Pura: pontuação de um alvo ofensivo segundo a doutrina.
static func target_score(value: int, hops: int, garrison: int, doc: Dictionary = {}) -> int:
	var d: Dictionary = doc if not doc.is_empty() else doctrine("strategic")
	return value * int(d["vm"]) / 100 - hops * HOP_COST - garrison * int(d["gc"])


## Valor estratégico de uma província para o comandante `c` (inimiga ou própria).
static func province_value(g: Node, p, c) -> int:
	var v := 20
	if int(p.core_owner) == c.id:
		v += 50
	if p.owner_id >= 0 and g.countries[p.owner_id].capital == p.id:
		v += 90
	if int(p.port) >= 0:
		v += 30
	if AiBrain.RARE.has(str(p.resource_type)):
		v += 25
	return v


static func regs_by_province(g: Node, owners: Array) -> Dictionary:
	var out := {}
	var ids: Array = g.armies.keys()
	ids.sort()
	for id in ids:
		var e = g.armies[id]
		if owners.has(e.owner_id):
			out[e.province_id] = int(out.get(e.province_id, 0)) + e.regiments
	return out


static func ring_threat(g: Node, pid: int, regs: Dictionary) -> int:
	var n := 0
	for q in g.provinces[pid].neighbors:
		n += int(regs.get(int(q), 0))
	return n


static func path_len(g: Node, from_id: int, to_id: int) -> int:
	if from_id == to_id:
		return 0
	var path: Array = g.find_path(from_id, to_id)
	return path.size() - 1 if not path.is_empty() else -1


static func _fallback(g: Node, a, c, own_regs: Dictionary, enemy_regs: Dictionary) -> int:
	var origin: Vector2 = g.provinces[a.province_id].center
	var best := -1
	var best_d := INF
	for pid in own_regs.keys():
		if int(pid) == a.province_id or int(own_regs[pid]) < a.regiments:
			continue
		if int(enemy_regs.get(int(pid), 0)) > 0:
			continue
		var d: float = origin.distance_squared_to(g.provinces[int(pid)].center)
		if d < best_d:
			best_d = d
			best = int(pid)
	if best >= 0:
		return best
	for pid in c.province_ids:
		if g._supply_range_at(int(pid), c.id) <= 0 or int(pid) == a.province_id:
			continue
		if int(enemy_regs.get(int(pid), 0)) > 0:
			continue
		var d2: float = origin.distance_squared_to(g.provinces[int(pid)].center)
		if d2 < best_d:
			best_d = d2
			best = int(pid)
	return best


static func _go(g: Node, a, dest: int, why: String) -> void:
	if dest < 0 or dest == a.province_id:
		return
	g._order_move(a, dest)
	g.ai_notes[a.id] = why


## Decide as ordens de todos os exércitos parados de `c` (ids crescentes).
## `force_doc` (opcional, testes) força uma doutrina.
static func think(g: Node, c, force_doc: String = "") -> void:
	var enemies: Array = g.wars_of(c.id)
	var doc := doctrine(force_doc) if force_doc != "" else doctrine_of(g, c)
	var enemy_regs := regs_by_province(g, enemies)
	var own_regs := {}
	var ids: Array = g.armies.keys()
	ids.sort()
	for id in ids:
		var o = g.armies[id]
		if o.owner_id == c.id and not o.is_moving():
			own_regs[o.province_id] = int(own_regs.get(o.province_id, 0)) + o.regiments
	var theaters: Array = AiTheater.build(g, c, doc, enemy_regs)
	g.ai_theaters[c.id] = theaters
	for id in ids:
		if not g.armies.has(id):
			continue
		var a = g.armies[id]
		if a.owner_id != c.id or a.is_moving():
			continue
		var here = g.provinces[a.province_id]
		if here.owner_id != c.id and g.sieges.has(here.id) and int(g.sieges[here.id]["by"]) == c.id:
			g.ai_notes[a.id] = "Sitiando %s" % here.name
			continue
		var mine: int = int(own_regs.get(a.province_id, a.regiments))
		var eh: int = int(enemy_regs.get(a.province_id, 0))
		var ring: int = ring_threat(g, a.province_id, enemy_regs)
		# 1) autopreservação
		if should_retreat(mine, eh, ring, a.supply, doc):
			var fb := _fallback(g, a, c, own_regs, enemy_regs)
			if fb >= 0:
				_go(g, a, fb, "Recuando: suprimentos críticos" if a.supply < int(doc["supply"]) else "Recuando: inimigo superior")
				if a.is_moving():
					continue
		if eh > 0 and eh * 100 >= mine * int(doc["retreat"]):
			continue   # sem rota de fuga: luta onde está
		# 2) concentração
		if mine < int(doc["below"]) and ring == 0 and eh == 0:
			var join := _join_target(g, a, own_regs, enemy_regs)
			if join >= 0:
				_go(g, a, join, "Juntando forças")
				if a.is_moving():
					continue
		# 3) defesa: invasor em terra própria
		var inv := _invader(g, a, c, enemy_regs, mine, doc)
		if inv >= 0:
			_go(g, a, inv, "Expulsando invasor")
			if a.is_moving():
				continue
		# 4) missão do teatro
		var th: Dictionary = AiTheater.theater_for(theaters, a.id)
		if th.is_empty():
			g.ai_notes[a.id] = "Sem teatro de operações"
			continue
		_execute_mission(g, a, c, th, enemy_regs, mine, doc)


static func _execute_mission(g: Node, a, c, th: Dictionary, enemy_regs: Dictionary, mine: int, doc: Dictionary) -> void:
	var tag: String = "Teatro %s [%s]" % [g.countries[int(th["enemy"])].name, str(th["plan"])]
	match str(th["plan"]):
		"offensive":
			var obj: int = int(th["objective"])
			var okay: bool = obj >= 0 and a.supply >= int(doc["supply"]) \
				and int(enemy_regs.get(obj, 0)) * 100 <= mine * int(doc["garrison"])
			if okay:
				_go(g, a, obj, "%s: avançando sobre %s" % [tag, g.provinces[obj].name])
				return
			var alt := best_target(g, a, c, g.wars_of(c.id), enemy_regs, mine, doc)
			if alt >= 0:
				_go(g, a, alt, "%s: alvo alternativo %s" % [tag, g.provinces[alt].name])
				return
			g.ai_notes[a.id] = "%s: aguardando reforços" % tag
		"defensive":
			var hold: int = int(th["hold"])
			if hold >= 0 and hold != a.province_id:
				_go(g, a, hold, "%s: defendendo %s" % [tag, g.provinces[hold].name])
			else:
				g.ai_notes[a.id] = "%s: mantendo a linha" % tag
		_:
			g.ai_notes[a.id] = "%s: vigilância" % tag


static func _join_target(g: Node, a, own_regs: Dictionary, enemy_regs: Dictionary) -> int:
	var origin: Vector2 = g.provinces[a.province_id].center
	var cands: Array = []
	for pid in own_regs.keys():
		if int(pid) == a.province_id or int(own_regs[pid]) < a.regiments:
			continue
		cands.append({"id": int(pid), "d": origin.distance_squared_to(g.provinces[int(pid)].center)})
	cands.sort_custom(func(x, y): return x["d"] < y["d"] or (x["d"] == y["d"] and x["id"] < y["id"]))
	for i in mini(cands.size(), 3):
		var pid: int = int(cands[i]["id"])
		if int(enemy_regs.get(pid, 0)) > 0:
			continue
		var n := path_len(g, a.province_id, pid)
		if n > 0 and n <= CONCENTRATE_HOPS:
			return pid
	return -1


static func _invader(g: Node, a, c, enemy_regs: Dictionary, mine: int, doc: Dictionary) -> int:
	var origin: Vector2 = g.provinces[a.province_id].center
	var best := -1
	var best_d := INF
	var keys: Array = enemy_regs.keys()
	keys.sort()
	for pid in keys:
		if g.provinces[int(pid)].owner_id != c.id:
			continue
		if int(enemy_regs[pid]) * 100 > mine * 100 * 100 / int(doc["attack"]):
			continue
		var d: float = origin.distance_squared_to(g.provinces[int(pid)].center)
		if d < best_d:
			best_d = d
			best = int(pid)
	return best


static func best_target(g: Node, a, c, enemies: Array, enemy_regs: Dictionary, mine: int, doc: Dictionary) -> int:
	var origin: Vector2 = g.provinces[a.province_id].center
	var cands: Array = []
	for p in g.provinces:
		if enemies.has(p.owner_id):
			var garr: int = int(enemy_regs.get(p.id, 0))
			if garr * 100 > mine * int(doc["garrison"]):
				continue
			cands.append({"id": p.id, "d": origin.distance_squared_to(p.center) / maxf(1.0, float(province_value(g, p, c)) / 40.0)})
	cands.sort_custom(func(x, y): return x["d"] < y["d"] or (x["d"] == y["d"] and x["id"] < y["id"]))
	var best := -1
	var best_s := -1000000
	for i in mini(cands.size(), 6):
		var pid: int = int(cands[i]["id"])
		var hops := path_len(g, a.province_id, pid)
		if hops < 0:
			continue
		var s := target_score(province_value(g, g.provinces[pid], c), hops, int(enemy_regs.get(pid, 0)), doc)
		if s > best_s:
			best_s = s
			best = pid
	return best

class_name AiWar
extends RefCounted
## Camada OPERACIONAL da IA em guerra (utility AI). A estratégia (AiBrain) decide QUEM atacar e
## POR QUÊ; esta camada decide o que cada exército FAZ, pesando riscos como um comandante:
##   1. Autopreservação - não luta em desvantagem clara: recua para um exército aliado ou para a
##                        retaguarda (capital/depósito); suprimentos críticos também mandam recuar.
##   2. Concentração    - exércitos pequenos se juntam a um maior próximo, em vez de morrer sozinhos.
##   3. Defesa          - expulsa invasores da própria terra quando tem vantagem.
##   4. Ofensiva        - pontua alvos por valor (capital, núcleo, porto, recurso raro) menos
##                        distância e guarnição, e evita alvos fortes demais.
## Sem estado próprio: tudo é recalculado do estado do jogo (determinístico no P2P). Cada decisão
## deixa um motivo em Game.ai_notes (só exibição; fora do hash e do save).

const RETREAT_RATIO := 150         # recua se o inimigo local >= 150% do meu exército
const RING_RATIO := 200            # recua se a vizinhança tem >= 200% do meu exército
const SUPPLY_CRITICAL := 35
const CONCENTRATE_BELOW := 4       # exércitos menores que isto procuram um maior
const CONCENTRATE_HOPS := 3
const ATTACK_MIN_PCT := 80         # ataca invasor/alvo se meu exército >= 80% do dele
const GARRISON_SKIP_PCT := 130     # ignora alvo guarnecido com > 130% do meu exército
const HOP_COST := 8
const GARRISON_COST := 35


## Pura: o exército deve recuar? (inimigo na própria província e na vizinhança).
static func should_retreat(mine: int, enemy_here: int, enemy_ring: int, supply: int) -> bool:
	if supply < SUPPLY_CRITICAL:
		return true
	if enemy_here > 0 and enemy_here * 100 >= mine * RETREAT_RATIO:
		return true
	return enemy_ring > 0 and enemy_ring * 100 >= mine * RING_RATIO


## Pura: pontuação de um alvo ofensivo.
static func target_score(value: int, hops: int, garrison: int) -> int:
	return value - hops * HOP_COST - garrison * GARRISON_COST


## Valor estratégico de uma província inimiga para o comandante.
static func province_value(g: Node, p, c) -> int:
	var v := 20
	if int(p.core_owner) == c.id:
		v += 50
	if g.countries[p.owner_id].capital == p.id:
		v += 90
	if int(p.port) >= 0:
		v += 30
	if AiBrain.RARE.has(str(p.resource_type)):
		v += 25
	return v


static func _regs_by_province(g: Node, owners: Array) -> Dictionary:
	var out := {}
	var ids: Array = g.armies.keys()
	ids.sort()
	for id in ids:
		var e = g.armies[id]
		if owners.has(e.owner_id):
			out[e.province_id] = int(out.get(e.province_id, 0)) + e.regiments
	return out


static func _ring(g: Node, pid: int, regs: Dictionary) -> int:
	var n := 0
	for q in g.provinces[pid].neighbors:
		n += int(regs.get(int(q), 0))
	return n


static func _path_len(g: Node, from_id: int, to_id: int) -> int:
	if from_id == to_id:
		return 0
	var path: Array = g.find_path(from_id, to_id)
	return path.size() - 1 if not path.is_empty() else -1


## Província segura para recuar: exército aliado parado mais próximo e forte; senão a fonte de
## suprimentos (capital/depósito) mais próxima.
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
@warning_ignore("integer_division")
static func think(g: Node, c) -> void:
	var enemies: Array = g.wars_of(c.id)
	var enemy_regs := _regs_by_province(g, enemies)
	var own_regs := {}
	var ids: Array = g.armies.keys()
	ids.sort()
	for id in ids:
		var o = g.armies[id]
		if o.owner_id == c.id and not o.is_moving():
			own_regs[o.province_id] = int(own_regs.get(o.province_id, 0)) + o.regiments
	for id in ids:
		if not g.armies.has(id):
			continue
		var a = g.armies[id]
		if a.owner_id != c.id or a.is_moving():
			continue
		var here = g.provinces[a.province_id]
		# mantém o cerco em andamento
		if here.owner_id != c.id and g.sieges.has(here.id) and int(g.sieges[here.id]["by"]) == c.id:
			g.ai_notes[a.id] = "Sitiando %s" % here.name
			continue
		var mine: int = int(own_regs.get(a.province_id, a.regiments))
		var eh: int = int(enemy_regs.get(a.province_id, 0))
		var ring: int = _ring(g, a.province_id, enemy_regs)
		# 1) autopreservação
		if should_retreat(mine, eh, ring, a.supply):
			var fb := _fallback(g, a, c, own_regs, enemy_regs)
			if fb >= 0:
				var why := "Recuando: suprimentos críticos" if a.supply < SUPPLY_CRITICAL else "Recuando: inimigo superior"
				_go(g, a, fb, why)
				if a.is_moving():
					continue
		if eh > 0 and eh * 100 >= mine * RETREAT_RATIO:
			continue   # sem rota de fuga: luta onde está
		# 2) concentração
		if mine < CONCENTRATE_BELOW and ring == 0 and eh == 0:
			var join := _join_target(g, a, own_regs, enemy_regs)
			if join >= 0:
				_go(g, a, join, "Juntando forças")
				if a.is_moving():
					continue
		# 3) defesa: invasor em terra própria
		var inv := _invader(g, a, c, enemy_regs, mine)
		if inv >= 0:
			_go(g, a, inv, "Expulsando invasor")
			if a.is_moving():
				continue
		# 4) ofensiva
		var t := _best_target(g, a, c, enemies, enemy_regs, mine)
		if t >= 0:
			_go(g, a, t, "Avançando sobre %s" % g.provinces[t].name)
		else:
			g.ai_notes[a.id] = "Mantendo posição"


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
		var n := _path_len(g, a.province_id, pid)
		if n > 0 and n <= CONCENTRATE_HOPS:
			return pid
	return -1


static func _invader(g: Node, a, c, enemy_regs: Dictionary, mine: int) -> int:
	var origin: Vector2 = g.provinces[a.province_id].center
	var best := -1
	var best_d := INF
	var keys: Array = enemy_regs.keys()
	keys.sort()
	for pid in keys:
		if g.provinces[int(pid)].owner_id != c.id:
			continue
		if int(enemy_regs[pid]) * 100 > mine * 100 * 100 / ATTACK_MIN_PCT:
			continue   # forte demais
		var d: float = origin.distance_squared_to(g.provinces[int(pid)].center)
		if d < best_d:
			best_d = d
			best = int(pid)
	return best


static func _best_target(g: Node, a, c, enemies: Array, enemy_regs: Dictionary, mine: int) -> int:
	var origin: Vector2 = g.provinces[a.province_id].center
	var cands: Array = []
	for p in g.provinces:
		if enemies.has(p.owner_id):
			var garr: int = int(enemy_regs.get(p.id, 0))
			if garr * 100 > mine * GARRISON_SKIP_PCT:
				continue
			cands.append({"id": p.id, "d": origin.distance_squared_to(p.center) / maxf(1.0, float(province_value(g, p, c)) / 40.0)})
	cands.sort_custom(func(x, y): return x["d"] < y["d"] or (x["d"] == y["d"] and x["id"] < y["id"]))
	var best := -1
	var best_s := -1000000
	for i in mini(cands.size(), 6):
		var pid: int = int(cands[i]["id"])
		var hops := _path_len(g, a.province_id, pid)
		if hops < 0:
			continue
		var s := target_score(province_value(g, g.provinces[pid], c), hops, int(enemy_regs.get(pid, 0)))
		if s > best_s:
			best_s = s
			best = pid
	return best

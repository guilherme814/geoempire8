class_name AiDiplomacy
extends RefCounted
## Negociação de paz da IA. Mede o "cansaço de guerra" (0..100+) a partir de pontuação,
## capital, exércitos, tesouro/estabilidade e duração; com isso decide (a) se aceita os termos
## propostos pelo jogador e (b) se oferece paz ao jogador, e em quais termos.
## Só lê o estado do jogo (sem rng): cada par de jogadores chega às mesmas ofertas.

const OFFER_DAYS := 60          # validade de uma oferta
const REFUSE_COOLDOWN := 90     # dias sem nova oferta após uma recusa
const SEEK_PEACE_W := 35        # cansaço mínimo para a IA buscar a paz
const NEED_W := {"white": 15, "indemnity": 30, "vassal": 55, "annex": 70}


## Cansaço de guerra de `ai` contra `foe`: quanto maior, mais disposta a ceder/negociar.
@warning_ignore("integer_division")
static func weariness(g: Node, ai: int, foe: int) -> int:
	var c = g.countries[ai]
	var s_ai: int = g.war_score(ai, foe)
	var s_foe: int = g.war_score(foe, ai)
	var w: int = clampi(s_foe - s_ai, -50, 100)
	if int(c.capital) >= 0 and int(g.provinces[int(c.capital)].owner_id) != ai:
		w += 25
	var ra: int = g.regiments_of(ai)
	var rf: int = g.regiments_of(foe)
	if ra * 2 < rf:
		w += 20
	elif ra < rf:
		w += 8
	elif ra > rf * 2:
		w -= 10
	var net: int = int(c.last_income) - int(c.last_expense)
	if int(c.treasury) < 0:
		w += 20
	elif net < 0 and int(c.treasury) < -net * 4:
		w += 12
	if int(c.stability) < 30:
		w += 15
	elif int(c.stability) < 45:
		w += 6
	var days: int = g.war_days(ai, foe)
	if days > 720:
		w += 20
	elif days > 360:
		w += 10
	if s_ai <= 5 and s_foe <= 5 and days >= 180:
		w += 15   # impasse prolongado
	# objetivo ainda vivo: o inimigo ocupa províncias que são núcleo da IA
	var held := 0
	for pid in g.countries[foe].province_ids:
		if int(g.provinces[pid].core_owner) == ai:
			held += 1
	w -= mini(20, held * 10)
	return w


static func willingness(g: Node, ai: int, foe: int) -> String:
	var w := weariness(g, ai, foe)
	if w >= 55:
		return "alta"
	if w >= SEEK_PEACE_W:
		return "média"
	return "baixa"


## A IA (perdedora) aceita os termos que o vencedor `winner` propôs?
static func accepts(g: Node, ai: int, winner: int, term: String) -> bool:
	return weariness(g, ai, winner) >= int(NEED_W.get(term, 100))


static func has_offer(g: Node, a: int, b: int) -> bool:
	for o in g.peace_offers:
		if (int(o["from"]) == a and int(o["to"]) == b) or (int(o["from"]) == b and int(o["to"]) == a):
			return true
	return false


## Revisão periódica (mensal) de uma IA: oferece paz aos jogadores com quem está em guerra.
static func review(g: Node, ai) -> void:
	for foe in g.wars_of(ai.id):
		var f: int = int(foe)
		if not g.is_human(f) or has_offer(g, ai.id, f):
			continue
		if int(g.peace_cd.get(g._pair(ai.id, f), 0)) > int(g.tick) or not g.can_make_peace(ai.id, f):
			continue
		var w := weariness(g, ai.id, f)
		var s_ai: int = g.war_score(ai.id, f)
		var s_f: int = g.war_score(f, ai.id)
		var winner := -1
		var term := ""
		if w >= SEEK_PEACE_W:
			if s_f > s_ai:
				winner = f   # a IA está perdendo: pede paz cedendo
				if w >= 80 and s_f >= g.SCORE_VASSAL and g.can_peace_term(f, ai.id, "vassal"):
					term = "vassal"
				elif s_f >= g.SCORE_INDEMNITY and g.can_peace_term(f, ai.id, "indemnity"):
					term = "indemnity"
				else:
					term = "white"
			else:
				# vantagem no campo, mas a economia/estabilidade não aguenta mais
				winner = ai.id
				term = "indemnity" if s_ai >= g.SCORE_INDEMNITY and g.can_peace_term(ai.id, f, "indemnity") else "white"
		elif s_ai >= g.SCORE_VASSAL and s_ai > s_f + 20 and g.war_days(ai.id, f) >= 90 \
				and g.can_peace_term(ai.id, f, "vassal"):
			winner = ai.id   # potência dominante dita os termos
			term = "vassal"
		if term == "" or winner < 0:
			continue
		if winner == ai.id and not g.can_peace_term(ai.id, f, term):
			continue
		g.peace_offers.append({"from": ai.id, "to": f, "winner": winner, "term": term, "tick": int(g.tick)})
		Events.notice.emit("%s propõe a paz: veja a proposta." % ai.name)
		Events.war_changed.emit()


# ---------------------------------------------------------------------------
# Convocação de aliados e coalizões (GEAI). Roda ao começar uma guerra.
# ---------------------------------------------------------------------------
const RALLY_MAX_PER_SIDE := 3
const ALLY_NEED := {"aggressive": 40, "opportunist": 45, "strategic": 55, "cautious": 70, "defensive": 85}


## Pura: um aliado do atacante entra na guerra? Precisa estar pronto e gostar do atacante o
## bastante; interesse próprio no alvo (motivo > 0) baixa a exigência.
static func ally_joins(pers: String, opinion: int, ready: bool, motive: int) -> bool:
	if not ready:
		return false
	var need: int = int(ALLY_NEED.get(pers, 60))
	if motive > 0:
		need -= 15
	return opinion >= need


## Pura: uma potência neutra entra ao lado do alvo para conter um agressor muito mais forte?
## Só estratégicos e países de "equilíbrio de poder"; cautelosos nunca. `ratio` = poder do
## agressor / poder do alvo (%).
static func coalition_joins(pers: String, balance: bool, op_target: int, op_aggressor: int, ratio: int, ready: bool) -> bool:
	if not ready or pers == "cautious":
		return false
	if not (balance or pers == "strategic"):
		return false
	return ratio >= 150 and op_target >= -10 and op_aggressor <= 20


static func _join(g: Node, o: int, enemy: int, other_side: int, why: String) -> void:
	g.wars.append(g._new_war(o, enemy))
	g.relations[g._pair(o, enemy)] = mini(g.opinion(o, enemy), -60)
	if g.is_human(enemy) or g.is_human(other_side):
		Events.notice.emit("%s entra na guerra %s." % [g.countries[o].name, why])


## Aliados do atacante e coalizões contra um agressor. Determinístico: países em ordem de id.
static func rally(g: Node, attacker: int, target: int) -> void:
	var on_att := 0
	var on_def := 0
	var ratio: int = AiBrain.own_power(g, attacker) * 100 / maxi(1, AiBrain.own_power(g, target))
	for o in g.countries:
		if o.id == attacker or o.id == target or not o.is_alive() or g.is_human(o.id) or int(o.overlord) >= 0:
			continue
		if g.at_war(o.id, attacker) or g.at_war(o.id, target) or g.wars_of(o.id).size() >= 2:
			continue
		var pers: String = AiWar.personality_key(g, o)
		var ready: bool = AiBrain.ready_for_war(g, o)
		if g.allied(o.id, attacker) and not g.allied(o.id, target):
			if on_att >= RALLY_MAX_PER_SIDE or not g.can_declare_war(o.id, target):
				continue
			var ev: Dictionary = AiBrain.evaluate(g, o, g.countries[target], -1, false)
			if ally_joins(pers, g.opinion(o.id, attacker), ready, int(ev["motive"])):
				_join(g, o.id, target, attacker, "ao lado de %s" % g.countries[attacker].name)
				on_att += 1
		elif not g.allied(o.id, attacker) and not g.allied(o.id, target) and not g.has_cb(attacker, target):
			if on_def >= RALLY_MAX_PER_SIDE or not g.can_declare_war(o.id, attacker):
				continue
			var bal: bool = bool(AiBrain.profile_of(o)["balance"])
			if coalition_joins(pers, bal, g.opinion(o.id, target), g.opinion(o.id, attacker), ratio, ready):
				_join(g, o.id, attacker, target, "para conter %s" % g.countries[attacker].name)
				on_def += 1

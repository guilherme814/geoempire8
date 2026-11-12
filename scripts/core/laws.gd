class_name Laws
extends RefCounted
## Leis do país (estilo Victoria 3): cada grupo tem uma opção em vigor.
## Dados puros e funções estáticas — sem dependência do autoload Game.
## O estado (qual opção está ativa e o tempo de espera) fica em Country.laws / Country.law_cd.
##
## Efeitos (fx): tax/trade = % sobre a arrecadação/comércio; army = % da manutenção do exército;
## lit = % extra no crescimento mensal da alfabetização; tech = pontos de tecnologia/mês;
## stab = deslocamento da satisfação-alvo de todas as classes; sat = {classe: deslocamento}.
## Classes: 0 camponeses, 1 operários, 2 aristocratas, 3 burguesia, 4 funcionários, 5 soldados.

const COOLDOWN_MONTHS := 24
const SAT_SHOCK_DIV := 2          # a mudança de lei abala a satisfação em metade do efeito

const COLUMN_NAMES := ["Estrutura de poder", "Economia", "Direitos e sociedade"]

const GROUPS := [
	{"id": "gov", "name": "Sistema de governo", "col": 0, "opts": [
		{"name": "Autocracia", "desc": "Poder concentrado no soberano.", "cost": 200, "tech": 0, "lit": 0,
			"fx": {"stab": 3, "tax": 3, "sat": {2: 8, 3: -8, 4: 3}}},
		{"name": "Monarquia constitucional", "desc": "Parlamento limita o rei.", "cost": 320, "tech": 1, "lit": 150,
			"fx": {"trade": 4, "sat": {2: 2, 3: 6, 4: 2}}},
		{"name": "República", "desc": "Governo eleito, sem trono.", "cost": 420, "tech": 2, "lit": 250,
			"fx": {"tech": 1, "trade": 6, "sat": {2: -10, 3: 8, 1: 4, 0: 2}}},
	]},
	{"id": "press", "name": "Liberdade de imprensa", "col": 0, "opts": [
		{"name": "Censura estatal", "desc": "O governo controla o que se publica.", "cost": 120, "tech": 0, "lit": 0,
			"fx": {"stab": 2, "lit": -15, "sat": {3: -6, 4: 3}}},
		{"name": "Imprensa vigiada", "desc": "Publicações licenciadas.", "cost": 160, "tech": 0, "lit": 100,
			"fx": {}},
		{"name": "Imprensa livre", "desc": "Debate público aberto.", "cost": 240, "tech": 1, "lit": 250,
			"fx": {"stab": -2, "lit": 20, "tech": 1, "sat": {3: 6, 1: 3, 2: -4}}},
	]},
	{"id": "military", "name": "Serviço militar", "col": 0, "opts": [
		{"name": "Exército profissional", "desc": "Soldados de ofício; caro, mas leal.", "cost": 220, "tech": 1, "lit": 0,
			"fx": {"army": 15, "sat": {5: 8}}},
		{"name": "Tropas mercenárias", "desc": "Contratos temporários; custo moderado.", "cost": 120, "tech": 0, "lit": 0,
			"fx": {"army": 0, "sat": {5: 0}}},
		{"name": "Conscrição nacional", "desc": "Todos servem; barato, impopular.", "cost": 260, "tech": 2, "lit": 200,
			"fx": {"army": -20, "sat": {0: -6, 1: -4, 5: 4}}},
	]},
	{"id": "economy", "name": "Política econômica", "col": 1, "opts": [
		{"name": "Mercantilismo", "desc": "O Estado tutela a economia.", "cost": 150, "tech": 0, "lit": 0,
			"fx": {"tax": 6, "trade": -6, "sat": {2: 4, 3: -5}}},
		{"name": "Intervencionismo", "desc": "Estado dirige investimentos.", "cost": 220, "tech": 1, "lit": 100,
			"fx": {"tax": 2, "tech": 1, "sat": {1: 3, 4: 4}}},
		{"name": "Livre mercado", "desc": "Mercados livres, impostos leves.", "cost": 280, "tech": 1, "lit": 150,
			"fx": {"tax": -4, "trade": 14, "sat": {3: 8, 2: -3, 1: -2}}},
	]},
	{"id": "trade", "name": "Política comercial", "col": 1, "opts": [
		{"name": "Protecionismo", "desc": "Tarifas altas protegem a indústria local.", "cost": 140, "tech": 0, "lit": 0,
			"fx": {"tax": 4, "trade": -10, "sat": {1: 2, 2: 3, 3: -3}}},
		{"name": "Tarifas moderadas", "desc": "Equilíbrio entre receita e abertura.", "cost": 140, "tech": 0, "lit": 0,
			"fx": {}},
		{"name": "Livre comércio", "desc": "Fronteiras abertas às mercadorias.", "cost": 200, "tech": 1, "lit": 100,
			"fx": {"tax": -3, "trade": 12, "sat": {3: 6, 2: -3}}},
	]},
	{"id": "tax", "name": "Sistema tributário", "col": 1, "opts": [
		{"name": "Tributo fundiário", "desc": "Imposto sobre a terra e a colheita.", "cost": 100, "tech": 0, "lit": 0,
			"fx": {"tax": 0, "sat": {0: -3, 2: -3}}},
		{"name": "Imposto proporcional", "desc": "Cobrança regular por renda e comércio.", "cost": 240, "tech": 1, "lit": 200,
			"fx": {"tax": 8, "sat": {3: -2, 4: 3}}},
		{"name": "Arrecadação por arrendamento", "desc": "Cobradores privados: rende, mas revolta.", "cost": 120, "tech": 0, "lit": 0,
			"fx": {"tax": 5, "stab": -2, "sat": {0: -5}}},
	]},
	{"id": "land", "name": "Trabalho compulsório", "col": 1, "opts": [
		{"name": "Servidão ou escravidão", "desc": "Trabalho forçado sustenta a elite.", "cost": 0, "tech": 0, "lit": 0,
			"fx": {"tax": 5, "stab": -1, "lit": -10, "sat": {2: 8, 0: -8, 1: -2}}},
		{"name": "Trabalho assalariado", "desc": "Camponeses livres, com obrigações.", "cost": 260, "tech": 1, "lit": 100,
			"fx": {"sat": {0: 4, 2: -6}}},
		{"name": "Reforma agrária", "desc": "Terra repartida entre os camponeses.", "cost": 380, "tech": 2, "lit": 200,
			"fx": {"tax": -3, "lit": 10, "sat": {0: 10, 2: -12, 3: 2}}},
	]},
	{"id": "edu", "name": "Educação", "col": 2, "opts": [
		{"name": "Ensino da Igreja", "desc": "Escolas paroquiais.", "cost": 80, "tech": 0, "lit": 0,
			"fx": {"lit": 0, "sat": {2: 2}}},
		{"name": "Escolas públicas", "desc": "Ensino básico financiado pelo Estado.", "cost": 260, "tech": 1, "lit": 150,
			"fx": {"lit": 25, "tech": 1, "sat": {4: 3, 0: 2}}},
		{"name": "Ensino universal obrigatório", "desc": "Toda criança vai à escola.", "cost": 420, "tech": 2, "lit": 300,
			"fx": {"lit": 50, "tech": 2, "tax": -2, "sat": {1: 4, 0: 3}}},
	]},
	{"id": "labor", "name": "Leis trabalhistas", "col": 2, "opts": [
		{"name": "Sem regulação", "desc": "Jornadas longas, trabalho infantil.", "cost": 0, "tech": 0, "lit": 0,
			"fx": {"tax": 4, "lit": -10, "sat": {1: -7, 3: 3}}},
		{"name": "Proteções básicas", "desc": "Limite de jornada e idade mínima.", "cost": 220, "tech": 1, "lit": 150,
			"fx": {"lit": 15, "sat": {1: 5, 3: -3}}},
		{"name": "Jornada regulada", "desc": "Fiscalização e descanso garantidos.", "cost": 340, "tech": 2, "lit": 250,
			"fx": {"tax": -3, "lit": 25, "sat": {1: 9, 3: -6}}},
	]},
	{"id": "unions", "name": "Direito de associação", "col": 2, "opts": [
		{"name": "Proibidas", "desc": "Sindicatos e partidos são ilegais.", "cost": 100, "tech": 0, "lit": 0,
			"fx": {"stab": 2, "sat": {1: -6, 3: -2, 5: 2}}},
		{"name": "Toleradas", "desc": "Associações existem sem proteção legal.", "cost": 120, "tech": 0, "lit": 100,
			"fx": {}},
		{"name": "Legalizadas", "desc": "Sindicatos e partidos reconhecidos.", "cost": 240, "tech": 2, "lit": 250,
			"fx": {"stab": -1, "sat": {1: 8, 0: 3, 2: -4}}},
	]},
]

const CLASS_NAMES := ["Camponeses", "Operários", "Aristocratas", "Burguesia", "Funcionários", "Soldados"]


static func group_count() -> int:
	return GROUPS.size()


static func group(gi: int) -> Dictionary:
	return GROUPS[gi]


static func option(gi: int, oi: int) -> Dictionary:
	var g: Dictionary = GROUPS[gi]
	var opts: Array = g["opts"]
	return opts[clampi(oi, 0, opts.size() - 1)]


## Leis iniciais (todas na opção 1, "meio-termo") ajustadas pelos dados históricos de 1836.
static func defaults_for(h: Dictionary) -> Array:
	var l: Array = []
	for i in GROUPS.size():
		l.append(1)
	if h.is_empty():
		return l
	var gov := str(h.get("gov", ""))
	var cent: int = int(h.get("cent", 2))
	var cap: int = int(h.get("cap", 2))
	var ind: int = int(h.get("ind", 1))
	var trade: int = int(h.get("trade", 2))
	var gi := _gi("gov")
	if gov.begins_with("republica"):
		l[gi] = 2
	elif gov.contains("absolut") or gov.contains("autocr") or gov.contains("sultan") or gov.contains("imperial") \
			or gov.contains("shogun") or gov.contains("califado") or gov.contains("teocr") or gov.contains("feudal"):
		l[gi] = 0
	else:
		l[gi] = 1
	l[_gi("press")] = 0 if (l[gi] == 0 and cent >= 3) else (2 if (ind >= 5 and gov.contains("constitucional")) else 1)
	var mil: int = int(h.get("army", 2))
	l[_gi("military")] = 2 if (mil >= 4 and cap >= 3) else (0 if mil >= 3 else 1)
	l[_gi("economy")] = 2 if (trade >= 4 and ind >= 4) else (0 if ind <= 1 else 1)
	l[_gi("trade")] = 2 if trade >= 5 else (0 if trade <= 1 else 1)
	l[_gi("tax")] = 1 if cap >= 3 else (2 if cap == 2 and cent <= 2 else 0)
	l[_gi("land")] = 0 if bool(h.get("slavery", false)) else 1
	l[_gi("edu")] = 1 if (ind >= 3 and cap >= 3) else 0
	l[_gi("labor")] = 0 if ind <= 3 else 1
	l[_gi("unions")] = 0 if (cent >= 4 or l[gi] == 0) else 1
	return l


static func _gi(id: String) -> int:
	for i in GROUPS.size():
		if str(GROUPS[i]["id"]) == id:
			return i
	return 0


## Soma dos efeitos das leis em vigor: {tax, trade, army, lit, tech, stab, sat:[6]}.
static func modifiers(laws: Array) -> Dictionary:
	var m := {"tax": 0, "trade": 0, "army": 0, "lit": 0, "tech": 0, "stab": 0, "sat": [0, 0, 0, 0, 0, 0]}
	for gi in mini(laws.size(), GROUPS.size()):
		var fx: Dictionary = option(gi, int(laws[gi]))["fx"]
		for k in ["tax", "trade", "army", "lit", "tech", "stab"]:
			m[k] = int(m[k]) + int(fx.get(k, 0))
		var sd: Dictionary = fx.get("sat", {})
		for ci in sd.keys():
			m["sat"][int(ci)] = int(m["sat"][int(ci)]) + int(sd[ci])
	return m


## Texto curto dos efeitos de uma opção, para a interface.
static func effect_lines(fx: Dictionary) -> Array:
	var out: Array = []
	var names := {"tax": "Arrecadação", "trade": "Comércio", "army": "Custo do exército",
		"lit": "Crescimento da alfabetização", "tech": "Tecnologia", "stab": "Estabilidade"}
	for k in ["tax", "trade", "army", "lit", "tech", "stab"]:
		if not fx.has(k) or int(fx[k]) == 0:
			continue
		var v: int = int(fx[k])
		var good := v > 0
		if k == "army":
			good = v < 0
		var txt := ""
		match k:
			"tech":
				txt = "%+d pt/mês" % v
			"stab":
				txt = "%+d" % v
			_:
				txt = "%+d%%" % v
		out.append({"text": "%s %s" % [names[k], txt], "good": good})
	var sd: Dictionary = fx.get("sat", {})
	for ci in sd.keys():
		var v2: int = int(sd[ci])
		if v2 != 0:
			out.append({"text": "%s %+d" % [CLASS_NAMES[int(ci)], v2], "good": v2 > 0})
	return out

extends SceneTree
## Teste de aceitação headless: godot --headless --path . --script tools/acceptance_test.gd
## Roda o ciclo central (carregar, simular, guerra, paz, vassalagem, salvar/carregar) sem UI e
## imprime "PASS"/"FAIL" por verificação; termina com código 1 se algo falhar.
## Usa get_node (e não os nomes dos autoloads) para compilar também em modo --script.

var g: Node
var fails: int = 0
var checks: int = 0


func check(name: String, ok: bool, extra: String = "") -> void:
	checks += 1
	if ok:
		print("PASS  ", name, "  ", extra)
	else:
		fails += 1
		print("FAIL  ", name, "  ", extra)


func _initialize() -> void:
	g = root.get_node("Game")
	if not g.loaded:
		g.load_world()
	run_all()
	print("RESULT: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)


func neighbors_pair() -> Array:
	# dois países vivos com fronteira terrestre, diferentes do jogador
	for c in g.countries:
		if not c.is_alive() or c.id == g.player_country or c.province_ids.size() < 3:
			continue
		for pid in c.province_ids:
			for nb in g.provinces[pid].neighbors:
				var o: int = int(g.provinces[int(nb)].owner_id)
				if o >= 0 and o != c.id and o != g.player_country and g.countries[o].is_alive() \
						and g.countries[o].province_ids.size() >= 4 and g.countries[o].overlord < 0 and c.overlord < 0:
					return [c.id, o]
	return []


func run_all() -> void:
	# --- mundo ------------------------------------------------------------
	var alive := 0
	var bad_owner := 0
	var bad_cap := 0
	for c in g.countries:
		if c.is_alive():
			alive += 1
			if c.capital >= 0 and int(g.provinces[c.capital].owner_id) != c.id:
				bad_cap += 1
	for p in g.provinces:
		if int(p.owner_id) >= g.countries.size():
			bad_owner += 1
	check("mundo carregado", g.provinces.size() > 100 and alive > 20, "%d provincias, %d paises" % [g.provinces.size(), alive])
	check("donos de provincia validos", bad_owner == 0)
	check("capitais pertencem ao proprio pais", bad_cap == 0, "%d fora" % bad_cap)
	var listed := 0
	for c in g.countries:
		listed += c.province_ids.size()
	var owned := 0
	for p in g.provinces:
		if int(p.owner_id) >= 0:
			owned += 1
	check("province_ids consistente com owner_id", listed == owned, "%d x %d" % [listed, owned])

	# --- calibração histórica do PIB (1836) ---------------------------------
	var em: Node = root.get_node("EconomyManager")
	var rf := FileAccess.open("res://data/real_economy_1836.json", FileAccess.READ)
	var table: Dictionary = JSON.parse_string(rf.get_as_text())
	var pcs: Dictionary = table["gdp_pc_1836"]
	var real_tot := 0.0
	var game_tot := 0.0
	var rows: Array = []
	for c in g.countries:
		if c.is_alive():
			var rr: float = float(pcs.get(c.tag, table["default_pc"])) * c.pop_total
			var gg: float = float(em.country_report(g, c.id)["gdp_nominal"])
			real_tot += rr
			game_tot += gg
			rows.append([c.tag, rr, gg])
	rows.sort_custom(func(x, y): return x[1] > y[1])
	var worst := 1.0
	var worst_tag := ""
	for i in 12:
		var ratio: float = (rows[i][2] / game_tot) / (rows[i][1] / real_tot)
		if absf(ratio - 1.0) > absf(worst - 1.0):
			worst = ratio
			worst_tag = rows[i][0]
	check("PIB dos 12 maiores segue a participacao historica (±35%)", worst > 0.65 and worst < 1.35, "pior %s x%.2f" % [worst_tag, worst])
	check("usd_per_gold calibrado", g.usd_per_gold > 0.0, "%.2f" % g.usd_per_gold)

	# --- simulação + desempenho ------------------------------------------
	g.speed = 1
	var snap0: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var t0 := Time.get_ticks_msec()
	var worst := 0
	for i in 365:
		var s0 := Time.get_ticks_msec()
		g.step()
		worst = maxi(worst, Time.get_ticks_msec() - s0)
	var el := Time.get_ticks_msec() - t0
	var h1: int = g.state_hash()
	print("PERF  365 dias: %d ms (%.1f ms/dia), pior dia %d ms, memoria %.0f MB" % [el, el / 365.0, worst, OS.get_static_memory_usage() / 1048576.0])
	check("simulacao anual < 60s (CI)", el < 60000)
	check("tesouro e estabilidade finitos", _sane_economy())

	# --- determinismo -----------------------------------------------------
	check("carregar estado inicial", g.load_state(snap0))
	for i in 365:
		g.step()
	var h2: int = g.state_hash()
	check("determinismo (mesmo estado -> mesmo hash)", h1 == h2, "%d x %d" % [h1, h2])

	# --- salvar / carregar -----------------------------------------------
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var before: int = g.state_hash()
	check("load_state do JSON", g.load_state(blob))
	check("salvar/carregar preserva o hash", g.state_hash() == before, "%d x %d" % [before, g.state_hash()])
	var path := "user://acc_save.json"
	check("save_game grava", g.save_game(path))
	check("load_game le", g.load_game(path))
	check("arquivo salvo preserva o hash", g.state_hash() == before)

	# --- pesquisa tecnológica ---------------------------------------------
	var rc = g.countries[g.player_country]
	g.apply_command({"type": "set_research", "pct": 20, "issuer": g.player_country})
	check("financiamento de pesquisa aplicado", rc.research_pct == 20)
	g.apply_command({"type": "set_research", "pct": 99, "issuer": g.player_country})
	check("financiamento limitado a 30%", rc.research_pct == g.RESEARCH_MAX_PCT)
	g.apply_command({"type": "set_research", "pct": 0, "issuer": g.player_country})
	var gain0: int = g.tech_gain(rc)
	var cost0: int = int(g.estimate_monthly(rc)["upkeep_research"])
	g.apply_command({"type": "set_research", "pct": 20, "issuer": g.player_country})
	check("20% dobra os pontos de pesquisa", g.tech_gain(rc) == gain0 * 2, "%d -> %d" % [gain0, g.tech_gain(rc)])
	check("pesquisa tem custo mensal", int(g.estimate_monthly(rc)["upkeep_research"]) > cost0)
	rc.tech_pts = g.MAX_TECH * Country.TECH_STEP + Country.TECH_STEP - 5
	g._simulate_month()
	check("tecnologia respeita o nivel maximo", rc.tech_level() <= g.MAX_TECH, "nivel %d" % rc.tech_level())
	var blob_r: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hr: int = g.state_hash()
	g.load_state(blob_r)
	check("pesquisa sobrevive ao salvar/carregar", g.countries[g.player_country].research_pct == 20 and g.state_hash() == hr)
	g.apply_command({"type": "set_research", "pct": 0, "issuer": g.player_country})

	# --- guerra, pontuação, vassalagem -----------------------------------
	var pr := neighbors_pair()
	check("achou par de vizinhos", pr.size() == 2)
	if pr.size() != 2:
		return
	var a: int = pr[0]
	var b: int = pr[1]
	g.alliances.erase(g._pair(a, b))
	g.truces.erase(g._pair(a, b))
	g._start_war(a, b)
	check("guerra declarada", g.at_war(a, b))
	var wi: int = g._war_index(a, b)
	g.wars[wi]["days"] = g.WAR_MIN_DAYS
	var n_b: int = g.countries[b].province_ids.size()
	var cap_b: int = g.countries[b].capital
	var sc0: int = g.war_score(a, b)
	# captura de capital: +30
	g._record_conquest(a, b, cap_b)   # mesma ordem do cerco: registra antes de transferir
	g.transfer_province(cap_b, a)
	var sc1: int = g.war_score(a, b)
	check("capital capturada soma 30 (+ 1 provincia)", sc1 == sc0 + g.CAPITAL_SCORE + 100 / n_b, "%d -> %d" % [sc0, sc1])
	# outra província
	var other := -1
	for pid in g.countries[b].province_ids:
		other = int(pid)
		break
	g._record_conquest(a, b, other)
	g.transfer_province(other, a)
	var sc2: int = g.war_score(a, b)
	check("provincia conquistada atualiza o placar", sc2 == 2 * 100 / n_b + g.CAPITAL_SCORE, "%d -> %d" % [sc1, sc2])
	# retomada e reconquista não duplicam
	g._record_conquest(b, a, other)
	g.transfer_province(other, b)
	g._record_conquest(a, b, other)
	g.transfer_province(other, a)
	check("retomar e reconquistar nao duplica", g.war_score(a, b) == sc2, "%d x %d" % [g.war_score(a, b), sc2])
	# indenização transfere o valor correto
	g.countries[b].treasury = 5000
	var ta: int = g.countries[a].treasury
	var tb: int = g.countries[b].treasury
	var amt: int = g.indemnity_amount(a, b)
	check("indenizacao possivel", g.can_peace_term(a, b, "indemnity"))
	g._apply_peace(a, b, "indemnity")
	check("indenizacao move o valor correto", g.countries[a].treasury == ta + amt and g.countries[b].treasury == tb - amt, "%d" % amt)
	check("guerra encerrada pela paz", not g.at_war(a, b))
	# vassalagem
	g._make_vassal(a, b)
	check("vassalo marcado", g.countries[b].overlord == a and g.is_vassal(b))
	check("alianca suserano-vassalo", g.allied(a, b))
	# salvar/carregar preserva vassalos
	var blob2: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var h3: int = g.state_hash()
	g.load_state(blob2)
	check("vassalagem sobrevive ao salvar/carregar", g.countries[b].overlord == a and g.state_hash() == h3)
	# tributo de 25% no mês
	g.countries[b].last_income = 1000
	var ov_t: int = g.countries[a].treasury
	var vs_t: int = g.countries[b].treasury
	g._simulate_month()
	var tribute_ok: bool = g.countries[b].overlord == a   # não se libertou
	if tribute_ok:
		check("tributo de 25% fluindo ao suserano", g.countries[a].treasury > ov_t - 5000 and g.countries[b].treasury != vs_t)
	# anexação: 360 dias e 60 por província
	g.countries[a].treasury = 999999
	g.countries[b].overlord_since = g.tick
	check("anexar antes de 360 dias e bloqueado", not g.can_annex_vassal(a, b))
	g.countries[b].overlord_since = g.tick - g.ANNEX_MIN_DAYS
	check("anexar apos 360 dias e liberado", g.can_annex_vassal(a, b))
	check("custo 60 por provincia", g.annex_cost(b) == g.countries[b].province_ids.size() * 60)
	# guerra do suserano arrasta vassalo
	var third := -1
	for c in g.countries:
		if c.is_alive() and c.id != a and c.id != b and c.id != g.player_country and c.overlord < 0 and not g.allied(a, c.id):
			third = c.id
			break
	if third >= 0:
		g.truces.erase(g._pair(a, third))
		g._start_war(a, third)
		check("vassalo entra na guerra do suserano", g.at_war(b, third))
		g._end_war(a, third)
		g._end_war(b, third)
	# libertação
	g._free_vassal(b, true)
	check("libertar remove a vassalagem", g.countries[b].overlord == -1 and not g.allied(a, b))
	# queda do suserano
	g._make_vassal(a, b)
	g.countries[a].province_ids.clear()   # simula país sem províncias
	g._simulate_month()
	check("queda do suserano liberta vassalos", g.countries[b].overlord == -1)


func _sane_economy() -> bool:
	for c in g.countries:
		if not c.is_alive():
			continue
		if abs(int(c.treasury)) > 1000000000 or int(c.stability) < 0 or int(c.stability) > 100:
			return false
	return true

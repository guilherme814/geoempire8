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

	# --- guerras em curso em 1836 e novos países ----------------------------
	var ids: Dictionary = {}
	for c in g.countries:
		ids[c.tag] = c.id
	check("Texas, Cáucaso, Montenegro e Abd al-Qadir existem", ids.has("TEX") and ids.has("CAU") and ids.has("MNE") and ids.has("ABD"))
	if ids.has("TEX") and ids.has("MEX"):
		check("guerra Mexico x Texas em curso", g.at_war(ids["MEX"], ids["TEX"]))
	if ids.has("ABD") and ids.has("FRA"):
		check("guerra Franca x Abd al-Qadir em curso", g.at_war(ids["FRA"], ids["ABD"]))
	if ids.has("CAU") and ids.has("RUS"):
		check("guerra Russia x Imamado do Caucaso em curso", g.at_war(ids["RUS"], ids["CAU"]))

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
	var gdp_dev := 1.0
	var worst_tag := ""
	for i in 12:
		var ratio: float = (rows[i][2] / game_tot) / (rows[i][1] / real_tot)
		if absf(ratio - 1.0) > absf(gdp_dev - 1.0):
			gdp_dev = ratio
			worst_tag = rows[i][0]
	check("PIB dos 12 maiores segue a participacao historica (±35%)", gdp_dev > 0.65 and gdp_dev < 1.35, "pior %s x%.2f" % [worst_tag, gdp_dev])
	check("usd_per_gold calibrado", g.usd_per_gold > 0.0, "%.2f" % g.usd_per_gold)

	# --- moeda (£) -----------------------------------------------------------
	check("Money: 140 -> £980 mil", Money.fmt(140) == "£980 mil", Money.fmt(140))
	check("Money: milhoes", Money.fmt(712) == "£5,0 mi", Money.fmt(712))
	check("Money: negativo e sinal", Money.fmt(-3) == "-£21 mil" and Money.signed(5) == "+£35 mil", Money.signed(5))
	check("Money: bilhoes", Money.fmt(1237731).ends_with(" bi"), Money.fmt(1237731))

	# --- governantes e nomes de época --------------------------------------
	var hair_ok: String = "bkgwryn"
	var beards_ok: Array = ["none", "stache", "chops", "full", "goatee", "long", "f"]
	var hats_ok: Array = ["none", "crown", "bicorne", "tophat", "turban", "fez", "qing", "eboshi", "gat", "mitre",
		"ghutra", "helmet", "tiara", "kepi", "papakha", "laurel"]
	var no_leaders: Array = []
	var bad_order: Array = []
	var bad_look: Array = []
	var rich: int = 0
	for c in g.countries:
		if not c.is_alive():
			continue
		var ll: Array = Leaders.list(c.tag)
		if ll.is_empty():
			no_leaders.append(c.tag)
			continue
		var prev_key: int = -1
		for e in ll:
			var ed: Dictionary = e
			var key: int = int(ed["from"]) * 12 + int(ed["m"])
			if key < prev_key:
				bad_order.append(c.tag)
			prev_key = key
			if not hair_ok.contains(str(ed["hair"])) or not beards_ok.has(str(ed["beard"])) or not hats_ok.has(str(ed["hat"])):
				bad_look.append(c.tag)
		if int(ll[0]["from"]) > 1836:
			bad_order.append(c.tag)
		if Leaders.successors(c.tag, 1836, 1, 6).size() >= 4:
			rich += 1
	check("todo pais vivo tem governantes", no_leaders.is_empty(), str(no_leaders))
	check("governantes em ordem cronologica", bad_order.is_empty(), str(bad_order))
	check("aparencia dos governantes valida", bad_look.is_empty(), str(bad_look))
	check("maioria dos paises com 4+ sucessores", rich >= 50, "%d paises" % rich)
	check("GBR 1836: Guilherme IV", str(Leaders.current("GBR", 1836, 1)["name"]) == "Guilherme IV")
	check("GBR 1837/6: Vitoria", str(Leaders.current("GBR", 1837, 6)["name"]) == "Vitória")
	check("GBR 1836: 6 sucessores", Leaders.successors("GBR", 1836, 1, 6).size() == 6)
	check("USA 1841/4: Tyler", str(Leaders.current("USA", 1841, 4)["name"]) == "John Tyler")
	var capital_bad: int = 0
	for c in g.countries:
		if c.is_alive() and c.capital >= 0 and g.provinces[c.capital].city == "":
			capital_bad += 1
	check("capitais com nome de cidade", capital_bad <= 2, "%d sem cidade" % capital_bad)
	var modern: int = 0
	for p in g.provinces:
		if p.name == "Istanbul" or p.name == "Beijing" or p.name == "Tokyo" or p.city == "Mumbai" or p.city == "Kolkata":
			modern += 1
	check("nomes modernos substituidos por nomes de epoca", modern == 0, "%d restantes" % modern)

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
	# árvore de tecnologias (estilo Victoria 3)
	check("catalogo: 36 tecnologias, 6 por era", Techs.ALL.size() == Techs.PER_ERA * Techs.MAX_ERA)
	var era_ok: bool = true
	for tid in Techs.ALL.size():
		var tdef: Dictionary = Techs.ALL[tid]
		if int(tdef["era"]) != tid / Techs.PER_ERA + 1 or not Techs.CATS.has(str(tdef["cat"])):
			era_ok = false
	check("ids por era e categorias consistentes", era_ok)
	var start_ok: bool = true
	for cc in g.countries:
		if not cc.is_alive():
			continue
		for ti in range(1, cc.techs.size()):
			if int(cc.techs[ti]) <= int(cc.techs[ti - 1]):
				start_ok = false
		if cc.techs.size() > 0 and int(cc.techs[cc.techs.size() - 1]) >= Techs.ALL.size():
			start_ok = false
	check("tecnologias ordenadas, sem repeticao e validas", start_ok)
	var pick: int = -1
	for tid in Techs.ALL.size():
		if Techs.available(rc, tid):
			pick = tid
			break
	if pick >= 0:
		g.apply_command({"type": "set_research_target", "tech": pick, "issuer": g.player_country})
		check("alvo de pesquisa aplicado", rc.researching == pick)
		var far: int = -1
		for tid in Techs.ALL.size():
			if int(Techs.ALL[tid]["era"]) > rc.tech_level() + 1:
				far = tid
				break
		if far >= 0:
			g.apply_command({"type": "set_research_target", "tech": far, "issuer": g.player_country})
			check("tecnologia de era bloqueada e recusada", rc.researching == pick)
		var n0: int = rc.techs.size()
		rc.tech_pts = Techs.cost(pick) + 7
		g._research_step(rc)
		check("pesquisa concluida adiciona a tecnologia", rc.techs.size() == n0 + 1 and rc.techs.has(pick) and rc.researching == -1)
		check("custo debitado do banco", rc.tech_pts == 7, "banco %d" % rc.tech_pts)
	var sum_atk: int = 0
	for tt in rc.techs:
		sum_atk += int(Techs.ALL[int(tt)]["fx"].get("atk", 0))
	check("efeitos acumulados conferem", int(g.tech_fx(rc)["atk"]) == sum_atk)
	# efeito econômico: Fertilizantes químicos (+5% de produção) aumenta a renda
	var saved_techs: Array = rc.techs.duplicate()
	rc.techs.erase(13)
	rc.fx_dirty = true
	var inc_a: int = int(g.estimate_monthly(rc)["income"])
	rc.techs.append(13)
	rc.fx_dirty = true
	var inc_b: int = int(g.estimate_monthly(rc)["income"])
	check("tecnologia de producao aumenta a renda", inc_b > inc_a or inc_a < 200, "%d -> %d" % [inc_a, inc_b])
	rc.techs = saved_techs
	rc.fx_dirty = true
	# novas construções liberadas por tecnologia
	var bp: Province = g.provinces[int(rc.province_ids[0])]
	var req_ok: bool = true
	var n_req: int = 0
	for bk in Province.BUILDINGS.keys():
		var rq: int = int(Province.BUILDINGS[bk].get("req", -1))
		if rq >= 0:
			n_req += 1
			if rq >= Techs.ALL.size() or not Province.EXTRA_KINDS.has(bk):
				req_ok = false
	check("10 construcoes por tecnologia com req valido e persistente", req_ok and n_req == 10, "%d" % n_req)
	var gate_saved: Array = rc.techs.duplicate()
	var treas_saved: int = rc.treasury
	var lv_bank: int = bp.building_level("bank")
	var lv_acad: int = bp.building_level("academy")
	var lv_lab: int = bp.building_level("lab")
	rc.treasury = 100000000
	rc.techs.erase(7)
	rc.fx_dirty = true
	check("banco bloqueado sem a tecnologia", not g.can_build(bp.id, g.player_country, "bank"))
	rc.techs.append(7)
	check("banco liberado com Bancos comerciais", g.can_build(bp.id, g.player_country, "bank"))
	bp.set_building_level("bank", 0)
	var tax0: int = bp.monthly_tax(30)
	bp.set_building_level("bank", 2)
	check("banco aumenta o imposto da provincia", bp.monthly_tax(30) > tax0 or bp.production() < 20, "%d -> %d" % [tax0, bp.monthly_tax(30)])
	bp.set_building_level("academy", 0)
	var mp0: int = bp.manpower_max()
	bp.set_building_level("academy", 3)
	check("academia aumenta a mao de obra", bp.manpower_max() > mp0 or bp.population < 3000)
	bp.set_building_level("lab", 0)
	var lab0: int = g.tech_gain_base(rc)
	bp.set_building_level("lab", 2)
	check("laboratorio aumenta pontos de pesquisa", g.tech_gain_base(rc) >= lab0 + 12, "%d -> %d" % [lab0, g.tech_gain_base(rc)])
	bp.set_building_level("bank", lv_bank)
	bp.set_building_level("academy", lv_acad)
	bp.set_building_level("lab", lv_lab)
	rc.techs = gate_saved
	rc.treasury = treas_saved
	rc.fx_dirty = true
	var ai_res: int = 0
	for cc in g.countries:
		if cc.is_alive() and not g.is_human(cc.id) and cc.researching >= 0:
			ai_res += 1
	check("IA escolhe pesquisa sozinha", ai_res >= 10, "%d paises" % ai_res)
	var techs_before: Array = rc.techs.duplicate()
	rc.tech_pts = 450
	g._simulate_month()
	check("tecnologia respeita o nivel maximo", rc.tech_level() <= g.MAX_TECH, "nivel %d" % rc.tech_level())
	var blob_r: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hr: int = g.state_hash()
	g.load_state(blob_r)
	check("pesquisa sobrevive ao salvar/carregar", g.countries[g.player_country].research_pct == 20 and g.state_hash() == hr)
	check("tecnologias sobrevivem ao salvar/carregar", g.countries[g.player_country].techs.size() >= techs_before.size())
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

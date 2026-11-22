extends SceneTree
## Teste de aceitação headless: godot --headless --path . --script tools/acceptance_test.gd
## Roda o ciclo central (carregar, simular, guerra, paz, vassalagem, salvar/carregar) sem UI e
## imprime "PASS"/"FAIL" por verificação; termina com código 1 se algo falhar.
## Usa get_node (e não os nomes dos autoloads) para compilar também em modo --script.

var g: Node
var fails: int = 0
var checks: int = 0


## Declara a guerra a e b e descarta guerras extras (aliados/coalizoes) para isolar o cenario.
func _war_only(a: int, b: int) -> void:
	g._start_war(a, b)
	var only: Array = []
	for ww in g.wars:
		if int(ww["a"]) == mini(a, b) and int(ww["b"]) == maxi(a, b):
			only.append(ww)
	g.wars = only


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
	# dois países vivos com fronteira terrestre, diferentes do jogador; prefere países médios
	# (3..15 províncias), para o cenário de guerra não depender do tamanho do mundo no dia do teste
	for max_n in [15, 100000]:
		var r: Array = _pair_upto(max_n)
		if not r.is_empty():
			return r
	return []


func _pair_upto(max_n: int) -> Array:
	for c in g.countries:
		if not c.is_alive() or c.id == g.player_country or c.province_ids.size() < 3 or c.province_ids.size() > max_n:
			continue
		for pid in c.province_ids:
			for nb in g.provinces[pid].neighbors:
				var o: int = int(g.provinces[int(nb)].owner_id)
				if o >= 0 and o != c.id and o != g.player_country and g.countries[o].is_alive() \
						and g.countries[o].province_ids.size() >= 4 and g.countries[o].province_ids.size() <= max_n and g.countries[o].overlord < 0 and c.overlord < 0:
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
	var all_brief: bool = true
	for cb in g.countries:
		if cb.province_ids.is_empty():
			continue
		var bb: Dictionary = Leaders.briefing(cb.tag)
		if bb.is_empty() or str(bb.get("hist", "")) == "" or str(bb.get("goal", "")) == "":
			all_brief = false
	check("todo pais tem briefing historico", all_brief)
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
	check("11 construcoes por tecnologia com req valido e persistente", req_ok and n_req == 11, "%d" % n_req)
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
	# migração e imigração
	var pop_before: int = 0
	for pp in g.provinces:
		pop_before += pp.population
	var pol_saved: Array = []
	for cc in g.countries:
		pol_saved.append(cc.immigration)
		cc.immigration = 0
	var per_c: Array = []
	for cc in g.countries:
		per_c.append(g.population_of(cc))
	g._simulate_migration()
	var closed_ok: bool = true
	for cc in g.countries:
		if cc.migr_in != 0 or g.population_of(cc) != int(per_c[cc.id]):
			closed_ok = false
	check("fronteira fechada: ninguem entra e a populacao do pais se conserva", closed_ok)
	for cc in g.countries:
		cc.immigration = 2
	g._simulate_migration()
	var pop_after: int = 0
	for pp in g.provinces:
		pop_after += pp.population
	var tot_in: int = 0
	var tot_out: int = 0
	for cc in g.countries:
		tot_in += cc.migr_in
		tot_out += cc.migr_out
	check("migracao conserva a populacao mundial", pop_after == pop_before, "%d -> %d" % [pop_before, pop_after])
	check("fronteira aberta gera fluxo entre paises", tot_in > 0 and tot_in == tot_out, "entram %d saem %d" % [tot_in, tot_out])
	for cc in g.countries:
		cc.immigration = int(pol_saved[cc.id])
		if cc.tag == "JAP":
			check("Japao comeca com a fronteira fechada", cc.immigration == 0)
	g.apply_command({"type": "set_immigration", "policy": 2, "issuer": g.player_country})
	check("politica de imigracao aplicada", rc.immigration == 2)
	g.apply_command({"type": "set_immigration", "policy": 9, "issuer": g.player_country})
	check("politica de imigracao invalida recusada", rc.immigration == 2)
	# logística e abastecimento
	check("abastecimento: perto da fonte = 100%", g._supply_ratio(3600, 6000) == 100)
	check("abastecimento: no limite do alcance = 50%", g._supply_ratio(6000, 6000) == 50)
	check("abastecimento: alem de 1,5x o alcance = 0%", g._supply_ratio(9000, 6000) == 0)
	check("rotulos de abastecimento", g.supply_label(90) == "normal" and g.supply_label(50) == "baixo" and g.supply_label(10) == "crítico")
	var cap_pid: int = rc.capital
	check("capital e fonte de abastecimento", g._supply_range_at(cap_pid, g.player_country) == g.SUPPLY_BASE_RANGE)
	var dpid: int = -1
	for pid2 in rc.province_ids:
		if int(pid2) != cap_pid:
			dpid = int(pid2)
			break
	if dpid >= 0:
		var dprov: Province = g.provinces[dpid]
		var lv_dep: int = dprov.building_level("depot")
		dprov.set_building_level("depot", 2)
		check("deposito: alcance 8000 e capacidade 16", g._supply_range_at(dpid, g.player_country) == 8000 and g._supply_cap_at(dpid) == 16)
		dprov.set_building_level("depot", lv_dep)
	g._add_regiments(cap_pid, g.player_country, 20)
	var sup_army: Army = null
	for aid in g.armies.keys():
		var ax: Army = g.armies[aid]
		if ax.owner_id == g.player_country and ax.province_id == cap_pid:
			sup_army = ax
	if sup_army != null:
		g._update_supply()
		check("exercito na capital recebe abastecimento total ate a capacidade", sup_army.supply > 0 and sup_army.supply <= 100, "%d%%" % sup_army.supply)
		var regs_before: int = sup_army.regiments
		sup_army.supply = 0
		g._supply_attrition()
		check("sem suprimentos o exercito perde regimentos", sup_army.regiments < regs_before, "%d -> %d" % [regs_before, sup_army.regiments])
		sup_army.supply = 37
		var blob_s: Dictionary = g.serialize_state()
		g.load_state(blob_s)
		var back: Army = null
		for aid2 in g.armies.keys():
			if int(aid2) == sup_army.id:
				back = g.armies[aid2]
		check("abastecimento sobrevive ao salvar/carregar", back != null and back.supply == 37)
		rc = g.countries[g.player_country]
	# IA operacional (AiWar / AiTheater): regras puras
	check("IA recua diante de inimigo superior", g.ai_should_retreat(5, 8, 0, 100))
	check("IA luta com vantagem", not g.ai_should_retreat(10, 5, 3, 100))
	check("IA recua com vizinhanca esmagadora", g.ai_should_retreat(4, 0, 9, 100))
	check("IA recua sem suprimentos", g.ai_should_retreat(10, 0, 0, 20))
	check("doutrina cautelosa recua onde a agressiva luta", g.ai_should_retreat(10, 13, 0, 100, "cautious") and not g.ai_should_retreat(10, 13, 0, 100, "aggressive"))
	check("oportunista pune guarnicao mais que o estrategico", g.ai_target_score(60, 2, 3, "opportunist") < g.ai_target_score(60, 2, 3, "strategic"))
	check("estrategico valoriza mais o alvo valioso", g.ai_target_score(150, 2, 0, "strategic") > g.ai_target_score(150, 2, 0, "defensive"))
	# atualizacao/changelog (UpdateRules) e desempenho
	check("tag semver valida", UpdateRules.is_valid_tag("v1.2.3") and UpdateRules.is_valid_tag("0.12.0-beta.1"))
	check("tag invalida rejeitada", not UpdateRules.is_valid_tag("latest") and not UpdateRules.is_valid_tag("1.2") and not UpdateRules.is_valid_tag("v1.2.3; rm"))
	check("versao mais nova detectada", UpdateRules.is_newer("0.13.0", "0.12.0") and UpdateRules.is_newer("v1.0.0", "0.99.9") and not UpdateRules.is_newer("0.12.0", "0.12.0") and not UpdateRules.is_newer("0.11.9", "0.12.0"))
	check("final vence prerelease da mesma base", UpdateRules.is_newer("1.0.0", "1.0.0-rc.1") and not UpdateRules.is_newer("1.0.0-rc.1", "1.0.0"))
	check("url oficial aceita", UpdateRules.url_allowed("https://github.com/guilherme814/geoempire8/releases/tag/v1.0.0") and UpdateRules.url_allowed("https://github.com/guilherme814/geoempire8"))
	check("url falsa rejeitada", not UpdateRules.url_allowed("https://github.com/guilherme814/geoempire8-evil") and not UpdateRules.url_allowed("https://github.com.evil.com/guilherme814/geoempire8") and not UpdateRules.url_allowed("http://github.com/guilherme814/geoempire8") and not UpdateRules.url_allowed("https://evil.com/github.com/guilherme814/geoempire8") and not UpdateRules.url_allowed("https://github.com@evil.com/guilherme814/geoempire8"))
	var bb: String = UpdateRules.to_bbcode("## Titulo\n- **item** [url=x]a[/url]")
	check("changelog remoto nao injeta BBCode", bb.find("[url") < 0 and bb.find("[lb]url") >= 0 and bb.find("[b]item[/b]") >= 0)
	check("payload de release validado", UpdateRules.clean_payload({"version": "v1.0.0", "body": "x", "html_url": "https://github.com/guilherme814/geoempire8/releases"}).get("version", "") == "1.0.0" and UpdateRules.clean_payload({"version": "v1.0.0", "body": "x", "html_url": "https://evil.com/x"}).is_empty() and UpdateRules.clean_payload({"body": "x"}).is_empty())
	check("corpo da release limitado", UpdateRules.to_bbcode("a".repeat(9000)).length() <= UpdateRules.MAX_BODY)
	PerfMonitor.clear()
	for i in 20:
		PerfMonitor.record("t", Time.get_ticks_usec())
	check("monitor de desempenho resume amostras", int(PerfMonitor.summary("t")["n"]) == 20 and float(PerfMonitor.summary("t")["max"]) >= float(PerfMonitor.summary("t")["avg"]))
	PerfMonitor.clear()
	var fb := FileAccess.open("res://data/changelog_fallback.json", FileAccess.READ)
	var fbj: Variant = JSON.parse_string(fb.get_as_text()) if fb != null else null
	check("changelog embutido valido e na versao do projeto", fbj is Dictionary and not UpdateRules.clean_payload(fbj).is_empty() and str(fbj["version"]) == str(ProjectSettings.get_setting("application/config/version", "")))
	# economia e diplomacia da IA (GEAI)
	check("IA sobe impostos na crise com estabilidade", g.ai_tax_step(25, -50, 100, 400, 60, false, "strategic") == 27)
	check("IA nao sobe impostos com estabilidade baixa", g.ai_tax_step(25, -50, 100, 400, 20, false, "cautious") == 25)
	check("IA baixa impostos com caixa folgado", g.ai_tax_step(25, 80, 20000, 400, 60, false, "strategic") == 24)
	check("IA em guerra com caixa curto sobe impostos", g.ai_tax_step(25, 0, 800, 400, 60, true, "aggressive") == 26)
	check("impostos da IA ficam em 12..45", g.ai_tax_step(45, -50, -5, 400, 80, false, "aggressive") == 45 and g.ai_tax_step(12, 50, 99999, 400, 80, false, "aggressive") == 12)
	var bo_war: Array = g.ai_build_order(["school", "farm", "market", "depot", "mine"], "strategic", true, "RUS")
	check("em guerra depositos e fazendas vem primeiro", bo_war[0] == "depot" and bo_war[1] == "farm")
	var bo_trade: Array = g.ai_build_order(["school", "farm", "market", "dock"], "strategic", false, "GBR")
	check("potencia comercial prioriza mercado e porto", bo_trade[0] == "market" and bo_trade[1] == "dock")
	check("ordem de construcao nao perde itens", g.ai_build_order(["a", "b", "c"], "aggressive", true, "XXX").size() == 3)
	check("aliado agressivo entra na guerra, defensivo nao", g.ai_ally_joins("aggressive", 50, true, 0) and not g.ai_ally_joins("defensive", 50, true, 0))
	check("interesse proprio baixa a exigencia do aliado", g.ai_ally_joins("cautious", 60, true, 20) and not g.ai_ally_joins("cautious", 60, true, 0))
	check("aliado sem preparo nao entra", not g.ai_ally_joins("aggressive", 90, false, 50))
	check("coalizao: estrategico contem agressor forte", g.ai_coalition_joins("strategic", false, 10, 0, 200, true))
	check("coalizao: cauteloso nunca, e so contra agressor forte", not g.ai_coalition_joins("cautious", true, 10, 0, 200, true) and not g.ai_coalition_joins("strategic", true, 10, 0, 120, true))
	check("alvo proximo vale mais que distante", g.ai_target_score(60, 1, 0) > g.ai_target_score(60, 6, 0))
	check("alvo guarnecido vale menos", g.ai_target_score(60, 2, 3) < g.ai_target_score(60, 2, 0))
	check("capital inimiga e mais valiosa", g.ai_province_value(g.countries[1].capital, 0) >= 110)
	var by_tag := {}
	for oc2 in g.countries:
		by_tag[oc2.tag] = oc2.id
	check("personalidades: GBR estrategico, RUS defensivo, FRA agressivo",
		g.ai_personality(int(by_tag["GBR"])) == "strategic" and g.ai_personality(int(by_tag["RUS"])) == "defensive" and g.ai_personality(int(by_tag["FRA"])) == "aggressive")
	check("personalidade imprevisivel resolve para uma doutrina concreta",
		["aggressive", "cautious", "opportunist", "strategic", "defensive"].has(g.ai_personality(int(by_tag["ARG"]))))
	# cenarios sobre o mapa real
	var bd: Dictionary = _find_border()
	if not bd.is_empty():
		var wc: Country = g.countries[int(bd["me"])]
		var wt: int = int(bd["foe"])
		var wsave: Dictionary = g.serialize_state()
		_war_only(wc.id, wt)
		var P: int = int(bd["p"])
		var Q: int = int(bd["q"])
		# cenario 1: potencia contra pequeno -> ofensiva
		g.armies.clear()
		g._add_regiments(P, wc.id, 12)
		g._add_regiments(Q, wt, 2)
		g.ai_think(wc.id, "strategic")
		var th1: Array = g.ai_theaters[wc.id]
		check("teatro criado contra o inimigo da guerra", th1.size() == 1 and int(th1[0]["enemy"]) == wt)
		check("superioridade esmagadora -> plano ofensivo", th1.size() == 1 and str(th1[0]["plan"]) == "offensive", str(th1[0]["why"]) if th1.size() == 1 else "")
		var moved1: bool = false
		for aid in g.armies.keys():
			var ax: Army = g.armies[aid]
			if ax.owner_id == wc.id and ax.is_moving():
				moved1 = true
		check("o exercito marcha ao objetivo do teatro", moved1)
		g.load_state(wsave)
		_war_only(wc.id, wt)
		# cenario 2: inferioridade -> nao ataca
		g.armies.clear()
		g._add_regiments(P, wc.id, 3)
		g._add_regiments(Q, wt, 10)
		g.ai_think(wc.id, "strategic")
		var th2: Array = g.ai_theaters[wc.id]
		check("inferioridade -> plano defensivo", th2.size() == 1 and str(th2[0]["plan"]) == "defensive")
		var suicide: bool = false
		for aid in g.armies.keys():
			var ay: Army = g.armies[aid]
			if ay.owner_id == wc.id and ay.is_moving() and ay.path.back() == Q:
				suicide = true
		check("a IA nao ataca em grande inferioridade", not suicide)
		g.load_state(wsave)
		_war_only(wc.id, wt)
		# cenario 3: a mesma situacao, doutrinas diferentes -> planos diferentes
		g.armies.clear()
		g._add_regiments(Q, wt, 4)
		g._add_regiments(P, wc.id, 1)
		g.ai_think(wc.id, "strategic")
		var need: int = int(g.ai_theaters[wc.id][0]["needed_off"])
		var force: int = (need * 110 + 99) / 100
		g.load_state(wsave)
		_war_only(wc.id, wt)
		g.armies.clear()
		g._add_regiments(Q, wt, 4)
		g._add_regiments(P, wc.id, force)
		g.ai_think(wc.id, "aggressive")
		var plan_agg: String = str(g.ai_theaters[wc.id][0]["plan"])
		g.load_state(wsave)
		_war_only(wc.id, wt)
		g.armies.clear()
		g._add_regiments(Q, wt, 4)
		g._add_regiments(P, wc.id, force)
		g.ai_think(wc.id, "cautious")
		var plan_cau: String = str(g.ai_theaters[wc.id][0]["plan"])
		check("agressivo ataca e cauteloso espera, com as mesmas tropas", plan_agg == "offensive" and plan_cau != "offensive", "%s x %s (%d tropas, precisa %d)" % [plan_agg, plan_cau, force, need])
		# cenario 4: ameaca perto da capital eleva a prioridade
		g.load_state(wsave)
		_war_only(wc.id, wt)
		g.armies.clear()
		g._add_regiments(P, wc.id, 5)
		g.ai_think(wc.id, "strategic")
		var prio0: int = int(g.ai_theaters[wc.id][0]["priority"])
		var capn: Array = g.provinces[wc.capital].neighbors
		if not capn.is_empty():
			g._add_regiments(int(capn[0]), wt, 5)
			g.ai_think(wc.id, "strategic")
			var prio1: int = int(g.ai_theaters[wc.id][0]["priority"])
			check("inimigo perto da capital aumenta a prioridade do teatro", prio1 > prio0, "%d -> %d" % [prio0, prio1])
		# determinismo das decisoes
		g.load_state(wsave)
		_war_only(wc.id, wt)
		g.armies.clear()
		g._add_regiments(P, wc.id, 8)
		g._add_regiments(Q, wt, 3)
		g.ai_think(wc.id)
		var hash_ai: int = g.state_hash()
		g.load_state(wsave)
		_war_only(wc.id, wt)
		g.armies.clear()
		g._add_regiments(P, wc.id, 8)
		g._add_regiments(Q, wt, 3)
		g.ai_think(wc.id)
		check("decisoes da IA sao deterministicas", hash_ai == g.state_hash())
		g.load_state(wsave)
		rc = g.countries[g.player_country]
	else:
		check("existe fronteira terrestre para os cenarios", false)
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
	check("politica de imigracao sobrevive ao salvar/carregar", g.countries[g.player_country].immigration == 2)
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
	check("provincia conquistada atualiza o placar", sc2 > sc1 and sc2 <= 100, "%d -> %d" % [sc1, sc2])
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
	_new_features()
	_log_buffer()
	_annex_batch_geometry()
	_sliced_month()
	_espionage()
	_infamy_and_outcomes()
	_pressure_and_ai_money()
	_production_methods()
	_law_legitimacy()
	_government()
	_diplomacy_moves()
	_pops()
	_class_income()
	_consumption()
	_regional_markets()
	_new_chains()
	_resource_methods()
	_private_capital()
	_tariffs()
	_excise()
	_transport()
	_cycles()
	_parliament()
	_interest_groups()
	_bills()
	_unrest()
	_revolutions()
	_money()


## Empréstimos, instrução das tropas, ajuda financeira e cooperação científica.
func _new_features() -> void:
	var me: int = g.player_country
	var c: Country = g.countries[me]
	c.debt = 0
	c.treasury = 1000
	c.last_income = 100
	var pre := c.treasury
	g.apply_command({"type": "take_loan", "issuer": me})
	check("empréstimo soma ao tesouro e à dívida", c.debt == g.LOAN_STEP and c.treasury == pre + g.LOAN_STEP)
	check("juros entram na despesa mensal", int(g.estimate_monthly(c)["upkeep_debt"]) == g.LOAN_STEP * g.LOAN_RATE_PCT / 100)
	for i in 30:
		g.apply_command({"type": "take_loan", "issuer": me})
	check("dívida respeita o limite de crédito", c.debt <= g.loan_limit(c))
	var d0: int = c.debt
	g.apply_command({"type": "repay_loan", "issuer": me})
	check("amortização reduz dívida", c.debt == d0 - g.LOAN_STEP)
	c.treasury = 0
	var d1: int = c.debt
	g.apply_command({"type": "repay_loan", "issuer": me})
	check("sem ouro não amortiza", c.debt == d1)
	c.debt = 0
	c.treasury = 1000
	# instrução
	var up0: int = int(g.estimate_monthly(c)["upkeep_army"])
	g.apply_command({"type": "set_drill", "level": 2, "issuer": me})
	check("instrução de elite custa mais", c.drill == 2 and int(g.estimate_monthly(c)["upkeep_army"]) >= up0)
	g.apply_command({"type": "set_drill", "level": 9, "issuer": me})
	check("instrução limitada a 0..2", c.drill == 2)
	g.apply_command({"type": "set_drill", "level": 0, "issuer": me})
	# ajuda
	var other := -1
	for o in g.countries:
		if o.id != me and o.is_alive() and not g.at_war(me, o.id) and g.opinion(me, o.id) < 70:
			other = o.id
			break
	if other >= 0:
		var t0: int = g.countries[other].treasury
		var op0: int = g.opinion(me, other)
		g.apply_command({"type": "send_aid", "target": other, "issuer": me})
		check("ajuda financeira transfere ouro e melhora opinião",
			c.treasury == 1000 - g.AID_COST and g.countries[other].treasury == t0 + g.AID_GIFT and g.opinion(me, other) == op0 + g.AID_OPINION)
	# ciência
	var sci0: int = g.tech_gain(c)
	check("cooperação científica sem aliados não muda a pesquisa", g.science_allies(c) >= 0 and sci0 >= g.tech_gain_base(c))
	# persistência
	c.debt = 700
	c.drill = 1
	var st: Dictionary = g.serialize_state()
	c.debt = 0
	c.drill = 0
	g.load_state(st)
	check("dívida e instrução persistem no save", g.countries[me].debt == 700 and g.countries[me].drill == 1)


func _sane_economy() -> bool:
	for c in g.countries:
		if not c.is_alive():
			continue
		if abs(int(c.treasury)) > 1000000000 or int(c.stability) < 0 or int(c.stability) > 100:
			return false
	return true


## Primeira fronteira terrestre entre dois países vivos (nenhum controlado pelo jogador).
func _find_border() -> Dictionary:
	for oc in g.countries:
		if oc.id == g.player_country or not oc.is_alive():
			continue
		for pid in oc.province_ids:
			for q in g.provinces[pid].neighbors:
				var o: int = g.provinces[int(q)].owner_id
				if o >= 0 and o != oc.id and o != g.player_country and g.countries[o].is_alive() and g.can_declare_war(oc.id, o):
					return {"me": oc.id, "foe": o, "p": int(pid), "q": int(q)}
	return {}


## Registro de sessão: agrupamento, limites, estatísticas de quadro e relatório.
func _log_buffer() -> void:
	var b := LogBuffer.new()
	b.add(LogBuffer.INFO, "teste", "mensagem", 1000)
	b.add(LogBuffer.INFO, "teste", "mensagem", 1500)
	b.add(LogBuffer.ERROR, "sanidade", "falha", 2000)
	check("log agrupa repetições consecutivas", b.lines.size() == 2 and int(b.lines[0]["n"]) == 2)
	check("log conta por nível", b.counts[0] == 2 and b.counts[2] == 1)
	for i in LogBuffer.MAX_LINES + 50:
		b.add(LogBuffer.INFO, "enc", "linha %d" % i, i)
	check("log respeita o limite de linhas", b.lines.size() <= LogBuffer.MAX_LINES and b.dropped > 0)
	var has_err := false
	for ln in b.lines:
		if int(ln["lvl"]) == LogBuffer.ERROR:
			has_err = true
	check("log nunca descarta erros", has_err)
	for i in 100:
		b.frame(0.016)
	b.frame(0.2)
	var fs: Dictionary = b.frame_stats()
	check("estatísticas de quadro (p50 e pior)", absf(float(fs["p50"]) - 16.0) < 0.5 and b.worst_ms >= 199.0 and b.hitches_100 == 1)
	b.bump("cmd_x")
	var txt: String = b.render({"Versão": "t"}, {"Seção": "conteúdo"})
	check("relatório traz resumo, seção e eventos", txt.contains("RESUMO") and txt.contains("SEÇÃO") and txt.contains("EVENTOS") and txt.contains("cmd_x=1") and txt.contains("falha"))
	b.frame_ctx("jogo_vel1", 0.016)
	b.frame_ctx("jogo_vel1", 0.2)
	b.add_timeline("01/01/1836 | teste")
	check("contexto de quadros e linha do tempo", b.ctx_report().contains("jogo_vel1") and b.timeline.size() == 1)
	for i in LogBuffer.MAX_TIMELINE + 10:
		b.add_timeline("m%d" % i)
	check("linha do tempo respeita o limite", b.timeline.size() == LogBuffer.MAX_TIMELINE)
	PerfMonitor.clear()
	PerfMonitor.record("m_a", Time.get_ticks_usec() - 5000)
	PerfMonitor.record("m_b", Time.get_ticks_usec() - 20000)
	check("PerfMonitor.slowest ordena etapas", PerfMonitor.slowest("m_", 1).begins_with("m_b") and PerfMonitor.last("m_a") > 0.0)
	PerfMonitor.clear()
	var got := []
	var b2 := LogBuffer.new()
	b2.on_important = func(lvl, tag, msg, _t): got.append([lvl, tag, msg])
	b2.add(LogBuffer.INFO, "x", "info")
	b2.add(LogBuffer.WARN, "x", "aviso")
	b2.add(LogBuffer.ERROR, "x", "erro")
	check("gancho do diário só recebe aviso e erro", got.size() == 2 and int(got[0][0]) == LogBuffer.WARN)
	check("formata o tempo da sessão", LogBuffer.fmt_time(3723004) == "01:02:03.004")


## Anexação refaz a geometria uma vez no fim: o resultado tem de ser igual a recalcular de novo.
func _annex_batch_geometry() -> void:
	var a := -1
	var v := -1
	for c in g.countries:
		if c.is_alive() and c.id != g.player_country and c.province_ids.size() >= 2:
			if a < 0:
				a = c.id
			elif v < 0:
				v = c.id
	if a < 0 or v < 0:
		return
	var nv: int = g.countries[v].province_ids.size()
	var na: int = g.countries[a].province_ids.size()
	g._annex_country(a, v)
	check("anexação move todas as províncias", g.countries[v].province_ids.is_empty() and g.countries[a].province_ids.size() == na + nv)
	var b1: Rect2 = g.countries[a].bounds
	var lp1: Vector2 = g.countries[a].label_pos
	g._refresh_country_geometry(g.countries[a])
	check("geometria em lote igual à recalculada", b1 == g.countries[a].bounds and lp1 == g.countries[a].label_pos)
	check("país anexado fica sem geometria", g.countries[v].bounds == Rect2())


## Turno mensal fatiado deve dar exatamente o mesmo estado que o turno síncrono.
func _sliced_month() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	g._simulate_month()
	var h_sync: int = g.state_hash()
	g.load_state(blob)
	g._month_stage = 0
	g.month_budget_us = 1   # força o corte em TODA unidade de trabalho (pior caso de fatiamento)
	var guard := 0
	while g.month_pending() and guard < 60000:
		g._run_month_slice()
		guard += 1
	var h_sliced: int = g.state_hash()
	g.month_budget_us = 9000
	check("mes fatiado levou varios quadros (cursores funcionando)", guard > 20, "%d quadros" % guard)
	check("mes fatiado gera o mesmo hash do sincrono", h_sync == h_sliced, "%d vs %d" % [h_sync, h_sliced])
	# comandos durante o mes ficam na fila e sao aplicados depois, na ordem
	g.load_state(blob)
	g._month_stage = 0
	# Regressao: autosave/hash chamados DURANTE a ultima etapa (ouvinte de month_changed) nao podem recursar.
	g.load_state(blob)
	g._month_stage = 0
	g.month_hook = func(): g.state_hash(); g.save_game("user://_t_reentry.json")
	g.finish_month()
	g.month_hook = Callable()
	check("autosave durante o mes nao recursa (reentrada)", not g.month_pending() and not g._month_running)
	g.load_state(blob)
	g._month_stage = 0
	var tax0: int = g.countries[g.player_country].tax_pct
	g.apply_command({"type": "set_tax", "country": g.player_country, "pct": 77, "issuer": g.player_country})
	check("comando durante o mes espera na fila", g.countries[g.player_country].tax_pct == tax0 and g._cmd_queue.size() == 1)
	g.finish_month()
	check("comando enfileirado e aplicado ao fim do mes", g.countries[g.player_country].tax_pct == 77 and not g.month_pending())
	g.load_state(blob)


func _espionage() -> void:
	var me: int = g.player_country
	var other := -1
	for c in g.countries:
		if c.is_alive() and c.id != me:
			other = c.id
			break
	if other < 0:
		return
	var c: Country = g.countries[me]
	c.treasury = 1000
	c.spy_cd = 0
	var op0: int = g.opinion(me, other)
	g.apply_command({"type": "spy", "target": other, "op": 0, "issuer": me})
	check("espionagem cobra custo e inicia espera", c.treasury == 1000 - g.SPY_COST and c.spy_cd == g.SPY_COOLDOWN)
	var t1: int = c.treasury
	g.apply_command({"type": "spy", "target": other, "op": 1, "issuer": me})
	check("espionagem bloqueada durante a espera", c.treasury == t1)
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	g.load_state(blob)
	check("espera de espionagem persiste no save", g.countries[me].spy_cd == g.SPY_COOLDOWN)
	g._simulate_month()
	check("espera de espionagem diminui por mes", g.countries[me].spy_cd == g.SPY_COOLDOWN - 1)
	g.countries[me].spy_cd = 0


func _infamy_and_outcomes() -> void:
	var me: int = g.player_country
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	# --- infamia
	var tgt := -1
	for c in g.countries:
		if c.is_alive() and c.id != me and not g.at_war(me, c.id) and g.can_declare_war(me, c.id):
			tgt = c.id
			break
	if tgt >= 0:
		var i0: int = g.countries[me].infamy
		g._start_war(me, tgt)
		check("declarar guerra aumenta a infamia", g.countries[me].infamy == i0 + g.INFAMY_WAR)
	g.countries[me].infamy = 120
	var other := -1
	for c in g.countries:
		if c.is_alive() and c.id != me and not g.at_war(me, c.id):
			other = c.id
			break
	if other >= 0:
		g.countries[me].treasury = 100000
		g.countries[other].treasury = 100000
		check("ninguem melhora relacoes, ajuda ou alia com um paria", not g.can_improve(other, me) and not g.can_send_aid(other, me) and not g.can_ally(other, me))
		g.countries[me].infamy = 10
		check("sem infamia alta, melhorar relacoes volta a ser possivel", g.can_improve(other, me) or g.opinion(other, me) >= 100)
		g.relations[g._pair(me, other)] = 50
		g.countries[me].infamy = g.INFAMY_BAD + g.INFAMY_DECAY   # o decaimento mensal vem antes da checagem
		g._simulate_month()
		check("mal visto perde 1 de opiniao por mes alem do decaimento", g.opinion(me, other) == 50 - 2 - 1, "%d" % g.opinion(me, other))
	g.countries[me].infamy = 10
	g._simulate_month()
	check("infamia decai por mes", g.countries[me].infamy == 10 - g.INFAMY_DECAY)
	var blob_i: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	g.countries[me].infamy = 77
	g.load_state(blob_i)
	check("infamia persiste no save", g.countries[me].infamy == 10 - g.INFAMY_DECAY)
	# --- vitorias / derrota
	g.load_state(blob)
	var got: Array = []
	var n := 0
	for p in g.provinces:
		if p.owner_id >= 0 and p.owner_id != me:
			g.transfer_province(p.id, me, false)
			n += 1
			if g.countries[me].province_ids.size() * 100 >= g.provinces.size() * g.HEGEMONY_PCT:
				break
	got = g._check_outcome()
	check("vitoria por hegemonia ao dominar 25% do mundo", got.has("hegemony") and g.victories.has("hegemony"))
	got = g._check_outcome()
	check("vitoria so e anunciada uma vez", got.is_empty())
	var blob_v: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	g.victories.clear()
	g.load_state(blob_v)
	check("vitorias persistem no save", g.victories.has("hegemony"))
	g.load_state(blob)
	for pid in g.countries[me].province_ids.duplicate():
		g.transfer_province(int(pid), (me + 1) % g.countries.size(), false)
	got = g._check_outcome()
	check("derrota ao perder todas as provincias", got.has("defeat") and g.defeated)
	g.load_state(blob)
	# --- save atomico
	var path := "user://_t_atomic.json"
	check("save atomico grava e nao deixa .tmp", g.save_game(path) and FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"))
	g.load_state(blob)


func _pressure_and_ai_money() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var agg := -1
	for c in g.countries:
		if c.is_alive() and c.id != me and not g.is_human(c.id):
			agg = c.id
			break
	if agg < 0:
		return
	check("pressao comeca em 0", g.pressure_level(agg, me) == 0)
	check("1a escalada vai ao nivel 1", g.pressure_escalate(agg, me) == 1)
	check("sem esperar, nao sobe de novo", g.pressure_escalate(agg, me) == 1)
	g.tick += g.PRESSURE_STEP_DAYS
	check("apos o intervalo sobe ao nivel 2", g.pressure_escalate(agg, me) == 2)
	var b2: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	g.pressure.clear()
	g.load_state(b2)
	check("pressao persiste no save", g.pressure_level(agg, me) == 2)
	g.countries[me].treasury = 100000
	g.relations[g._pair(me, agg)] = 0
	g.apply_command({"type": "improve_relations", "target": agg, "issuer": me})
	check("melhorar relacoes acalma a pressao", g.pressure_level(agg, me) <= 1)
	g.tick += g.PRESSURE_FORGET_DAYS
	g._simulate_month()
	check("pressao esquecida com o tempo", g.pressure_level(agg, me) == 0)
	# financas da IA
	g.load_state(blob)
	var a: Country = g.countries[agg]
	a.treasury = -50
	a.debt = 0
	g._ai_finance(a)
	check("IA toma emprestimo com caixa negativo", a.debt > 0 and a.treasury > -50)
	a.treasury = 100000
	var d0: int = a.debt
	g._ai_finance(a)
	check("IA amortiza quando sobra dinheiro", a.debt < d0)
	g.load_state(blob)


func _production_methods() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var fp: Province = null
	for pid in g.countries[me].province_ids:
		var p: Province = g.provinces[pid]
		p.factory = "carpentry"
		p.factory_level = 2
		p.method = 0
		fp = p
		break
	if fp == null:
		return
	var c: Country = g.countries[me]
	c.treasury = 100000
	c.techs.clear()
	var u0: int = fp.factory_units()
	check("metodo artesanal e a base", u0 == int(Province.FACTORIES[fp.factory]["amount"]) * 2)
	check("manufatura exige era 1", not g.can_set_method(fp.id, me, 1) or c.tech_level() >= 1)
	# libera tecnologia suficiente para a era 3
	var ids := []
	for i in Techs.ALL.size():
		ids.append(i)
	c.techs = ids
	check("com tecnologia, pode mecanizar", g.can_set_method(fp.id, me, 2))
	var t0: int = c.treasury
	g.apply_command({"type": "set_method", "province": fp.id, "method": 2, "issuer": me})
	check("mecanizar cobra o custo e muda o metodo", fp.method == 2 and c.treasury < t0)
	check("mecanizada produz mais", fp.factory_units() == u0 * 170 / 100)
	var in0: int = fp.factory_input("timber")
	check("mecanizada consome mais insumos", in0 == 100 * 2 * 150 / 100)
	var b2: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	fp.method = 0
	g.load_state(b2)
	check("metodo persiste no save", g.provinces[fp.id].method == 2)
	var t1: int = c.treasury
	g.apply_command({"type": "set_method", "province": fp.id, "method": 0, "issuer": me})
	check("voltar ao artesanal e gratis", fp.method == 0 and c.treasury == t1)
	g.load_state(blob)


func _law_legitimacy() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	check("tabela de afinidade cobre todos os grupos", Laws.fit_all(c.laws).size() == 5)
	var pol: Dictionary = g.politics_of(c)
	check("legitimidade limitada a +-6", absi(int(pol["legit"])) <= 6)
	check("previsao e deterministica", int(g.politics_of(c)["legit"]) == int(pol["legit"]))
	for gi in Laws.group_count():
		check("afinidade definida: " + str(Laws.group(gi)["id"]), Laws.LEAN.has(str(Laws.group(gi)["id"])) and (Laws.LEAN[str(Laws.group(gi)["id"])] as Array).size() == (Laws.group(gi)["opts"] as Array).size())
	var dem: Array = g.law_demands(c, pol)
	check("no maximo 3 reformas exigidas", dem.size() <= 3)
	for dm in dem:
		check("reforma exigida melhora a afinidade", int(dm["gain"]) > 0)
	g.load_state(blob)


func _government() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	c.treasury = 100000
	c.budget_code = Government.DEFAULT_CODE
	c.decree = -1
	c.decree_cd = 0
	check("codigo de orcamento: niveis padrao", Government.level(13, 0) == 1 and Government.level(13, 3) == 0)
	check("with_level troca so o ministerio", Government.level(Government.with_level(13, 2, 2), 2) == 2 and Government.level(Government.with_level(13, 2, 2), 1) == 1)
	var e0: Dictionary = g.estimate_monthly(c)
	g.apply_command({"type": "set_budget", "ministry": 3, "level": 2, "issuer": me})
	var e1: Dictionary = g.estimate_monthly(c)
	check("assistencia social cobra despesa", int(e1["upkeep_welfare"]) > 0 and int(e1["expense"]) > int(e0["expense"]))
	g.apply_command({"type": "set_budget", "ministry": 0, "level": 0, "issuer": me})
	check("cortar educacao reduz o custo", int(g.estimate_monthly(c)["upkeep_edu"]) <= int(e1["upkeep_edu"]))
	check("orcamento invalido e ignorado", not g.can_set_budget(me, 9, 1) and not g.can_set_budget(me, 0, 5))
	var sh: Array = Government.sat_shift(c.budget_code, -1)
	check("assistencia eleva satisfacao de operarios", int(sh[1]) > 0)
	g.apply_command({"type": "decree", "id": 0, "issuer": me})
	check("decreto entra em vigor", c.decree == 0 and c.decree_left == 12)
	check("so um decreto por vez", g.decree_block_reason(me, 1) != "")
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	g.load_state(bl)
	check("governo sobrevive ao salvar/carregar", g.countries[me].decree == 0 and g.countries[me].budget_code == c.budget_code and g.state_hash() == hh)
	c = g.countries[me]
	c.decree_left = 1
	g._country_month(c)
	check("decreto expira e entra em espera", c.decree == -1 and c.decree_cd == Government.DECREE_COOLDOWN - 0)
	check("espera bloqueia novo decreto", g.decree_block_reason(me, 2) != "")
	g.load_state(blob)


func _diplomacy_moves() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var other := -1
	for c in g.countries:
		if c.is_alive() and c.id != me and c.overlord < 0 and not g.at_war(me, c.id) and not g.allied(me, c.id) and c.infamy < g.INFAMY_PARIAH:
			other = c.id
			break
	if other < 0:
		check("achou alvo diplomatico", false)
		return
	g.countries[me].treasury = 100000
	g.countries[me].overlord = -1
	g.cb.clear()
	g.treaties.clear()
	g.truces.erase(g._pair(me, other))
	# casus belli
	check("pode justificar guerra", g.can_justify(me, other))
	g.apply_command({"type": "justify", "target": other, "issuer": me})
	check("justificativa em preparo", g.cb_pending_days(me, other) > 0 and not g.has_cb(me, other))
	check("nao justifica duas vezes", not g.can_justify(me, other))
	g.tick += g.JUSTIFY_DAYS
	check("casus belli pronto", g.has_cb(me, other))
	var inf0: int = g.countries[me].infamy
	g._start_war(me, other)
	check("guerra com casus belli nao gera infamia", g.countries[me].infamy == inf0 and not g.cb.has(me * 1000 + other))
	g._end_war(me, other)
	g.truces.erase(g._pair(me, other))
	# tratados
	g.relations[g._pair(me, other)] = 50
	g.apply_command({"type": "propose_treaty", "target": other, "kind": 0, "issuer": me})
	check("pacto de nao agressao firmado", g.treaty_active(me, other, 0))
	check("pacto bloqueia declaracao de guerra", not g.can_declare_war(me, other) and not g.can_declare_war(other, me))
	g.apply_command({"type": "propose_treaty", "target": other, "kind": 1, "issuer": me})
	check("acordo comercial da bonus de comercio", g.treaty_trade_pct(me) == g.TREATY_TRADE_PCT)
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	g.load_state(bl)
	check("tratados sobrevivem ao salvar/carregar", g.treaty_active(me, other, 0) and g.state_hash() == hh)
	var inf1: int = g.countries[me].infamy
	g.apply_command({"type": "break_treaty", "target": other, "kind": 0, "issuer": me})
	check("romper pacto custa infamia", not g.treaty_active(me, other, 0) and g.countries[me].infamy == inf1 + g.PACT_BREAK_INFAMY)
	g.tick += g.TREATY_DAYS + 1
	g._expire_diplomacy()
	check("tratados vencem", not g.treaty_active(me, other, 1) and g.treaty_trade_pct(me) == 0)
	g.relations[g._pair(me, other)] = 0
	g.apply_command({"type": "propose_treaty", "target": other, "kind": 0, "issuer": me})
	check("sem opiniao suficiente a IA recusa", not g.treaty_active(me, other, 0))
	g.load_state(blob)


func _pops() -> void:
	var c: Country = g.countries[g.player_country]
	var pops: Dictionary = g.country_pops(c)
	check("pops cobrem todas as provincias", pops.size() == c.province_ids.size())
	var bad := 0
	var neg := 0
	for pid in pops.keys():
		var v: Array = pops[pid]
		var sum := 0
		for i in 6:
			sum += int(v[i])
			if int(v[i]) < 0:
				neg += 1
		if sum != g.provinces[int(pid)].population:
			bad += 1
	check("soma das pops = populacao da provincia", bad == 0, "%d provincias" % bad)
	check("nenhuma pop negativa", neg == 0)
	var again: Dictionary = g.country_pops(c)
	check("pops sao deterministicas", JSON.stringify(again) == JSON.stringify(pops))


func _class_income() -> void:
	var c: Country = g.countries[g.player_country]
	var inc: Dictionary = g.class_income(c)
	var neg := 0
	for i in 6:
		if int(inc["pool"][i]) < 0 or int(inc["pc"][i]) < 0:
			neg += 1
	check("renda por classe nao e negativa", neg == 0)
	check("Gini entre 0 e 1000", int(inc["gini"]) >= 0 and int(inc["gini"]) <= 1000, str(inc["gini"]))
	check("renda e deterministica", JSON.stringify(g.class_income(c)) == JSON.stringify(inc))
	var people := 0
	for i in 6:
		people += int(inc["people"][i])
	check("pessoas somam a populacao", people == g.population_of(c))


func _consumption() -> void:
	for i in 6:
		var tw := 0
		for k in Consumption.BASKETS[i].keys():
			tw += int(Consumption.BASKETS[i][k])
		check("cesta %d soma 100" % i, tw == 100, str(tw))
	var base := {}
	check("precos-base: termo de conforto 0", Consumption.comfort_term(base, 2) == 0 and Consumption.comfort_term(base, 0) == 0)
	var dear := {"wine": 140, "silk": 140, "spices": 140, "furniture": 140, "sugar": 140, "tea": 140}
	check("cesta cara reduz satisfacao", Consumption.comfort_term(dear, 2) < 0)
	var cheap := {"wine": 70, "silk": 70, "spices": 70, "furniture": 70, "sugar": 70, "tea": 70}
	check("cesta barata eleva satisfacao", Consumption.comfort_term(cheap, 2) > 0)
	check("termo limitado", Consumption.comfort_term({"wine": 1000, "silk": 1000, "spices": 1000, "furniture": 1000, "sugar": 1000, "tea": 1000}, 2) >= Consumption.TERM_MIN)


func _regional_markets() -> void:
	var food: Dictionary = g.region_food()
	check("ha mercados regionais", food.size() > 0)
	var neg := 0
	var famine := 0
	for k in food.keys():
		var r: Array = food[k]
		if int(r[0]) < 0 or int(r[1]) < 0:
			neg += 1
	for p in g.provinces:
		if p.owner_id >= 0 and g.region_famine(food, p):
			famine += 1
	check("oferta e demanda regionais nao negativas", neg == 0)
	check("regioes sao deterministicas", JSON.stringify(g.region_food()) == JSON.stringify(food))
	print("INFO provincias em regiao com fome: %d de %d" % [famine, g.provinces.size()])


func _new_chains() -> void:
	for k in ["paper", "machinery"]:
		check("fabrica %s registrada" % k, Province.FACTORIES.has(k) and Province.BUILDINGS.has(k) and Province.JOBS_PER_LEVEL.has(k) and Province.BUILD_MATERIALS.has(k) and Province.WAGE_PCT.has(k))
		var out: String = str(Province.FACTORIES[k]["out"])
		check("bem %s no mercado" % out, Province.PROCESSED.has(out) and g.goods_list().has(out))
	var bad := 0
	for b in Province.BUILD_MATERIALS.keys():
		for good in Province.BUILD_MATERIALS[b].keys():
			if not (Province.RESOURCE_PRICE.has(good) or Province.PROCESSED.has(good)):
				bad += 1
	check("materiais de obra so usam bens existentes", bad == 0, "%d invalidos" % bad)


func _resource_methods() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	var ep: Province = null
	for pid in c.province_ids:
		var p: Province = g.provinces[pid]
		if p.can_host(p.primary_extractor()):
			ep = p
			break
	if ep == null:
		check("achou provincia com extracao", false)
		return
	ep.bld[ep.primary_extractor()] = 2
	ep.rmethod = 0
	c.treasury = 100000
	var ids := []
	for i in Techs.ALL.size():
		ids.append(i)
	c.techs = ids
	var u0: int = ep.units()
	check("com tecnologia pode mecanizar a extracao", g.can_set_rmethod(ep.id, me, 2))
	g.apply_command({"type": "set_rmethod", "province": ep.id, "method": 2, "issuer": me})
	check("extracao mecanizada produz mais", ep.rmethod == 2 and ep.units() > u0)
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	ep.rmethod = 0
	g.load_state(bl)
	check("metodo de extracao persiste", g.provinces[ep.id].rmethod == 2 and g.state_hash() == hh)
	g.load_state(blob)


func _private_capital() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	var fp: Province = null
	for pid in c.province_ids:
		var p: Province = g.provinces[pid]
		p.factory = "carpentry"
		p.factory_level = 1
		p.method = 0
		fp = p
		break
	check("grupo de lei economico existe", Laws.group_index("economy") >= 0)
	c.private_capital = 100000
	var t0: int = c.treasury
	g._private_invest(c)
	check("capitalistas ampliam a fabrica sem gastar o tesouro", fp.factory_level >= 2 and c.treasury == t0 and c.private_capital < 100000)
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	c.private_capital = 0
	g.load_state(bl)
	check("capital privado persiste", g.countries[me].private_capital == int(bl["private_capital"][me]) and g.state_hash() == hh)
	g.countries[me].private_capital = 0
	g.provinces[fp.id].factory_level = Province.MAX_BUILDING
	g._private_invest(g.countries[me])
	check("fabrica no maximo nao e ampliada", g.provinces[fp.id].factory_level == Province.MAX_BUILDING)
	g.load_state(blob)


func _tariffs() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	check("tarifa padrao e 10%", g.countries[me].tariff == g.TRADE_TARIFF_PCT or g.countries[me].tariff >= 0)
	g.countries[me].tariff = 10
	check("tarifa invalida e recusada", not g.can_set_tariff(me, 12) and not g.can_set_tariff(me, 35) and not g.can_set_tariff(me, 10))
	g.apply_command({"type": "set_tariff", "pct": 25, "issuer": me})
	check("tarifa definida", g.countries[me].tariff == 25)
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	g.countries[me].tariff = 5
	g.load_state(bl)
	check("tarifa persiste", g.countries[me].tariff == 25 and g.state_hash() == hh)
	var bal: Array = g.trade_balance(me)
	check("balanca comercial nao negativa", int(bal[0]) >= 0 and int(bal[1]) >= 0)
	g.load_state(blob)


func _money() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	c.interest = 2
	c.inflation = 0
	check("juros invalidos recusados", not g.can_set_rate(me, 0) and not g.can_set_rate(me, 9) and not g.can_set_rate(me, 2))
	var e2: int = int(g.estimate_monthly(c)["upkeep_debt"])
	c.debt = 10000
	var d2: int = int(g.estimate_monthly(c)["upkeep_debt"])
	g.apply_command({"type": "set_rate", "pct": 4, "issuer": me})
	var d4: int = int(g.estimate_monthly(c)["upkeep_debt"])
	check("juros maiores encarecem a divida", c.interest == 4 and d4 == 2 * d2 and d2 > e2)
	var t0: int = c.treasury
	g.apply_command({"type": "print_money", "issuer": me})
	check("emitir moeda da caixa e inflacao", c.treasury == t0 + g.PRINT_STEP and c.inflation > 0)
	var tax0: int = int(g.estimate_monthly(c)["income"])
	c.inflation = 0
	var tax1: int = int(g.estimate_monthly(c)["income"])
	check("inflacao corroi a arrecadacao", tax0 <= tax1)
	c.inflation = 20
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	c.inflation = 0
	g.load_state(bl)
	check("juros e inflacao persistem", g.countries[me].interest == 4 and g.countries[me].inflation == 20 and g.state_hash() == hh)
	g._country_month(g.countries[me])
	check("inflacao cai com juros altos", g.countries[me].inflation == 18)
	g.load_state(blob)


func _excise() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	c.excise = 0
	c.tax_pct = 30
	check("imposto de consumo invalido e recusado", not g.can_set_excise(me, 7) and not g.can_set_excise(me, 25) and not g.can_set_excise(me, 0))
	var e0: Dictionary = g.estimate_monthly(c)
	check("sem consumo, nada arrecadado dele", int(e0["excise"]) == 0)
	g.apply_command({"type": "set_excise", "pct": 15, "issuer": me})
	check("imposto de consumo definido", c.excise == 15)
	var e1: Dictionary = g.estimate_monthly(c)
	check("consumo rende e evasao sobe", int(e1["excise"]) > 0 and int(e1["evasion"]) >= int(e0["evasion"]))
	check("renda inclui o consumo", int(e1["income"]) == int(e1["tax"]) + int(e1["excise"]) + int(e1["industry_state"]) + int(e1["trade"]))
	c.excise = 0
	c.tax_pct = 90
	var ev_hi: int = g.tax_evasion(c)
	c.tax_pct = 10
	check("evasao maior com imposto alto, sempre limitada", ev_hi > g.tax_evasion(c) and ev_hi <= g.EVASION_MAX and g.tax_evasion(c) >= g.EVASION_MIN, "alto %d baixo %d alf %d tarifa %d" % [ev_hi, g.tax_evasion(c), c.literacy, c.tariff])
	c.tax_pct = 30
	c.excise = 10
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	c.excise = 0
	g.load_state(bl)
	check("imposto de consumo persiste", g.countries[me].excise == 10 and g.state_hash() == hh)
	g.load_state(blob)


func _transport() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	for pid in c.province_ids:
		g.provinces[pid].bld["railway"] = 0
	check("sem ferrovia: transporte 25%", g.transport_pct(c) == 25)
	for pid in c.province_ids:
		g.provinces[pid].bld["railway"] = 2
	check("ferrovias elevam o transporte, limitado a 90%", g.transport_pct(c) > 25 and g.transport_pct(c) <= 90)
	for pid in c.province_ids:
		g.provinces[pid].bld["railway"] = 0
	# Região em falta recebe parte da sobra do país conforme o transporte.
	var food := {"%d|A" % me: [0, 100], "%d|B" % me: [400, 100]}
	var pool: Dictionary = g.food_pool(food)
	check("sobra do pais = 300", int(pool.get(me, 0)) == 300)
	var r_local: int = g.region_ratio(food, me, "A")
	var r_net: int = g.region_ratio(food, me, "A", pool)
	check("sem rede a regiao em falta passa fome", r_local == 0)
	check("rede de transporte leva a sobra: 25% de 300 = 75", r_net == 75)
	for pid in c.province_ids:
		g.provinces[pid].bld["railway"] = 3
	check("mais ferrovia, mais alimento chega", g.region_ratio(food, me, "A", pool) > r_net)
	check("custo da rota maritima cresce com passagens", g.lane_cost(0) == 1 and g.lane_cost(3) == 4 and g.lane_cost(-2) == 1)
	for pid in c.province_ids:
		g.provinces[pid].bld["dock"] = 0
	check("sem cais, sem bonus portuario", g.port_trade_pct(c) == 0)
	g.provinces[c.province_ids[0]].bld["dock"] = 50
	check("bonus portuario limitado a 30%", g.port_trade_pct(c) == g.PORT_TRADE_MAX)
	g.load_state(blob)


func _cycles() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	c.panic_left = 0
	c.interest = 2
	c.inflation = 0
	c.debt = 0
	c.private_capital = 0
	var low: int = g.panic_risk(c)
	check("risco financeiro baixo com juros normais e sem divida", low >= 0 and low < g.PANIC_RISK)
	c.interest = 4
	c.inflation = 30
	c.private_capital = g.PRIVATE_CAPITAL_MAX
	var high: int = g.panic_risk(c)
	check("juros, inflacao e capital elevam o risco, limitado a 100", high > low and high <= 100 and high >= g.PANIC_RISK)
	check("fase do ciclo reflete o risco", g.cycle_phase(c) == 2)
	# Pânico: corrida aos bancos destrói capital privado e arrecadação.
	c.panic_left = 0
	var tax0: int = int(g.estimate_monthly(c)["tax"])
	var cap0: int = c.private_capital
	c.panic_left = g.PANIC_MONTHS
	var tax1: int = int(g.estimate_monthly(c)["tax"])
	check("panico corta a arrecadacao", tax1 < tax0)
	check("fase de panico", g.cycle_phase(c) == 3)
	g._private_invest(c)
	check("credito congelado no panico", c.private_capital == cap0)
	g._panic_step(c)
	check("panico dura meses e conta regressiva", c.panic_left == g.PANIC_MONTHS - 1)
	# Rolagem determinística: mesma data e país, mesmo resultado.
	check("rolagem do panico e deterministica", g._panic_roll(c) == g._panic_roll(c) and g._panic_roll(c) >= 0 and g._panic_roll(c) < 100)
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	c.panic_left = 0
	g.load_state(bl)
	check("panico persiste no save", g.countries[me].panic_left == g.PANIC_MONTHS - 1 and g.state_hash() == hh)
	# Tabela de ranking mundial.
	var em: Node = load("res://scripts/core/economy_manager.gd").new()
	var wt: Array = em.world_table(g)
	check("tabela mundial tem os paises vivos", wt.size() > 10 and wt[0].has("gdp_nominal") and wt[0].has("army"))
	var so: Array = em.sort_by(wt, "population")
	check("ranking ordenado em ordem decrescente", int(so[0]["population"]) >= int(so[1]["population"]) and int(so[so.size() - 2]["population"]) >= int(so[so.size() - 1]["population"]))
	em.free()
	g.load_state(blob)


func _parliament() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	var gi: int = Laws.group_index("gov")
	c.laws[gi] = 0
	var none: Array = g.election_seats(c)
	check("autocracia: sem eleicao", g.suffrage_of(c) == 0 and int(none[0]) + int(none[1]) + int(none[2]) + int(none[3]) + int(none[4]) == 0)
	c.laws[gi] = 2
	var s2: Array = g.election_seats(c)
	var t2 := 0
	var neg := false
	for j in 5:
		t2 += int(s2[j])
		if int(s2[j]) < 0:
			neg = true
	check("republica: 100 cadeiras, nenhuma negativa", t2 == g.SEAT_TOTAL and not neg)
	c.laws[gi] = 1
	var s1: Array = g.election_seats(c)
	var t1 := 0
	for j in 5:
		t1 += int(s1[j])
	check("monarquia constitucional: 100 cadeiras", t1 == g.SEAT_TOTAL)
	check("eleicao deterministica", g.election_seats(c) == s1)
	c.elect_cd = 2
	var st0: int = c.stability
	g._election_step(c)
	check("contagem regressiva da eleicao", c.elect_cd == 1)
	g._election_step(c)
	check("eleicao reinicia o ciclo de 48 meses", c.elect_cd == g.ELECTION_MONTHS)
	var tt := 0
	for j in 5:
		tt += int(c.seats[j])
	check("eleicao preenche o parlamento", tt == g.SEAT_TOTAL)
	check("efeito na estabilidade e limitado", absi(c.stability - st0) <= g.ELECTION_STAB_MAX)
	var sup: int = g.parliament_support(c)
	check("apoio ao governo entre 0 e 100", sup >= 0 and sup <= 100)
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	var keep: Array = c.seats.duplicate()
	c.seats = [0, 0, 0, 0, 0]
	c.elect_cd = 1
	g.load_state(bl)
	check("parlamento persiste no save", g.countries[me].seats == keep and g.countries[me].elect_cd == g.ELECTION_MONTHS and g.state_hash() == hh)
	g.load_state(blob)


func _interest_groups() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	var gr: Array = g.interest_groups(c)
	var clout := 0
	var ok := true
	for e in gr:
		clout += int(e["clout"])
		if int(e["approval"]) < 0 or int(e["approval"]) > 100 or int(e["tier"]) < 0 or int(e["tier"]) > 2:
			ok = false
	check("5 grupos de interesse", gr.size() == 5)
	check("aprovacao e nivel validos", ok)
	check("clout soma ~100 (arredondamento)", clout >= 95 and clout <= 100)
	for i in 6:
		c.sat[i] = 95
	var happy: Dictionary = g.group_effects(g.interest_groups(c))
	for i in 6:
		c.sat[i] = 3
	var angry: Dictionary = g.group_effects(g.interest_groups(c))
	check("grupos felizes ajudam, irritados atrapalham", int(happy["tax"]) >= int(angry["tax"]) and int(happy["trade"]) >= int(angry["trade"]) and int(angry["tax"]) <= 0)
	check("efeitos limitados", int(happy["tax"]) <= 8 and int(angry["tax"]) >= -12 and absi(int(angry["trade"])) <= 8)
	var e0: Dictionary = g.estimate_monthly(c)
	c.grp_tax = 0
	var base_tax: int = int(g.estimate_monthly(c)["tax"])
	c.grp_tax = -10
	check("efeito dos grupos reduz a arrecadacao", int(g.estimate_monthly(c)["tax"]) < base_tax)
	c.grp_tax = -7
	c.grp_trade = 4
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	c.grp_tax = 0
	c.grp_trade = 0
	g.load_state(bl)
	check("efeitos dos grupos persistem", g.countries[me].grp_tax == -7 and g.countries[me].grp_trade == 4 and g.state_hash() == hh)
	check("estimate valido", e0.has("income"))
	g.load_state(blob)


func _bills() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	var gi: int = Laws.group_index("press")
	c.laws[Laws.group_index("gov")] = 2
	for k in 5:
		c.seats[k] = 0
	check("sem parlamento eleito, a lei e direta", not g.needs_vote(c))
	c.seats = [20, 20, 20, 20, 20]
	check("com parlamento, a lei precisa de voto", g.needs_vote(c))
	# Escolhe uma opção diferente da vigente com apoiadores e opositores.
	var cur: int = int(c.laws[gi])
	var oi := -1
	for k in Laws.group(gi)["opts"].size():
		if k != cur:
			oi = k
			break
	c.law_cd[gi] = 0
	c.treasury = 10000000
	var sup: Dictionary = g.bill_support(c, gi, oi)
	check("apoio nunca passa de 100%", int(sup["for"]) + int(sup["against"]) <= 100 and int(sup["for"]) >= 0)
	# Parlamento totalmente a favor: passa em 3 fases.
	for k in 5:
		c.seats[k] = 0
	var fav := -1
	for k in 5:
		if Laws.lean(gi, oi, k) - Laws.lean(gi, cur, k) > 0:
			fav = k
	var opp := -1
	for k in 5:
		if Laws.lean(gi, oi, k) - Laws.lean(gi, cur, k) < 0:
			opp = k
	if fav >= 0:
		c.seats[fav] = 100
		g._start_bill(c, gi, oi)
		check("projeto entra em tramitacao", c.bill_g == gi and c.bill_o == oi)
		check("so um projeto por vez", g.law_block_reason(c, gi, oi) != "")
		g._bill_step(c)
		g._bill_step(c)
		check("duas fases vencidas, lei ainda nao vale", c.bill_p == 2 and int(c.laws[gi]) == cur)
		g._bill_step(c)
		check("terceira fase aprova a lei", int(c.laws[gi]) == oi and c.bill_g == -1)
	# Parlamento contra: 3 reveses derrubam, devolvem metade e bloqueiam por 2 anos.
	if opp >= 0:
		c.laws[gi] = cur
		c.law_cd[gi] = 0
		for k in 5:
			c.seats[k] = 0
		c.seats[opp] = 100
		var t0: int = c.treasury
		g._start_bill(c, gi, oi)
		var cost: int = int(Laws.option(gi, oi)["cost"])
		check("custo e cobrado ao propor", c.treasury == t0 - cost)
		g._bill_step(c)
		g._bill_step(c)
		g._bill_step(c)
		check("tres reveses derrubam o projeto", c.bill_g == -1 and int(c.laws[gi]) == cur)
		check("metade do custo devolvida", c.treasury == t0 - cost + cost / 2)
		check("bloqueio de 2 anos", int(c.law_cd[gi]) == g.BILL_BLOCK_MONTHS)
		# Cancelar um projeto.
		c.law_cd[gi] = 0
		g._start_bill(c, gi, oi)
		g.apply_command({"type": "cancel_bill", "issuer": me})
		check("cancelar limpa o projeto e bloqueia o grupo", c.bill_g == -1 and int(c.law_cd[gi]) == g.BILL_BLOCK_MONTHS)
	# Persistência.
	c.law_cd[gi] = 0
	c.seats = [20, 20, 20, 20, 20]
	g._start_bill(c, gi, oi)
	c.bill_p = 2
	c.bill_s = 1
	c.bill_a = 4
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var hh: int = g.state_hash()
	g._clear_bill(c)
	g.load_state(bl)
	var lc: Country = g.countries[me]
	check("projeto de lei persiste no save", lc.bill_g == gi and lc.bill_o == oi and lc.bill_p == 2 and lc.bill_s == 1 and lc.bill_a == 4 and g.state_hash() == hh)
	g.load_state(blob)


func _unrest() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	var pol: Dictionary = g.politics_of(c)
	# Estavel: nada de rebeldes e relogio parado.
	for pid in c.province_ids:
		g.provinces[pid].unrest = 0
	c.stability = 80
	c.rev_clock = 0
	for k in 5:
		c.radical[k] = 0
	for k in 6:
		c.sat[k] = 80
	g._unrest_step(c, pol)
	var cnt: Dictionary = g.unrest_counts(c)
	check("pais estavel sem rebeldes", int(cnt["rebel"]) == 0 and c.rev_clock == 0 and c.strikes == 0)
	# Insatisfacao radicaliza a corrente da classe.
	for k in 6:
		c.sat[k] = 10
	var before: int = int(c.radical[int(g.CLASS_RADICAL[0])])
	g._unrest_step(c, pol)
	check("insatisfacao radicaliza correntes", int(c.radical[int(g.CLASS_RADICAL[0])]) > before)
	# Caos: agitacao sobe, rebeldes surgem, relogio corre (carencia alta: a revolucao fica para outro teste).
	c.stability = 5
	c.rev_cd = 999
	for i in 40:
		g._unrest_step(c, pol)
	cnt = g.unrest_counts(c)
	check("caos gera rebeldes", int(cnt["rebel"]) > 0)
	check("greves cortam arrecadacao", c.strikes > 0)
	check("relogio da revolucao corre", c.rev_clock > 0 and c.rev_clock <= g.REV_CLOCK_MAX)
	var pp: Province = null
	for pid in c.province_ids:
		if g.provinces[pid].unrest >= g.UNREST_REBEL:
			pp = g.provinces[pid]
			break
	var mp0: int = pp.manpower if pp != null else 0
	if pp != null:
		g._unrest_step(c, pol)
		check("rebeldes drenam mao de obra", pp.manpower <= mp0)
	# Recuperacao.
	c.stability = 90
	for k in 6:
		c.sat[k] = 90
	for i in 60:
		g._unrest_step(c, pol)
	check("com estabilidade a agitacao e o relogio recuam", c.rev_clock == 0 and int(g.unrest_counts(c)["rebel"]) == 0)
	# Persistencia.
	c.stability = 5
	for i in 20:
		g._unrest_step(c, pol)
	var hh: int = g.state_hash()
	var rc: int = c.rev_clock
	var u0: int = g.provinces[c.province_ids[0]].unrest
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	g.provinces[c.province_ids[0]].unrest = 0
	c.rev_clock = 0
	g.load_state(bl)
	var lc: Country = g.countries[me]
	check("agitacao e relogio persistem no save", lc.rev_clock == rc and g.provinces[lc.province_ids[0]].unrest == u0 and g.state_hash() == hh)
	g.load_state(blob)


func _revolutions() -> void:
	var blob: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	var me: int = g.player_country
	var c: Country = g.countries[me]
	var pol: Dictionary = g.politics_of(c)
	var gov: int = Laws.group_index("gov")
	var n0: int = g.chronicle.size()
	# Previsao: corrente socialista dominante = revolucao.
	for k in 5:
		c.radical[k] = 0
	c.radical[2] = 900
	var fc: Dictionary = g.revolution_forecast(c, pol)
	check("previsao: socialista dominante gera revolucao", int(fc["dom"]) == 2 and int(fc["kind"]) == 2)
	# Revolucao: sistema de governo muda, parlamento reiniciado, relogio zerado, carencia.
	c.laws[gov] = 0
	c.seats = [20, 20, 20, 20, 20]
	c.rev_cd = 0
	c.rev_clock = 12
	for pid in c.province_ids:
		g.provinces[pid].unrest = 90
	g._revolution(c, pol)
	check("revolucao troca o governo para republica", int(c.laws[gov]) == 2)
	check("revolucao reinicia o parlamento", int(c.seats[0]) + int(c.seats[1]) + int(c.seats[2]) + int(c.seats[3]) + int(c.seats[4]) == 0 and c.elect_cd == 12)
	check("revolucao zera relogio, dispersa rebeldes e cria carencia", c.rev_clock == 0 and c.rev_cd == g.REV_COOLDOWN and c.rev_type == 2 and int(g.unrest_counts(c)["rebel"]) == 0)
	check("revolucao entra na cronica", g.chronicle.size() == n0 + 1 and int(g.chronicle[n0][2]) == me)
	# Carencia: com caos, o relogio nao passa de 11 e nao ha nova revolucao.
	c.stability = 5
	for i in 20:
		g._unrest_step(c, pol)
	check("carencia impede nova revolucao", c.rev_clock <= g.REV_CLOCK_MAX - 1 and g.chronicle.size() == n0 + 1)
	# Golpe: autocracia, imprensa censurada, parlamento dissolvido.
	c.rev_cd = 0
	c.laws[gov] = 2
	c.seats = [20, 20, 20, 20, 20]
	g._revolution(c, pol, 1)
	check("golpe instala autocracia e dissolve o parlamento", int(c.laws[gov]) == 0 and not g.needs_vote(c) and c.rev_type == 1)
	# Gatilho pelo passo mensal: relogio no limite dispara a revolucao.
	c.rev_cd = 0
	c.rev_clock = 11
	c.stability = 5
	var n1: int = g.chronicle.size()
	g._unrest_step(c, pol)
	check("relogio completo dispara a revolucao", g.chronicle.size() == n1 + 1 and c.rev_clock == 0 and c.rev_cd > 0)
	# Persistencia.
	var hh: int = g.state_hash()
	var cs: int = g.chronicle.size()
	var cd: int = c.rev_cd
	var bl: Dictionary = JSON.parse_string(JSON.stringify(g.serialize_state()))
	c.rev_cd = 0
	g.chronicle = []
	g.load_state(bl)
	check("cronica e carencia persistem no save", g.chronicle.size() == cs and g.countries[me].rev_cd == cd and g.state_hash() == hh)
	g.load_state(blob)

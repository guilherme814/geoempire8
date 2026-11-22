extends SceneTree
## Auditoria da economia: simula 10 anos sem jogador e imprime, por ano, estatísticas
## agregadas + alertas. godot --headless --path . --script tools/economy_audit.gd

var g: Node
var em: Node
var alerts: Array = []


func _initialize() -> void:
	g = root.get_node("Game")
	em = root.get_node("EconomyManager")
	if not g.loaded:
		g.load_world()
	_calibration()
	var start := _snapshot()
	print("ANO  0 | ", _fmt(start))
	_demo_probe(0)
	_growth_probe(0)
	for year in range(1, 11):
		for i in 365:
			g.step()
		var s := _snapshot()
		print("ANO %2d | " % year, _fmt(s))
		if year == 10:
			_demo_probe(year)
		if year == 5 or year == 10:
			_growth_probe(year)
		var vas := 0
		for c in g.countries:
			if c.is_alive() and c.overlord >= 0:
				vas += 1
		print("GUERRA ano %2d | guerras ativas %d | vassalos %d | propostas de paz pendentes %d | exercitos %d" % [year, g.wars.size(), vas, g.peace_offers.size(), g.armies.size()])
		_check(year, s, start)
		_politics(year)
	print("REVOLUCOES em 10 anos: %d (golpes %d)" % [g.chronicle.size(), g.chronicle.filter(func(e): return int(e[3]) == 1).size()])
	print("--- alertas ---")
	for a in alerts:
		print("ALERT ", a)
	print("AUDIT-DONE ", alerts.size(), " alertas")
	_worst()
	print("--- BASELINE DE DESEMPENHO (CI, 10 anos, sem jogador) ---")
	print(PerfMonitor.report())
	quit(0)


func _snapshot() -> Dictionary:
	var n := 0
	var neg := 0
	var deficit := 0
	var bal: Array = []
	var cpis: Array = []
	var unemp: Array = []
	var gdp := 0
	var pop := 0
	var treas: Array = []
	var stab: Array = []
	for c in g.countries:
		if not c.is_alive():
			continue
		n += 1
		var r: Dictionary = em.country_report(g, c.id)
		if int(c.treasury) < 0:
			neg += 1
		var b: int = int(c.last_income) - int(c.last_expense)
		if b < 0:
			deficit += 1
		bal.append(b)
		cpis.append(int(r["price_index"]))
		unemp.append(g.unemployment_pct(c))
		gdp += int(r["gdp_nominal"])
		pop += int(r["population"])
		treas.append(int(c.treasury))
		stab.append(int(c.stability))
	bal.sort()
	cpis.sort()
	unemp.sort()
	treas.sort()
	stab.sort()
	var pmin := 100000
	var pmax := 0
	for tbl in g.local_price:
		for good in g.goods_list():
			var v: int = int(tbl.get(good, 100))
			pmin = mini(pmin, v)
			pmax = maxi(pmax, v)
	return {"n": n, "neg": neg, "deficit": deficit, "gdp": gdp, "pop": pop,
		"bal_med": bal[n / 2], "bal_min": bal[0], "bal_max": bal[n - 1],
		"cpi_min": cpis[0], "cpi_med": cpis[n / 2], "cpi_max": cpis[n - 1],
		"un_med": unemp[n / 2], "un_max": unemp[n - 1],
		"tr_med": treas[n / 2], "tr_min": treas[0], "tr_max": treas[n - 1],
		"st_min": stab[0], "st_med": stab[n / 2],
		"p_min": pmin, "p_max": pmax}


func _fmt(s: Dictionary) -> String:
	return "paises %d | PIB %d pop %d | saldo med %d [%d..%d] deficit %d | tesouro med %d [%d..%d] neg %d | CPI %d/%d/%d | desemp med %d max %d | estab min %d med %d | precos %d..%d" % [
		s["n"], s["gdp"], s["pop"], s["bal_med"], s["bal_min"], s["bal_max"], s["deficit"],
		s["tr_med"], s["tr_min"], s["tr_max"], s["neg"], s["cpi_min"], s["cpi_med"], s["cpi_max"],
		s["un_med"], s["un_max"], s["st_min"], s["st_med"], s["p_min"], s["p_max"]]


func _check(year: int, s: Dictionary, start: Dictionary) -> void:
	if int(s["neg"]) * 4 > int(s["n"]):
		alerts.append("ano %d: %d de %d paises com tesouro negativo" % [year, s["neg"], s["n"]])
	if int(s["deficit"]) * 2 > int(s["n"]):
		alerts.append("ano %d: maioria em deficit mensal (%d de %d)" % [year, s["deficit"], s["n"]])
	if int(s["cpi_max"]) > 250 or int(s["cpi_min"]) < 40:
		alerts.append("ano %d: indice de precos fora de 40..250 (%d..%d)" % [year, s["cpi_min"], s["cpi_max"]])
	if int(s["p_max"]) > 400 or int(s["p_min"]) < 25:
		alerts.append("ano %d: preco local extremo (%d%%..%d%%)" % [year, s["p_min"], s["p_max"]])
	if int(s["gdp"]) > int(start["gdp"]) * 2 or int(s["gdp"]) * 2 < int(start["gdp"]):
		alerts.append("ano %d: PIB mundial %d vs inicio %d (variacao >2x ou <0,5x)" % [year, s["gdp"], start["gdp"]])
	if int(s["pop"]) > int(start["pop"]) * 2 or int(s["pop"]) * 10 < int(start["pop"]) * 7:
		alerts.append("ano %d: populacao mundial %d vs inicio %d" % [year, s["pop"], start["pop"]])
	if int(s["tr_max"]) > 50000000:
		alerts.append("ano %d: tesouro maximo explodiu (%d)" % [year, s["tr_max"]])
	if int(s["un_max"]) > 20:
		alerts.append("ano %d: desemprego fora de 0..20" % year)


## Política (B25): pobreza, agitação, relógio da revolução e desfechos, por ano. Gera alertas de balanceamento.
func _politics(year: int) -> void:
	var pov: Array = []
	var stab: Array = []
	var clock_hi := 0
	var rebel_p := 0
	var prot_p := 0
	var tot_p := 0
	var n := 0
	for c in g.countries:
		if not c.is_alive():
			continue
		n += 1
		pov.append(int(c.poverty))
		stab.append(int(c.stability))
		if c.rev_clock >= 6:
			clock_hi += 1
		for pid in c.province_ids:
			tot_p += 1
			var u: int = g.provinces[pid].unrest
			if u >= 70:
				rebel_p += 1
			elif u >= 40:
				prot_p += 1
	pov.sort()
	stab.sort()
	var kinds := [0, 0, 0, 0, 0]
	for e in g.chronicle:
		var k: int = int(e[3])
		if k >= 0 and k < 5:
			kinds[k] += 1
	print("POLITICA ano %2d | miseria min/med/max %d/%d/%d | estab min/med %d/%d | relogio>=6: %d de %d | provincias rebeldes %d protesto %d de %d | cronica golpe %d revol %d secessao %d guerra civil %d" % [year, pov[0], pov[pov.size() / 2], pov[-1], stab[0], stab[stab.size() / 2], clock_hi, n, rebel_p, prot_p, tot_p, kinds[1], kinds[2], kinds[3], kinds[4]])
	if clock_hi * 5 > n:
		alerts.append("ano %d: mais de 20%% dos paises com relogio da revolucao >= 6 (%d de %d)" % [year, clock_hi, n])
	if rebel_p * 10 > tot_p:
		alerts.append("ano %d: mais de 10%% das provincias em rebeliao (%d de %d)" % [year, rebel_p, tot_p])
	if pov[pov.size() / 2] > 85:
		alerts.append("ano %d: miseria mediana %d%% (>85)" % [year, pov[pov.size() / 2]])
	if year == 10 and g.chronicle.size() > 20:
		alerts.append("revolucoes demais em 10 anos: %d" % g.chronicle.size())


func _worst() -> void:
	var rows: Array = []
	for c in g.countries:
		if c.is_alive():
			rows.append([int(c.treasury), c.name, int(c.last_income) - int(c.last_expense), int(c.stability)])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(5, rows.size()):
		print("PIORES tesouro: ", rows[i])
	for i in mini(5, rows.size()):
		print("MELHORES tesouro: ", rows[rows.size() - 1 - i])


## Compara a participação de cada país no PIB/população do jogo com a histórica (data/real_economy_1836.json).
func _calibration() -> void:
	var f := FileAccess.open("res://data/real_economy_1836.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var pcs: Dictionary = d["gdp_pc_1836"]
	var def_pc: int = int(d["default_pc"])
	var rows: Array = []
	var real_total := 0.0
	var game_total := 0.0
	var pop_game_total := 0.0
	var pop_real_total := 0.0
	for c in g.countries:
		if not c.is_alive():
			continue
		var r: Dictionary = em.country_report(g, c.id)
		var real: float = float(pcs.get(c.tag, def_pc)) * float(c.pop_total)   # milhões de US$
		real_total += real
		game_total += float(r["gdp_nominal"])
		pop_game_total += float(r["population"])
		pop_real_total += float(c.pop_total) * 1000000.0
		rows.append([c.tag, c.name, real, float(r["gdp_nominal"]), float(c.pop_total) * 1000000.0, float(r["population"])])
	rows.sort_custom(func(a, b): return a[2] > b[2])
	print("CAL mundo: PIB real %.0f mi US$, PIB jogo %.0f | pop real %.0f mi, pop jogo %.0f mi" % [real_total, game_total, pop_real_total / 1e6, pop_game_total / 1e6])
	for i in mini(30, rows.size()):
		var r = rows[i]
		var rs: float = r[2] / real_total * 100.0
		var gs: float = r[3] / game_total * 100.0
		var pr: float = r[4] / pop_real_total * 100.0
		var pg: float = r[5] / pop_game_total * 100.0
		print("CAL %-4s %-26s PIB real %5.2f%% jogo %5.2f%% (x%.2f) | pop real %5.2f%% jogo %5.2f%% (x%.2f) | pop jogo/hist %.2f" % [r[0], r[1], rs, gs, gs / maxf(0.001, rs), pr, pg, pg / maxf(0.001, pr), r[5] / maxf(1.0, r[4])])


## Sonda (B13): distribuição de padrão de vida e renda per capita para calibrar a linha de pobreza.
func _demo_probe(year: int) -> void:
	var sol: Array = []
	var pc0: Array = []
	var pc1: Array = []
	var gini: Array = []
	var growth: Array = []
	for c in g.countries:
		if not c.is_alive():
			continue
		var e: Dictionary = g.estimate_monthly(c)
		sol.append(g.standard_of_living_x10(c, e))
		var ci: Dictionary = g.class_income(c)
		pc0.append(int(ci["pc"][0]))
		pc1.append(int(ci["pc"][1]))
		gini.append(int(ci["gini"]))
	sol.sort()
	pc0.sort()
	pc1.sort()
	gini.sort()
	print("SONDA ano %d | n %d | sol min/med/max %d/%d/%d | pc camponeses %d/%d/%d | pc operarios %d/%d/%d | gini %d/%d/%d" % [year, sol.size(), sol[0], sol[sol.size() / 2], sol[-1], pc0[0], pc0[pc0.size() / 2], pc0[-1], pc1[0], pc1[pc1.size() / 2], pc1[-1], gini[0], gini[gini.size() / 2], gini[-1]])


## Sonda (B25): de onde vem o crescimento do PIB — produção primária, fábricas, edifícios, população.
func _growth_probe(year: int) -> void:
	var prim := 0
	var pop := 0
	var fac := 0
	var fac_n := 0
	var lv := {}
	var tech := 0
	var lit := 0
	var n := 0
	for p in g.provinces:
		if p.owner_id < 0:
			continue
		prim += p.production()
		pop += p.population
		if p.factory != "" and p.factory_level > 0:
			fac += p.factory_level
			fac_n += 1
		for k in p.bld.keys():
			lv[k] = int(lv.get(k, 0)) + int(p.bld[k])
		lv["workshop"] = int(lv.get("workshop", 0)) + p.workshop
	for c in g.countries:
		if c.is_alive():
			n += 1
			tech += int(g.tech_fx(c)["prod"]) + int(g.tech_fx(c)["ind"])
			lit += c.literacy
	var parts := []
	for k in lv.keys():
		parts.append("%s %d" % [k, lv[k]])
	parts.sort()
	print("CRESC ano %d | prim %d | pop %d | prim/pop*1e6 %d | fabricas %d (niveis %d) | tech prod+ind medio %d | alfab media %d | edificios: %s" % [year, prim, pop, prim * 1000000 / maxi(1, pop), fac_n, fac, tech / maxi(1, n), lit / maxi(1, n), ", ".join(parts)])

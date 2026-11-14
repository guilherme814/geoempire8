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
	var start := _snapshot()
	print("ANO  0 | ", _fmt(start))
	for year in range(1, 11):
		for i in 365:
			g.step()
		var s := _snapshot()
		print("ANO %2d | " % year, _fmt(s))
		_check(year, s, start)
	print("--- alertas ---")
	for a in alerts:
		print("ALERT ", a)
	print("AUDIT-DONE ", alerts.size(), " alertas")
	_worst()
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
	if int(s["gdp"]) > int(start["gdp"]) * 3 or int(s["gdp"]) * 2 < int(start["gdp"]):
		alerts.append("ano %d: PIB mundial %d vs inicio %d (variacao >3x ou <0,5x)" % [year, s["gdp"], start["gdp"]])
	if int(s["pop"]) > int(start["pop"]) * 2 or int(s["pop"]) * 10 < int(start["pop"]) * 7:
		alerts.append("ano %d: populacao mundial %d vs inicio %d" % [year, s["pop"], start["pop"]])
	if int(s["tr_max"]) > 50000000:
		alerts.append("ano %d: tesouro maximo explodiu (%d)" % [year, s["tr_max"]])
	if int(s["un_max"]) > 20:
		alerts.append("ano %d: desemprego fora de 0..20" % year)


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

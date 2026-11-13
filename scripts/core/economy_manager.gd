extends Node
## Camada analítica da economia do GeoEmpire 8.
## Não substitui o motor econômico de Game: consome os dados e fórmulas já existentes.
## Todos os cálculos são determinísticos e usam inteiros sempre que possível,
## preservando o lockstep P2P. Histórico é analítico e não altera o estado da simulação.

const MAX_HISTORY := 120
const INVESTMENT_RATE_PCT := 15
const SHORTAGE_PCT := 115
const SURPLUS_PCT := 125

var _history_by_country: Dictionary = {}


func reset_history() -> void:
	_history_by_country.clear()


func get_history(country_id: int) -> Array:
	return (_history_by_country.get(country_id, []) as Array).duplicate(true)


func record_month(game: Node) -> void:
	if game == null or game.countries.is_empty():
		return

	# O tick mensal ocorre no primeiro dia do novo mês; o registro representa
	# o mês que acabou de terminar.
	var report_year: int = int(game.clock.year)
	var report_month: int = int(game.clock.month) - 1
	if report_month <= 0:
		report_month = 12
		report_year -= 1

	var market_tables: Array = game.market_tables()
	for country in game.countries:
		if not country.is_alive():
			continue
		var report := _calculate_country_report(game, country.id, market_tables)
		var rows: Array = _history_by_country.get(country.id, [])
		var previous: Dictionary = rows.back() if not rows.is_empty() else {}
		report["year"] = report_year
		report["month"] = report_month
		report["date_label"] = "%02d/%04d" % [report_month, report_year]
		report["gdp_growth_pct"] = _percentage_change(
			int(report["gdp_real"]), int(previous.get("gdp_real", report["gdp_real"]))
		)
		report["nominal_growth_pct"] = _percentage_change(
			int(report["gdp_nominal"]), int(previous.get("gdp_nominal", report["gdp_nominal"]))
		)
		report["inflation_pct"] = _percentage_change(
			int(report["price_index"]), int(previous.get("price_index", report["price_index"]))
		)
		rows.append(report)
		while rows.size() > MAX_HISTORY:
			rows.pop_front()
		_history_by_country[country.id] = rows


func country_report(game: Node, country_id: int) -> Dictionary:
	if game == null or country_id < 0 or country_id >= game.countries.size():
		return {}
	return _calculate_country_report(game, country_id, game.market_tables())


func _calculate_country_report(game: Node, country_id: int, market_tables: Array) -> Dictionary:
	var c = game.countries[country_id]
	var population: int = int(game.population_of(c))
	var primary_output := 0
	var factory_output := 0
	var intermediate_inputs := 0
	var factory_wages := 0
	var factory_net := 0
	var estimated_jobs := 0
	var factory_count := 0
	var primary_count := 0
	var goods_output: Dictionary = {}

	for pid in c.province_ids:
		var p: Province = game.provinces[int(pid)]
		primary_output += int(p.production())
		if p.resource_type != "":
			goods_output[p.resource_type] = int(goods_output.get(p.resource_type, 0)) + int(p.units())
		if p.side_timber() > 0:
			goods_output["timber"] = int(goods_output.get("timber", 0)) + int(p.side_timber())
		primary_count += 1

		# Capacidade de emprego é estimativa: o projeto ainda não contrata trabalhadores
		# individualmente. JOBS_PER_LEVEL é atualmente informativo no Province.
		for kind in Province.JOBS_PER_LEVEL.keys():
			var level: int = int(p.building_level(str(kind)))
			if level <= 0:
				continue
			estimated_jobs += int(Province.JOBS_PER_LEVEL[kind]) * level

		if p.factory != "" and p.factory_level > 0:
			var building: Dictionary = p.building_report(p.factory, p.factory_level, c.tax_pct)
			var revenue: int = int(building.get("revenue", 0))
			var inputs: int = int(building.get("inputs_cost", 0))
			factory_output += revenue
			intermediate_inputs += inputs
			factory_wages += int(building.get("wages", 0))
			factory_net += int(building.get("net", 0))
			factory_count += 1
			var product: String = str(building.get("product", ""))
			if product != "":
				goods_output[product] = int(goods_output.get(product, 0)) + int(building.get("units", 0))

	# PIB pelo valor agregado: produção primária + produção industrial - insumos
	# intermediários. Salários são parte do valor agregado, não uma dedução do PIB.
	var gdp_nominal: int = maxi(0, primary_output + factory_output - intermediate_inputs)
	var cpi: int = _weighted_price_index(game, country_id, market_tables)
	var gdp_real: int = gdp_nominal * 100 / maxi(1, cpi)
	var gdp_per_capita_x100: int = 0
	if population > 0:
		gdp_per_capita_x100 = gdp_nominal * 10000 / population

	var labor_force: int = population * 40 / 100
	var employment_capacity: int = mini(estimated_jobs, labor_force)
	var employment_pct: int = employment_capacity * 100 / maxi(1, labor_force)
	# Sem contratação efetiva no motor atual, desemprego não pode ser afirmado.
	# -1 sinaliza explicitamente que a estimativa ainda não é calculável.
	var unemployment_proxy: int = 100 - employment_pct if estimated_jobs > 0 else -1

	var e: Dictionary = game.estimate_monthly(c)
	var balance: int = int(c.last_income) - int(c.last_expense)
	var trade_balance := 0
	for good in game.goods_list():
		var imports: int = int(game.trade_imp[country_id].get(good, 0)) if country_id < game.trade_imp.size() else 0
		var exports: int = int(game.trade_exp[country_id].get(good, 0)) if country_id < game.trade_exp.size() else 0
		trade_balance += exports * Province.base_price(good) / 10
		trade_balance -= imports * Province.base_price(good) / 10

	var investment_flow: int = 0
	if Province.FACTORIES_PRIVATE:
		investment_flow = maxi(0, factory_net) * INVESTMENT_RATE_PCT / 100
	var industry_value_added: int = maxi(0, factory_output - intermediate_inputs)
	var sector_total: int = maxi(1, primary_output + industry_value_added)
	var primary_pct: int = primary_output * 100 / sector_total
	var industry_pct: int = industry_value_added * 100 / sector_total

	var top_provinces: Array = game.top_provinces(c, 5)
	var top_rows: Array = []
	for row in top_provinces:
		var p: Province = game.provinces[int(row["id"])]
		top_rows.append({
			"id": p.id, "name": p.name, "city": p.city,
			"tax": int(row["tax"]), "production": int(p.production())
		})

	return {
		"country_id": country_id,
		"country_name": str(c.name),
		"population": population,
		"gdp_nominal": gdp_nominal,
		"gdp_real": gdp_real,
		"gdp_per_capita_x100": gdp_per_capita_x100,
		"price_index": cpi,
		"inflation_pct": 0,
		"gdp_growth_pct": 0,
		"nominal_growth_pct": 0,
		"production_primary": primary_output,
		"production_industry_gross": factory_output,
		"intermediate_inputs": intermediate_inputs,
		"industry_value_added": industry_value_added,
		"primary_share_pct": primary_pct,
		"industry_share_pct": industry_pct,
		"services_share_pct": 0,
		"monthly_income": int(c.last_income),
		"monthly_expense": int(c.last_expense),
		"monthly_balance": balance,
		"treasury": int(c.treasury),
		"trade_balance": trade_balance,
		"imports_value": _trade_value(game, country_id, false),
		"exports_value": _trade_value(game, country_id, true),
		"investment_flow": investment_flow,
		"factory_wages": factory_wages,
		"factory_net_profit": factory_net,
		"estimated_jobs": estimated_jobs,
		"labor_force_estimate": labor_force,
		"employment_capacity_pct": employment_pct,
		"unemployment_proxy_pct": unemployment_proxy,
		"standard_of_living_x10": int(game.standard_of_living_x10(c, e)),
		"literacy_x10": int(c.literacy),
		"stability": int(c.stability),
		"factory_count": factory_count,
		"province_count": primary_count,
		"goods_output": goods_output,
		"top_provinces": top_rows
	}


func _weighted_price_index(game: Node, country_id: int, market_tables: Array) -> int:
	if country_id >= game.local_price.size():
		return 100
	var supply: Dictionary = market_tables[0][country_id]
	var demand: Dictionary = market_tables[1][country_id]
	var prices: Dictionary = game.local_price[country_id]
	var weighted_sum := 0
	var total_weight := 0
	for good in game.goods_list():
		var weight: int = int(demand.get(good, 0)) + int(supply.get(good, 0)) / 4
		if weight <= 0:
			continue
		weighted_sum += int(prices.get(good, 100)) * weight
		total_weight += weight
	if total_weight <= 0:
		return 100
	return clampi(weighted_sum / total_weight, 50, 250)


func _trade_value(game: Node, country_id: int, exports: bool) -> int:
	var total := 0
	var tables: Array = game.trade_exp if exports else game.trade_imp
	if country_id >= tables.size():
		return 0
	for good in game.goods_list():
		total += int(tables[country_id].get(good, 0)) * Province.base_price(good) / 100
	return total


func _percentage_change(current: int, previous: int) -> int:
	if previous <= 0:
		return 0
	return (current - previous) * 100 / previous


func global_rankings(game: Node) -> Array:
	var rows: Array = []
	var tables: Array = game.market_tables()
	for c in game.countries:
		if not c.is_alive():
			continue
		var report := _calculate_country_report(game, c.id, tables)
		rows.append({
			"id": c.id, "name": c.name, "tag": c.tag,
			"gdp_nominal": int(report["gdp_nominal"]),
			"gdp_real": int(report["gdp_real"]),
			"gdp_per_capita_x100": int(report["gdp_per_capita_x100"]),
			"population": int(report["population"])
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["gdp_nominal"]) == int(b["gdp_nominal"]):
			return int(a["id"]) < int(b["id"])
		return int(a["gdp_nominal"]) > int(b["gdp_nominal"])
	)
	return rows


func market_report(game: Node, country_id: int) -> Array:
	if country_id < 0 or country_id >= game.countries.size():
		return []
	var tables: Array = game.market_tables()
	var supply: Dictionary = tables[0][country_id]
	var demand: Dictionary = tables[1][country_id]
	var rows: Array = []
	for good in game.goods_list():
		var s: int = int(supply.get(good, 0))
		var d: int = int(demand.get(good, 0))
		var price: int = int(game.local_price[country_id].get(good, 100))
		var status := "equilibrado"
		if d * 100 > s * SHORTAGE_PCT:
			status = "escassez"
		elif s * 100 > d * SURPLUS_PCT:
			status = "excedente"
		rows.append({
			"good": good, "supply": s, "demand": d, "price_pct": price,
			"balance": s - d, "status": status,
			"imports": int(game.trade_imp[country_id].get(good, 0)),
			"exports": int(game.trade_exp[country_id].get(good, 0))
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_short: int = 1 if a["status"] == "escassez" else 0
		var b_short: int = 1 if b["status"] == "escassez" else 0
		if a_short != b_short:
			return a_short > b_short
		return int(a["price_pct"]) > int(b["price_pct"])
	)
	return rows


func bottlenecks(game: Node, country_id: int) -> Array:
	var result: Array = []
	for row in market_report(game, country_id):
		if str(row["status"]) == "escassez":
			result.append({
				"severity": "critical" if int(row["price_pct"]) >= 130 else "warning",
				"good": str(row["good"]),
				"supply": int(row["supply"]),
				"demand": int(row["demand"]),
				"price_pct": int(row["price_pct"]),
				"message": "Oferta insuficiente para atender a demanda."
			})
		elif str(row["status"]) == "excedente":
			result.append({
				"severity": "surplus", "good": str(row["good"]),
				"supply": int(row["supply"]), "demand": int(row["demand"]),
				"price_pct": int(row["price_pct"]),
				"message": "Excesso de oferta: considere novos consumidores ou exportações."
			})
	return result

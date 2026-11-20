class_name Consumption
extends RefCounted
## Consumo (B3): cestas de bens de cada classe. Dados puros e funções estáticas.
## Classes: 0 camponeses, 1 operários, 2 aristocratas, 3 burguesia, 4 funcionários, 5 soldados.
## Pesos somam 100 por classe. Os preços vêm de Game.local_price[país] (100 = preço-base).
## Grãos e tecido já pesam direto na satisfação (politics_of); a "cesta de conforto" é o resto.

const BASKETS := [
	{"grain": 60, "fish": 10, "livestock": 10, "fabric": 10, "tools": 10},
	{"grain": 40, "fabric": 20, "furniture": 10, "tools": 10, "sugar": 10, "tobacco": 10},
	{"wine": 25, "silk": 20, "spices": 15, "furniture": 20, "sugar": 10, "tea": 10},
	{"furniture": 20, "coffee": 15, "tea": 15, "silk": 15, "wine": 15, "tools": 10, "sugar": 10},
	{"grain": 25, "fabric": 20, "furniture": 15, "tea": 15, "coffee": 10, "sugar": 10, "tobacco": 5},
	{"grain": 40, "livestock": 15, "fabric": 15, "tobacco": 15, "wine": 15},
]
const BASIC := ["grain", "fabric"]     # já tratados em politics_of
const COMFORT_DIV := 8                 # cada 8 pontos de preço = 1 ponto de satisfação
const TERM_MIN := -5
const TERM_MAX := 3


## Índice de preço (100 = base) dos itens da cesta; com `comfort_only`, ignora grãos e tecido.
@warning_ignore("integer_division")
static func price_index(lp: Dictionary, cls: int, comfort_only: bool) -> int:
	var basket: Dictionary = BASKETS[cls]
	var sum := 0
	var w := 0
	for g in basket.keys():
		if comfort_only and BASIC.has(g):
			continue
		var wt: int = int(basket[g])
		sum += wt * int(lp.get(str(g), 100))
		w += wt
	return sum / w if w > 0 else 100


## Efeito da cesta de conforto na satisfação-alvo da classe: barata (+), cara (−).
@warning_ignore("integer_division")
static func comfort_term(lp: Dictionary, cls: int) -> int:
	var idx := price_index(lp, cls, true)
	return clampi(-(idx - 100) / COMFORT_DIV, TERM_MIN, TERM_MAX)

class_name Government
extends RefCounted
## Governo (Fase 5): orçamento por ministérios e decretos temporários.
## Dados puros e funções estáticas — sem dependência do autoload Game.
## Estado (em Country): `budget_code` (nível de cada ministério, base 3), `decree`, `decree_left`, `decree_cd`.
## Classes: 0 camponeses, 1 operários, 2 aristocratas, 3 burguesia, 4 funcionários, 5 soldados.

const LEVEL_NAMES := ["Cortado", "Normal", "Reforçado"]
const DECREE_COOLDOWN := 12
const WELFARE_PER_PROVINCE := 3      # custo mensal de 100% da assistência, por província
const DEFAULT_CODE := 13             # edu 1, exército 1, administração 1, assistência 0

## pct = custo em % do normal; eff = efeito principal em % (por nível); sat = {classe: [cortado, normal, reforçado]}.
const MINISTRIES := [
	{"id": "edu", "name": "Educação", "pct": [60, 100, 140], "eff": [-20, 0, 25],
		"eff_text": "crescimento da alfabetização", "sat": {4: [-3, 0, 2]}},
	{"id": "army", "name": "Forças Armadas", "pct": [70, 100, 130], "eff": [0, 0, 0],
		"eff_text": "lealdade dos soldados", "sat": {5: [-8, 0, 6]}},
	{"id": "admin", "name": "Administração", "pct": [70, 100, 140], "eff": [-4, 0, 5],
		"eff_text": "arrecadação de impostos", "sat": {4: [-4, 0, 3]}},
	{"id": "welfare", "name": "Assistência social", "pct": [0, 50, 100], "eff": [0, 0, 0],
		"eff_text": "satisfação de camponeses e operários", "sat": {0: [0, 3, 6], 1: [0, 3, 6]}},
]

## cost = ouro ao decretar; dur = meses; exp = % sobre despesas de ministérios; tax/ind/lit = % sobre os ganhos;
## sat = {classe: deslocamento}, "all" = todas as classes.
const DECREES := [
	{"name": "Austeridade", "desc": "Corta 15% das despesas dos ministérios, mas o povo sofre.", "cost": 0, "dur": 12,
		"exp": -15, "tax": 0, "ind": 0, "lit": 0, "all": -3, "sat": {}},
	{"name": "Estado de emergência", "desc": "Ordem pela força: mais estabilidade, menos arrecadação.", "cost": 0, "dur": 12,
		"exp": 0, "tax": -8, "ind": 0, "lit": 0, "all": 5, "sat": {}},
	{"name": "Incentivo industrial", "desc": "Subsídios às fábricas: +15% na renda industrial do Estado.", "cost": 150, "dur": 12,
		"exp": 0, "tax": 0, "ind": 15, "lit": 0, "all": 0, "sat": {3: 3, 1: -2}},
	{"name": "Campanha de alfabetização", "desc": "Mutirão de ensino: alfabetização cresce 40% mais rápido.", "cost": 120, "dur": 12,
		"exp": 0, "tax": 0, "ind": 0, "lit": 40, "all": 0, "sat": {4: 2}},
]


static func level(code: int, m: int) -> int:
	var v := code
	for i in m:
		v /= 3
	return v % 3


static func with_level(code: int, m: int, lv: int) -> int:
	var p := 1
	for i in m:
		p *= 3
	return code + (lv - level(code, m)) * p


static func pct(code: int, m: int) -> int:
	return int((MINISTRIES[m]["pct"] as Array)[level(code, m)])


static func eff(code: int, m: int) -> int:
	return int((MINISTRIES[m]["eff"] as Array)[level(code, m)])


static func decree_field(decree: int, key: String) -> int:
	if decree < 0 or decree >= DECREES.size():
		return 0
	return int(DECREES[decree][key])


## Deslocamento da satisfação-alvo de cada classe por orçamento e decreto.
static func sat_shift(code: int, decree: int) -> Array:
	var out := [0, 0, 0, 0, 0, 0]
	for m in MINISTRIES.size():
		var sat: Dictionary = MINISTRIES[m]["sat"]
		for k in sat.keys():
			out[int(k)] += int((sat[k] as Array)[level(code, m)])
	if decree >= 0 and decree < DECREES.size():
		var d: Dictionary = DECREES[decree]
		for i in 6:
			out[i] += int(d["all"])
		var ds: Dictionary = d["sat"]
		for k in ds.keys():
			out[int(k)] += int(ds[k])
	return out

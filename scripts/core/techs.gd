class_name Techs
extends RefCounted
## Árvore de tecnologias (dado estático, estilo Victoria 3): 36 tecnologias em 3 categorias
## (Produção, Militar, Sociedade) e 6 eras. O id é o índice em ALL; a era `e` ocupa os ids
## 6*(e-1) .. 6*e-1 (2 de cada categoria). O nível de tecnologia do país = tecnologias / 6.
## Uma tecnologia da era `e` só pode ser estudada quando o país já está no nível e-1.
## Efeitos (inteiros, em %): prod produção, ind lucro industrial, trade comércio, tax imposto,
## army desconto na manutenção do exército, mp mão de obra, atk ataque, def defesa,
## nav força naval (pontos), lit crescimento da alfabetização, tech pesquisa, stab estabilidade
## (pontos), pop crescimento populacional (centésimos de % ao mês).

const PER_ERA := 6
const MAX_ERA := 6
const FX_KEYS := ["prod", "ind", "trade", "tax", "army", "mp", "atk", "def", "nav", "lit", "tech", "stab", "pop"]
const FX_LABEL := {
	"prod": "Produção", "ind": "Lucro industrial", "trade": "Comércio", "tax": "Imposto",
	"army": "Manutenção do exército", "mp": "Mão de obra", "atk": "Ataque", "def": "Defesa",
	"nav": "Força naval", "lit": "Alfabetização", "tech": "Pesquisa", "stab": "Estabilidade",
	"pop": "Crescimento populacional",
}
const CAT_ORDER := ["prod", "mil", "soc"]
const CATS := {
	"prod": {"name": "Produção", "icon": "hammer"},
	"mil": {"name": "Militar", "icon": "shield"},
	"soc": {"name": "Sociedade", "icon": "book"},
}

const ALL := [
	# Era 1
	{"cat": "prod", "era": 1, "name": "Rotação de culturas", "fx": {"prod": 3}},
	{"cat": "prod", "era": 1, "name": "Mecânica de precisão", "fx": {"ind": 5}},
	{"cat": "mil", "era": 1, "name": "Mosquete padronizado", "fx": {"atk": 4}},
	{"cat": "mil", "era": 1, "name": "Escola de oficiais", "fx": {"mp": 4, "def": 3}},
	{"cat": "soc", "era": 1, "name": "Alfabetização paroquial", "fx": {"lit": 10}},
	{"cat": "soc", "era": 1, "name": "Cartografia e estatística", "fx": {"tech": 4, "tax": 1}},
	# Era 2
	{"cat": "prod", "era": 2, "name": "Vapor de alta pressão", "fx": {"ind": 8, "prod": 2}},
	{"cat": "prod", "era": 2, "name": "Bancos comerciais", "fx": {"trade": 8, "tax": 1}},
	{"cat": "mil", "era": 2, "name": "Cápsula de percussão", "fx": {"atk": 6}},
	{"cat": "mil", "era": 2, "name": "Intendência militar", "fx": {"army": 4}},
	{"cat": "soc", "era": 2, "name": "Escolas normais", "fx": {"lit": 12}},
	{"cat": "soc", "era": 2, "name": "Sanidade pública", "fx": {"pop": 2}},
	# Era 3
	{"cat": "prod", "era": 3, "name": "Locomotiva a vapor", "fx": {"prod": 4, "trade": 6}},
	{"cat": "prod", "era": 3, "name": "Fertilizantes químicos", "fx": {"prod": 5}},
	{"cat": "mil", "era": 3, "name": "Fuzil raiado", "fx": {"atk": 6, "def": 4}},
	{"cat": "mil", "era": 3, "name": "Casco a vapor e hélice", "fx": {"nav": 2}},
	{"cat": "soc", "era": 3, "name": "Código civil", "fx": {"tax": 2, "stab": 2}},
	{"cat": "soc", "era": 3, "name": "Imprensa a vapor", "fx": {"tech": 6, "lit": 6}},
	# Era 4
	{"cat": "prod", "era": 4, "name": "Processo Bessemer", "fx": {"ind": 10}},
	{"cat": "prod", "era": 4, "name": "Telégrafo elétrico", "fx": {"trade": 8, "tax": 2}},
	{"cat": "mil", "era": 4, "name": "Artilharia raiada de culatra", "fx": {"atk": 7}},
	{"cat": "mil", "era": 4, "name": "Ferrovia militar", "fx": {"mp": 6, "army": 4}},
	{"cat": "soc", "era": 4, "name": "Universidade de pesquisa", "fx": {"tech": 10}},
	{"cat": "soc", "era": 4, "name": "Parlamento e sufrágio", "fx": {"stab": 3, "lit": 6}},
	# Era 5
	{"cat": "prod", "era": 5, "name": "Maquinário mecanizado", "fx": {"ind": 12, "prod": 3}},
	{"cat": "prod", "era": 5, "name": "Conservas e refrigeração", "fx": {"prod": 4, "pop": 2}},
	{"cat": "mil", "era": 5, "name": "Arame farpado e metralhadora", "fx": {"def": 9}},
	{"cat": "mil", "era": 5, "name": "Encouraçados", "fx": {"nav": 3}},
	{"cat": "soc", "era": 5, "name": "Sindicatos reconhecidos", "fx": {"stab": 4}},
	{"cat": "soc", "era": 5, "name": "Escolaridade obrigatória", "fx": {"lit": 15}},
	# Era 6
	{"cat": "prod", "era": 6, "name": "Eletricidade industrial", "fx": {"ind": 14, "prod": 4}},
	{"cat": "prod", "era": 6, "name": "Motor de combustão", "fx": {"trade": 10, "prod": 3}},
	{"cat": "mil", "era": 6, "name": "Artilharia de tiro rápido", "fx": {"atk": 9}},
	{"cat": "mil", "era": 6, "name": "Estado-maior geral", "fx": {"army": 6, "mp": 8, "def": 4}},
	{"cat": "soc", "era": 6, "name": "Seguridade social", "fx": {"stab": 5, "pop": 3}},
	{"cat": "soc", "era": 6, "name": "Método científico aplicado", "fx": {"tech": 12}},
]


static func cost(id: int) -> int:
	return 50 + 10 * int(ALL[id]["era"])


static func icon_of(id: int) -> String:
	return str(CATS[str(ALL[id]["cat"])]["icon"])


## Pode ser estudada agora? (ainda não dominada e dentro da era liberada pelo nível do país)
static func available(c: Country, id: int) -> bool:
	if id < 0 or id >= ALL.size():
		return false
	if c.techs.has(id):
		return false
	return int(ALL[id]["era"]) <= c.tech_level() + 1


## Escolha da IA: categoria conforme a situação (guerra, alfabetização baixa) + soma dos efeitos.
static func score(id: int, at_war: bool, low_literacy: bool) -> int:
	var t: Dictionary = ALL[id]
	var w: int = 30
	match str(t["cat"]):
		"mil":
			w = 10 + (40 if at_war else 0)
		"soc":
			w = 14 + (14 if low_literacy else 0)
	var s: int = w * 10
	var fx: Dictionary = t["fx"]
	for k in fx.keys():
		s += int(fx[k])
	return s


static func fx_text(fx: Dictionary) -> String:
	var parts: Array = []
	for k in FX_KEYS:
		if not fx.has(k):
			continue
		var v: int = int(fx[k])
		match k:
			"army":
				parts.append("%s -%d%%" % [FX_LABEL[k], v])
			"stab":
				parts.append("%s +%d" % [FX_LABEL[k], v])
			"nav":
				parts.append("%s +%d" % [FX_LABEL[k], v])
			"pop":
				parts.append("%s +%d,%02d%%/mês" % [FX_LABEL[k], v / 100, v % 100])
			_:
				parts.append("%s +%d%%" % [FX_LABEL[k], v])
	return ", ".join(parts)

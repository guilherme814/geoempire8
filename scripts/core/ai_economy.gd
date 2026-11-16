class_name AiEconomy
extends RefCounted
## Inteligência econômica da IA (GEAI): política fiscal e prioridades de investimento moldadas
## pela personalidade do país e pelo estado de guerra. Só lê o estado do jogo (sem rng).
##   - Impostos: sobem na crise (ou na guerra com caixa curto) enquanto a estabilidade aguenta, e
##     descem com folga de caixa para a população e a economia respirarem.
##   - Investimento: a ordem de construção muda com a personalidade (comerciantes priorizam
##     mercados/portos/bancos; estratégicos, educação; agressivos, minas e telégrafos) e, em
##     guerra, suprimentos (depósitos), fazendas, minas e madeira vêm primeiro.

const TAX_MIN := 12
const TAX_MAX := 45
const TRADE_TAGS := ["GBR", "NED", "POR", "DEN", "SWE", "USA", "BEL", "HAW", "OMA"]

const PRIORITY := {
	"aggressive": ["mine", "telegraph", "farm"],
	"cautious": ["farm", "hospital", "market"],
	"defensive": ["farm", "hospital", "depot"],
	"opportunist": ["market", "bank", "dock"],
	"strategic": ["school", "university", "library"],
}
const WAR_FIRST := ["depot", "farm", "mine", "logging"]
const TRADE_FIRST := ["market", "dock", "bank"]


## Estabilidade mínima para a IA ainda subir impostos, por personalidade.
static func _stab_floor(pers: String) -> int:
	match pers:
		"aggressive", "opportunist":
			return 35
		"cautious", "defensive":
			return 48
	return 42


## Pura: nova alíquota (±1/±2 por mês). `months` = tesouro em meses de despesa.
@warning_ignore("integer_division")
static func tax_step(tax: int, net: int, treasury: int, expense: int, stability: int, at_war: bool, pers: String) -> int:
	var months: int = treasury / maxi(1, expense)
	var floor_: int = _stab_floor(pers)
	var want := tax
	var crisis: bool = treasury < 0 or (net < 0 and months < 3)
	if crisis:
		if stability >= floor_:
			want = tax + 2
	elif at_war and months < 6 and net <= 0:
		if stability >= floor_:
			want = tax + 1
	elif months > 24 or (months > 14 and net > 0 and stability < 70):
		want = tax - 1
	return clampi(want, TAX_MIN, TAX_MAX)


## Ordem de construção: kinds preferidos primeiro (só os que já estão na ordem base).
static func build_order(base: Array, pers: String, at_war: bool, tag: String) -> Array:
	var front: Array = []
	if at_war:
		front.append_array(WAR_FIRST)
	if TRADE_TAGS.has(tag):
		front.append_array(TRADE_FIRST)
	front.append_array(PRIORITY.get(pers, []))
	var out: Array = []
	for k in front:
		if base.has(k) and not out.has(k):
			out.append(k)
	for k in base:
		if not out.has(k):
			out.append(k)
	return out


## Revisão mensal: ajusta a alíquota do país (IA).
static func review_taxes(g: Node, c) -> void:
	var pers := AiWar.personality_key(g, c)
	var net: int = int(c.last_income) - int(c.last_expense)
	c.tax_pct = tax_step(int(c.tax_pct), net, int(c.treasury), int(c.last_expense), int(c.stability), not g.wars_of(c.id).is_empty(), pers)

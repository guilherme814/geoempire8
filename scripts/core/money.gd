class_name Money
extends RefCounted
## Moeda do jogo: libra esterlina (£), padrão de 1836. Os valores internos são inteiros ("unidades");
## 1 unidade = GBP_PER_UNIT libras. A escala foi escolhida para que o PIB do Reino Unido fique perto
## da renda nacional britânica de 1836 (~£500 milhões por ano). Só formatação: a simulação segue em inteiros.

const GBP_PER_UNIT := 7000


static func _dec(x: float, digits: int) -> String:
	return ("%." + str(digits) + "f") % x


## Ex.: 712 -> "£5,0 mi"; 140 -> "£980 mil"; -3 -> "-£21 mil"
static func fmt(units: int) -> String:
	var v: int = units * GBP_PER_UNIT
	var a: int = absi(v)
	var sign: String = "-" if v < 0 else ""
	var body: String
	if a < 1000:
		body = "£%d" % a
	elif a < 1000000:
		body = "£%d mil" % (a / 1000)
	elif a < 1000000000:
		body = "£" + _dec(float(a) / 1000000.0, 1).replace(".", ",") + " mi"
	else:
		body = "£" + _dec(float(a) / 1000000000.0, 2).replace(".", ",") + " bi"
	return sign + body


## Com sinal explícito: "+£5,0 mi" / "-£21 mil" / "£0".
static func signed(units: int) -> String:
	if units > 0:
		return "+" + fmt(units)
	return fmt(units)

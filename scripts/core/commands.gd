class_name Cmd
extends RefCounted
## Comandos de jogo: a ÚNICA forma de a UI/IA alterar o estado.
## São Dictionaries simples (serializáveis) para viajar pela rede P2P.
##
## Campos comuns:
##   type   -> uma das constantes abaixo
##   issuer -> id do país que emitiu (preenchido por Game.submit_command)
##
## Para criar um comando novo: adicione a constante e a factory aqui e
## trate-o em Game.apply_command() (e valide em Net._rpc_submit se precisar).

const SET_SPEED := "set_speed"
const SET_TAX := "set_tax"
const TRANSFER_PROVINCE := "transfer_province"   # debug / base para conquista


static func set_speed(speed: int) -> Dictionary:
	return {"type": SET_SPEED, "speed": speed}


static func set_tax(country: int, pct: int) -> Dictionary:
	return {"type": SET_TAX, "country": country, "pct": pct}


static func transfer_province(province: int, to_country: int) -> Dictionary:
	return {"type": TRANSFER_PROVINCE, "province": province, "to": to_country}

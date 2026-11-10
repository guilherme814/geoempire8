class_name Cmd
extends RefCounted
## Comandos de jogo: a ÚNICA forma de a UI/IA alterar o estado.
## São Dictionaries simples (serializáveis) para viajar pela rede P2P.
##
## Campos comuns:
##   type   -> uma das constantes abaixo
##   issuer -> id do país que emitiu (preenchido por Game.submit_command)
##
## A VALIDAÇÃO fica em Game.apply_command (roda igual em todos os pares): o comando
## só vale se o emissor for dono da província/exército, tiver ouro, etc.
##
## Para criar um comando novo: adicione a constante e a factory aqui e trate-o em
## Game.apply_command().

const SET_SPEED := "set_speed"
const SET_TAX := "set_tax"
const RECRUIT := "recruit"
const BUILD := "build"
const MOVE_ARMY := "move_army"
const STOP_ARMY := "stop_army"
const DISBAND_ARMY := "disband_army"
const CHOOSE_EVENT := "choose_event"
const IMPROVE_RELATIONS := "improve_relations"
const PROPOSE_ALLIANCE := "propose_alliance"
const BREAK_ALLIANCE := "break_alliance"
const MOVE_FLEET := "move_fleet"
const STOP_FLEET := "stop_fleet"
const BUILD_SHIP := "build_ship"
const EMBARGO := "embargo"
const LIFT_EMBARGO := "lift_embargo"
const DECLARE_WAR := "declare_war"
const MAKE_PEACE := "make_peace"
const TRANSFER_PROVINCE := "transfer_province"   # debug / base para conquista


static func set_speed(speed: int) -> Dictionary:
	return {"type": SET_SPEED, "speed": speed}


static func set_tax(country: int, pct: int) -> Dictionary:
	return {"type": SET_TAX, "country": country, "pct": pct}


## Recruta 1 regimento na província (custa ouro + mão de obra; treina por alguns dias).
static func recruit(province: int) -> Dictionary:
	return {"type": RECRUIT, "province": province}


## kind: "workshop" (+25% produção por nível) ou "barracks" (+1% mão de obra por nível).
static func build(province: int, kind: String) -> Dictionary:
	return {"type": BUILD, "province": province, "kind": kind}


static func move_army(army: int, to_province: int) -> Dictionary:
	return {"type": MOVE_ARMY, "army": army, "to": to_province}


static func stop_army(army: int) -> Dictionary:
	return {"type": STOP_ARMY, "army": army}


static func disband_army(army: int) -> Dictionary:
	return {"type": DISBAND_ARMY, "army": army}


## Escolhe uma opção de um evento pendente (uid vem de Game.pending_events).
static func choose_event(uid: int, option: int) -> Dictionary:
	return {"type": CHOOSE_EVENT, "uid": uid, "option": option}


static func transfer_province(province: int, to_country: int) -> Dictionary:
	return {"type": TRANSFER_PROVINCE, "province": province, "to": to_country}


## Declara guerra ao país alvo (o emissor é o agressor).
static func declare_war(target: int) -> Dictionary:
	return {"type": DECLARE_WAR, "target": target}


## Propõe paz branca (vale após Game.WAR_MIN_DAYS dias de guerra; sem IA, é aceita na hora).
static func make_peace(target: int) -> Dictionary:
	return {"type": MAKE_PEACE, "target": target}


## Gasta ouro para melhorar a opinião do país alvo (+20).
static func improve_relations(target: int) -> Dictionary:
	return {"type": IMPROVE_RELATIONS, "target": target}


static func propose_alliance(target: int) -> Dictionary:
	return {"type": PROPOSE_ALLIANCE, "target": target}


static func break_alliance(target: int) -> Dictionary:
	return {"type": BREAK_ALLIANCE, "target": target}


## Constrói 1 navio em um porto (província costeira própria).
static func build_ship(province: int) -> Dictionary:
	return {"type": BUILD_SHIP, "province": province}


## Embargo: proíbe todo comércio entre o emissor e o alvo (nos dois sentidos).
static func embargo(target: int) -> Dictionary:
	return {"type": EMBARGO, "target": target}


static func lift_embargo(target: int) -> Dictionary:
	return {"type": LIFT_EMBARGO, "target": target}


## Manda a frota navegar até uma célula do mar (índice y * sea_w + x).
static func move_fleet(fleet: int, to_cell: int) -> Dictionary:
	return {"type": MOVE_FLEET, "fleet": fleet, "cell": to_cell}


static func stop_fleet(fleet: int) -> Dictionary:
	return {"type": STOP_FLEET, "fleet": fleet}

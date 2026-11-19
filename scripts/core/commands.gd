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
const RELEASE_VASSAL := "release_vassal"
const ANNEX_VASSAL := "annex_vassal"
const ACCEPT_PEACE := "accept_peace"
const REJECT_PEACE := "reject_peace"
const ENACT_LAW := "enact_law"
const SET_RESEARCH := "set_research"
const SET_RESEARCH_TARGET := "set_research_target"
const SET_IMMIGRATION := "set_immigration"
const SET_AUTO_FRONT := "set_auto_front"
const TAKE_LOAN := "take_loan"
const REPAY_LOAN := "repay_loan"
const SET_DRILL := "set_drill"
const SEND_AID := "send_aid"
const SPY := "spy"
const SET_METHOD := "set_method"
const TRANSFER_PROVINCE := "transfer_province"   # debug / base para conquista


## Empréstimo de um degrau (Game.LOAN_STEP) e amortização do mesmo valor.
static func take_loan() -> Dictionary:
	return {"type": TAKE_LOAN}


static func repay_loan() -> Dictionary:
	return {"type": REPAY_LOAN}


## Instrução das tropas: 0 recrutas, 1 regulares, 2 elite.
static func set_drill(level: int) -> Dictionary:
	return {"type": SET_DRILL, "level": level}


## Troca o método de produção da fábrica de uma província (índice em Province.METHODS).
static func set_method(province: int, method: int) -> Dictionary:
	return {"type": SET_METHOD, "province": province, "method": method}


## Operação de espionagem contra outro país (op: 0 roubar tecnologia, 1 sabotar economia, 2 insuflar descontentamento).
static func spy(target: int, op: int) -> Dictionary:
	return {"type": SPY, "target": target, "op": op}


## Ajuda financeira a outro país (melhora a opinião).
static func send_aid(target: int) -> Dictionary:
	return {"type": SEND_AID, "target": target}


static func set_speed(speed: int) -> Dictionary:
	return {"type": SET_SPEED, "speed": speed}


## Aprova uma lei: `group` = índice em Laws.GROUPS, `option` = opção escolhida.
static func enact_law(group: int, option: int) -> Dictionary:
	return {"type": ENACT_LAW, "group": group, "option": option}


## Liga/desliga o avanço automático dos exércitos à linha de frente.
static func set_auto_front(enabled: bool) -> Dictionary:
	return {"type": SET_AUTO_FRONT, "enabled": enabled}


## Define o investimento em pesquisa (% da renda, múltiplo de 5).
static func set_research(pct: int) -> Dictionary:
	return {"type": SET_RESEARCH, "pct": pct}


static func set_immigration(policy: int) -> Dictionary:
	return {"type": SET_IMMIGRATION, "policy": policy}


static func set_research_target(tech: int) -> Dictionary:
	return {"type": SET_RESEARCH_TARGET, "tech": tech}


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


## Propõe paz (vale após Game.WAR_MIN_DAYS dias de guerra). `term`: "white", "indemnity",
## "vassal" ou "annex" (cada um exige uma pontuação de guerra mínima, ver Game.war_score).
static func make_peace(target: int, term: String = "white") -> Dictionary:
	return {"type": MAKE_PEACE, "target": target, "term": term}


static func release_vassal(target: int) -> Dictionary:
	return {"type": RELEASE_VASSAL, "target": target}


static func annex_vassal(target: int) -> Dictionary:
	return {"type": ANNEX_VASSAL, "target": target}


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


## Aceita/recusa a proposta de paz feita por `from` (IA) ao emissor.
static func accept_peace(from: int) -> Dictionary:
	return {"type": ACCEPT_PEACE, "from": from}


static func reject_peace(from: int) -> Dictionary:
	return {"type": REJECT_PEACE, "from": from}

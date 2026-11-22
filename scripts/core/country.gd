class_name Country
extends RefCounted
## País. O estado que muda (tesouro, imposto) entra no snapshot de rede.

var id: int = 0
var tag: String = ""
var name: String = ""
var color: Color = Color.GRAY
var capital: int = -1
var pop_total: float = 0.0   # milhões, dado histórico (define o exército inicial)

var treasury: int = 0
var tax_pct: int = 30
var last_income: int = 0
var last_expense: int = 0
var literacy: int = 100       # alfabetização em décimos de % (100 = 10,0%)
var immigration: int = 1       # política: 0 fechada, 1 seletiva, 2 aberta
var migr_in: int = 0           # imigrantes recebidos no último mês
var migr_out: int = 0          # emigrantes no último mês
var research_pct: int = 0      # % da renda investido em pesquisa (0..RESEARCH_MAX_PCT)
var tech_pts: int = 0         # banco de pontos de pesquisa (gastos na tecnologia em estudo)
var techs: Array = []         # ids (Techs.ALL) das tecnologias dominadas
var researching: int = -1     # tecnologia em estudo (-1 = nenhuma)
var fx: Dictionary = {}       # efeitos acumulados das tecnologias (cache; recalculado ao carregar)
var fx_dirty: bool = true
var lit_acc: int = 0          # resto fracionário do crescimento da alfabetização
var sat: Array = [50, 50, 50, 50, 50, 50]   # satisfação (0-100) de cada classe social
var stability: int = 50       # estabilidade interna (0-100), média ponderada da satisfação
var auto_front: bool = true   # exércitos parados vão sozinhos à linha de frente em guerra
var laws: Array = []         # opção em vigor de cada grupo de leis (ver Laws.GROUPS)
var law_cd: Array = []        # meses de espera até poder mudar cada grupo
var overlord: int = -1        # suserano (-1 = independente); vassalo paga tributo e segue o suserano
var overlord_since: int = 0   # dia (tick) em que virou vassalo
var debt: int = 0             # dívida (empréstimos) em ouro
var infamy: int = 0             # infâmia: sobe ao atacar/anexar, cai devagar
var budget_code: int = 13       # orçamento: nível de cada ministério (Government)
var decree: int = -1            # decreto em vigor (-1 = nenhum)
var decree_left: int = 0        # meses restantes do decreto
var decree_cd: int = 0          # meses até poder decretar de novo
var private_capital: int = 0     # capital privado acumulado (B7), reinvestido nas fábricas
var tariff: int = 10               # tarifa de importação (%, B8)
var grp_tax: int = 0              # efeito dos grupos de interesse na arrecadação (%, B16)
var grp_trade: int = 0            # efeito dos grupos de interesse no comércio (%, B16)
var bill_g: int = -1              # projeto de lei em votação: grupo (-1 = nenhum) (B17)
var bill_o: int = -1              # opção proposta
var bill_p: int = 0               # fases vencidas (0..3)
var bill_s: int = 0               # reveses (0..3)
var bill_a: int = 0               # meses em tramitação
var radical: Array = [0, 0, 0, 0, 0]   # radicalização por corrente 0..1000 (B18)
var plan_sector: int = -1         # setor em plano quinquenal (índice em Province.FACTORIES) (B23)
var plan_left: int = 0            # meses restantes do plano
var plan_cd: int = 0              # carência para novo plano
var sub_mask: int = 0             # setores subsidiados (bits)
var nat_mask: int = 0             # setores estatizados (bits)
var mono_good: int = -1           # recurso sob monopólio estatal (índice em Province.RESOURCE_PRICE) (B23)
var culture: int = -1             # cultura de Estado (índice em Cultures) (B22)
var faith: int = -1               # religião de Estado (B22)
var culture_policy: int = 0       # 0 tolerância, 1 assimilação (B22)
var faith_policy: int = 0         # 0 tolerância, 1 conversão (B22)
var poverty: int = 50             # % da população na miséria 0..100 (B13)
var famine_pct: int = 0           # % das províncias em fome neste mês (B13)
var admin: int = 0                # nível da administração pública 0..5 (B21)
var anticorr: int = 0             # meses restantes da campanha anticorrupção (B21)
var security: int = 0             # guarda nacional / polícia secreta 0..3 (B20)
var repress_left: int = 0         # meses de repressão ativa (B20)
var siege_left: int = 0           # meses de estado de sítio (B20)
var order_cd: int = 0             # carência para nova repressão/sítio (B20)
var concede_cd: int = 0           # carência para nova concessão (B20)
var rev_cd: int = 0               # carência (meses) após golpe/revolução (B19)
var rev_type: int = 0             # último desfecho: 0 nenhum, 1 golpe, 2 revolução
var rev_clock: int = 0            # relógio da revolução 0..12 (B18)
var strikes: int = 0              # % de províncias em protesto/greve (B18)
var elect_cd: int = 24            # meses até a próxima eleição (B15)
var seats: Array = [0, 0, 0, 0, 0]   # cadeiras do parlamento por corrente (100 no total; vazio = sem eleição)
var panic_left: int = 0           # meses restantes de pânico financeiro (B12)
var excise: int = 0               # imposto de consumo (%, B10)
var interest: int = 2              # juros mensais sobre a dívida (%, B9)
var inflation: int = 0             # inflação acumulada (pontos, B9)
var spy_cd: int = 0             # meses até a próxima operação de espionagem
var drill: int = 0            # instrução das tropas: 0 recrutas, 1 regulares, 2 elite
var ships: int = 0            # frota (capacidade de comércio marítimo e bloqueio)

# Derivados (recalculados por Game._refresh_country_geometry)
var province_ids: Array[int] = []
var bounds: Rect2 = Rect2()       # do maior bloco contínuo de províncias
var label_pos: Vector2 = Vector2.ZERO
var label_size: int = 16


static func from_dict(d: Dictionary) -> Country:
	var c := Country.new()
	c.id = int(d["id"])
	c.tag = str(d.get("tag", ""))
	c.name = str(d["name"])
	c.color = Color.html(str(d["color"]))
	c.capital = int(d["capital"])
	c.pop_total = float(d.get("pop_total", 1.0))
	return c


const TECH_STEP := 400


## Nível = tecnologias dominadas / 6 (uma era completa por nível), no máximo Techs.MAX_ERA.
@warning_ignore("integer_division")
func tech_level() -> int:
	return mini(Techs.MAX_ERA, techs.size() / Techs.PER_ERA)


func is_alive() -> bool:
	return not province_ids.is_empty()

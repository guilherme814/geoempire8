class_name Onboarding
extends RefCounted
## Primeiro acesso: boas-vindas no menu e tutorial em páginas na primeira campanha.
## Os marcadores ficam em user://settings.cfg (AppSettings), fora do save.

const SEC := "onboarding"

const PAGES := [
	{"title": "O objetivo", "body": "Conduza uma nação por [b]176 anos[/b] (1836–2012): prosperar, expandir-se e sobreviver às guerras. Cada país começa com seus governantes, economia e vizinhos históricos."},
	{"title": "Navegando no mapa", "body": "[b]Arraste[/b] com um dedo para mover o mapa e use a [b]pinça[/b] para dar zoom. [b]Toque numa província[/b] para ver população, dono e construções."},
	{"title": "Barra superior", "body": "Mostra o [b]tesouro[/b] (e o saldo por mês), a população, a alfabetização, o padrão de vida, a tecnologia, a estabilidade e o exército.\n\nSaldo [color=#e0705f]vermelho[/color] é déficit: ajuste impostos e gastos antes que o dinheiro acabe."},
	{"title": "Painéis laterais", "body": "Os ícones laterais abrem [b]Tecnologia, Economia, Mercado, Política, Governantes, Leis e Diplomacia[/b]. Toque de novo no ícone, ou no X, para fechar."},
	{"title": "Controle do tempo", "body": "Use os botões de velocidade para [b]pausar[/b] ou acelerar. Pause para planejar: construir, recrutar e mudar políticas não têm pressa. No computador, a barra de espaço também pausa."},
	{"title": "Construção e economia", "body": "Toque numa província sua e escolha uma construção. Fazendas, minas e mercados rendem; escolas e universidades aceleram o progresso; [b]depósitos[/b] abastecem exércitos longe da capital."},
	{"title": "Exércitos e guerra", "body": "Recrute regimentos, toque no exército e depois no destino. [b]Exércitos sem suprimentos perdem tropas.[/b] Declare guerra pela Diplomacia, e lembre que aliados e potências vizinhas podem entrar no conflito."},
	{"title": "Boa sorte, governante!", "body": "O jogo salva sozinho todo mês de janeiro, e você também pode salvar pelo menu. Reveja este guia em [b]Configurações › Como jogar[/b]. Bom reinado!"},
]


static func welcomed() -> bool:
	return AppSettings.get_flag(SEC, "welcomed", false)


static func tutorial_done() -> bool:
	return AppSettings.get_flag(SEC, "tutorial_done", false)


## Boas-vindas (primeira vez no menu). `on_start` roda ao tocar em Começar.
static func show_welcome(host: Node, on_start: Callable) -> void:
	var m := ModalCard.new()
	host.add_child(m)
	m.show_text("Bem-vindo ao GeoEmpire 8",
		"Grande estratégia · 1836–2012",
		"Em 1836 o mundo está nas suas mãos. Escolha uma nação — de um império a um pequeno principado — e governe economia, tecnologia, diplomacia e guerra até 2012.\n\nToque em [b]Novo Jogo[/b] para escolher seu país. Um guia rápido aparece na primeira partida.",
		[
			{"text": "Como jogar", "keep": true, "cb": func():
				AppSettings.set_flag(SEC, "welcomed", true)
				m.close()
				show_tutorial(host, false)},
			{"text": "Começar", "primary": true, "cb": func():
				AppSettings.set_flag(SEC, "welcomed", true)
				if on_start.is_valid():
					on_start.call()},
		])


## Tutorial em páginas. `mark_done`: grava o marcador ao terminar (a repetição manual não precisa).
static func show_tutorial(host: Node, mark_done: bool = true) -> void:
	var m := ModalCard.new()
	host.add_child(m)
	m.show_pages(PAGES, func():
		if mark_done:
			AppSettings.set_flag(SEC, "tutorial_done", true)
		m.close())

# GeoEmpire

Grand strategy para celular (Android), inspirado em **Age of History** e **Victoria 3**.
Feito em **Godot 4.3** (GDScript, renderer GL Compatibility), com build por GitHub Actions.
As províncias seguem as **divisões administrativas reais** (estados, regiões, departamentos...) com nome e cidade-sede (★ = capital nacional); divisões minúsculas são fundidas e as gigantes subdivididas.
O mapa é **original**: a Terra em 1836, gerada a partir de dados abertos do Natural Earth (domínio público).

## Como rodar

- Abra a pasta no Godot 4.3+ e rode (`F5`). No PC: arraste com o botão esquerdo, roda do mouse dá zoom.
- No celular: arraste com 1 dedo, pinça com 2, toque curto seleciona a província ou o exército.
- O APK de debug sai do workflow **Build APK (Godot)** (artefato `geoempire-apk`).

## Como jogar (versão base)

- Você começa como o Reino Unido em 1 jan 1836. Toque numa província de outro país e use **Assumir país** para trocar.
- **Economia:** cada província produz conforme população, terreno e recurso. O país cobra impostos (`+`/`-` ajusta a taxa) e paga manutenção de províncias e regimentos. **Oficina** aumenta a produção; **Quartel** aumenta a mão de obra.
- **Exército:** em província sua, **Recrutar** (30 de ouro + 1000 de mão de obra; 30 dias de treino). Toque no marcador do exército para selecioná-lo e depois numa província para marchar. Exércitos parados do mesmo dono se fundem.
- **Mercado mundial:** cada recurso tem preço (% do base) que sobe quando a demanda (proporcional à população) supera a oferta e cai quando sobra; ele multiplica a renda das províncias. Oficinas aumentam a oferta e baixam o preço. Veja o botão **Mercado**.
- **Indústria:** cada província pode ter 1 fábrica (até nível 3): **Tecelagem** (algodão + lã → tecido), **Ferraria** (ferro + madeira → ferramentas), **Marcenaria** (madeira → móveis). Elas compram insumos e vendem produtos a preço de mercado; o lucro mensal entra na receita. Bens processados começam escassos (preço alto), então as primeiras fábricas rendem mais.
- **Comércio global e marinha:** cada país tem mercado e preços próprios (70% a 140% do base). Quem tem déficit de um bem compra de quem tem sobra; vizinhos por terra comerciam livre, e por mar o comércio gasta **capacidade marítima** (40 por porto + 120 por **navio**, 80 de ouro, 40 dias, manutenção 3/mês) dos dois lados. Exportador vende ao preço do comprador e o importador ganha tarifas de 10%. Em guerra, quem tem menos navios que os inimigos fica **bloqueado** (perde a capacidade). **Embargo** (botão na província de outro país) proíbe todo comércio entre os dois e custa 15 de opinião. O botão **Mercado** mostra oferta, demanda, preço, importações e exportações do seu país.
- **Navios no mapa:** em província sua com porto, **Navio** (80 de ouro, 40 dias) cria ou reforça uma frota ancorada no porto. Toque na frota para selecionar, depois no mar ou num porto para navegar (3 células por dia, rota pela água; Suez e Panamá fechados em 1836). Toque na frota de novo para parar. Frotas inimigas na mesma célula lutam; frotas paradas do mesmo dono se fundem. A frota total dá capacidade de comércio e bloqueio.
- **Bandeiras:** cada país tem bandeira (desenhada por código, simplificada) no topo e nos marcadores de exército e frota.
- **Eventos:** surgem todo mês (sorteio determinístico). Escolha uma opção; sem escolha em 30 dias vale a primeira.
- **Guerra:** em província de outro país use **Declarar guerra**. Exércitos inimigos que se encontram lutam todo dia (perde 25% do efetivo inimigo por round; empate decidido por sorteio). Exército parado em província inimiga sem defensores faz **cerco**: em 10 dias ela passa a ser sua. **Propor paz** vale após 30 dias de guerra. **IA simples:** países que não são seus recrutam conforme o tamanho, expulsam invasores, atacam a província inimiga mais próxima e só aceitam paz se não forem mais fortes que você. **Diplomacia:** **Melhorar relações** (50 de ouro, +20 de opinião), **Propor aliança** (a IA aceita com opinião 40 ou mais; o aliado entra na guerra se você for atacado) e trégua de 1 ano após a paz. Depois do primeiro ano a IA pode declarar guerra ao vizinho mais fraco (sem aliança, trégua ou boa opinião).

## Estrutura

```
data/world.json            mundo 1836 (1140 províncias, grade marítima 256x117, 74 países, 3072x1394) - gerado
data/events.json           eventos do jogo (texto, condições e efeitos)
tools/generate_world_1836.py  gera world.json a partir do Natural Earth (ver abaixo)
tools/world1836_data.py    tabela histórica: países, dono de cada região, densidade
scenes/main.tscn           cena mínima; os nós são montados por código em scripts/main.gd
scripts/core/              ENGINE
  events.gd                barramento de sinais (autoload Events)
  game_state.gd            estado, tempo, economia, recrutamento, exércitos, eventos,
                           comandos, hash/snapshot (autoload Game)
  commands.gd              comandos de jogo (Cmd): única forma de alterar o estado
  province.gd country.gd army.gd game_clock.gd province_graph.gd (A* de marcha)
scripts/map/               MAPA
  map_view.gd              malha única das províncias, fronteiras, nomes, 4 modos de mapa
  map_overlay.gd           seleção, marcadores e rota de exércitos (camada dinâmica)
  map_camera.gd            pan/pinça/inércia/zoom, toque curto = tap
scripts/ui/hud.gd          HUD (topo, painel de província, exército, evento, impostos)
scripts/net/p2p_network.gd PRÉ-ESTRUTURA do multiplayer P2P (autoload Net)
```

### Regerar o mapa

```
git clone --depth 1 https://github.com/nvkelso/natural-earth-vector
python3 tools/generate_world_1836.py --ne natural-earth-vector/geojson \
        --width 3072 --density 1.3 --out data/world.json
```

Requer `numpy`, `scipy`, `Pillow` e `scikit-image`. `--density` maior = menos províncias; `--min-frac`/`--max-frac` controlam fusão/divisão de divisões; `--voronoi` volta às células sintéticas.

## Regras para manter o online viável

1. O estado só muda por `Game.apply_command()` / `_simulate_*()`.
2. Sem `randf()`, `Time` ou `OS` na simulação; use `Game.rng` e inteiros (economia em `int`).
3. A UI só chama `Game.submit_command(Cmd.xxx(...))`.
4. Novo comando = constante + factory em `commands.gd` + tratamento (com validação) em `Game.apply_command`.
5. Todo estado novo precisa entrar em `serialize_state`, `load_state` e `state_hash`.

## Roadmap

- [x] **Fase 1 (base jogável)**: engine, mapa 1836, economia, recrutamento, exércitos, eventos
- [x] P2P (pré-estrutura): lockstep com host sequenciador sobre ENet
- [ ] **Fase 2 (polimento)**: melhoria gráfica, menu inicial e escolha de país, salvar/carregar na UI, áudio, tutorial, balanceamento
- [ ] Guerra, combate e conquista; diplomacia; IA dos países; marinha (travessia de oceanos)
- [ ] Tecnologias e mais eventos históricos
- [ ] Multiplayer: lobby, WebRTC com sinalização, reconexão


## Painel de estatísticas e extras
- Barra sob o topo: **população**, **alfabetização** (sobe aos poucos, dá até ~+19% de imposto; eventos podem mudá-la) e **padrão de vida** (produção per capita + alfabetização).
- Atalhos (PC): `Espaço` pausa/continua, `+`/`-` mudam a velocidade.
- Autosave anual em `user://autosave.json` (só no modo offline).
- 16 eventos políticos, incluindo imprensa, escolas, ferrovias, revoltas, greves e abolição.

## Construções (abas na parte de baixo)
- **Governo**: Escola, Universidade (alfabetização e pesquisa, têm manutenção) e Quartel.
- **Recursos**: Mina (carvão/ferro/sal/ouro), Fazenda (produção agrícola), Madeireira (madeira; em florestas gera madeira extra) e Oficina.
- **Indústria**: Tecelagem, Marcenaria, Ferraria (tecnologia 1) e Siderúrgica (tecnologia 3, ferro + carvão -> aço).
- **Tecnologia**: sobe todo mês com a alfabetização, escolas e universidades; libera indústrias mais avançadas.
- Selecione uma província sua, abra a aba e toque em Construir.

## Interface (fase de layout)
- **Escolha de nação** ao iniciar: lista com busca e ordenação, ficha do país (população, capital, tecnologia, exército, tesouro) e botão Jogar. Tocar num país no mapa também o escolhe. "Trocar de país" fica no menu lateral.
- **Barra superior**: bandeira e país, tesouro (+saldo), população, alfabetização, padrão de vida, tecnologia, estabilidade, exército, data e velocidade.
- **Barra lateral**: Política, Leis, Economia, Mercado, modo do mapa e menu (salvar, carregar, trocar de país).
- **Dock inferior**: construções (Governo, Recursos, Indústria).
- **Política interna**: seis classes sociais (camponeses, operários, aristocratas, burguesia, funcionários, soldados) com satisfação e influência, e cinco correntes (conservadorismo, liberalismo, socialismo, nacionalismo, reacionarismo) que nascem da economia. Estabilidade baixa reduz a arrecadação e causa revoltas; novos eventos reagem às correntes.
- Ícones e tema desenhados em código (`scripts/ui/ui_icon.gd`, `scripts/ui/ui_kit.gd`).

## Leis
- 10 grupos de leis (governo, imprensa, serviço militar, política econômica, comercial, tributária, trabalho compulsório, educação, trabalhista, associação), cada um com 3 opções, em `scripts/core/laws.gd`.
- Janela **Leis** na barra lateral, em três colunas: Estrutura de poder / Economia / Direitos e sociedade. Aprovar custa ouro, exige tecnologia e alfabetização, abala a satisfação das classes e bloqueia o grupo por 24 meses.
- Efeitos: arrecadação, comércio, custo do exército, crescimento da alfabetização, tecnologia, estabilidade e satisfação por classe. Comando `enact_law` (online-safe); estado em `Country.laws` / `law_cd`, salvo e no hash.

## Som e música
- Tudo sintetizado em código (`scripts/audio/audio_manager.gd`), sem arquivos de áudio: cliques de botão, moeda, construção, lei, sino, tambor, guerra e eventos.
- Música em Ré menor (pad, baixo, arpejo e melodia) gerada numa thread ao iniciar e tocada em loop. Liga/desliga música e efeitos no Menu.

## Regiões históricas (V0.12)
- `data/regions.json` agrupa as províncias-célula em províncias históricas (Brasil: 16 províncias de 1836, de Grão-Pará a Rio Grande do Sul) e dá nomes de época às células. A ficha da província mostra "Prov. de ...".
- Eventos regenciais do Brasil (Cabanagem, Farroupilha, Sabinada, Balaiada, Maioridade) com efeito regional (`region_pop_pct`).

## Estreitos e rotas (V0.12)
- `data/sea_gates.json`: 5 passagens estratégicas (Estreitos turcos, Øresund, Gibraltar, Cabo da Boa Esperança, Malaca), marcadas no mapa. O controlador é o dono da província-âncora e muda com a conquista.
- `scripts/core/sea_zones.gd`: 6 zonas marítimas (Atlântico, Mediterrâneo, Mar Negro, Báltico, Índico, Pacífico). Uma rota comercial por mar cruza as passagens da zona de um porto à do outro.
- O controlador fecha a passagem a países em guerra ou embargo com ele e cobra pedágio (3% nos Estreitos e no Øresund, 1% no Cabo e em Malaca). A janela de Economia lista controlador, pedágio e fluxo.

## Guerra (V0.12)
- **Frente automática** (botão no painel de guerras, ligada por padrão): os exércitos parados do jogador marcham sozinhos ao inimigo, inclusive no instante em que a guerra é declarada.
- Território conquistado fica com o tom do dono original e contorno na cor de quem o tomou; fronteiras entre países em guerra ficam vermelhas; cercos mostram arco de progresso. `core_owner` entra no save.
- **Marinha:** frotas ociosas em guerra (da IA e do jogador com a frente automática) caçam a frota inimiga mais próxima se não estiverem em desvantagem, bloqueiam o porto inimigo mais próximo ou voltam ao porto. O combate ocorre também entre células vizinhas, e a força de cada navio cresce com a tecnologia (fragata, navio de linha, vapor de guerra).
- **Molde 3D do exército** (`scripts/ui/army_model.gd`): ao selecionar um exército, o painel mostra soldados 3D em formação (até 24, conforme os regimentos), que marcham em movimento e balançam parados, com o estandarte do país ondulando por shader. É um protótipo de formas simples, a ser trocado por modelos melhores.

## Camada econômica analítica (V0.12)
- `EconomyManager` (autoload): PIB por **valor agregado** (produção primária + indústria − insumos), PIB real (deflacionado por índice de preços ponderado), inflação, crescimento, balança comercial, fluxo de investimento privado, rankings mundiais e gargalos/excedentes. Histórico de até 120 meses (não vai para o save nem para o hash P2P).
- Janela **Economia**: indicadores, gráficos de PIB real e saldo fiscal (`GDPChartPanel`), maiores economias e alertas de mercado. Detalhes em `docs/INTEGRACAO_ECONOMIA.md`.
- **Desemprego** (`Game.unemployment_pct`): 20% da força de trabalho busca emprego formal; vagas vêm de `Province.JOBS_PER_LEVEL`. Desemprego acima de 14% reduz a satisfação de trabalhadores (÷2) e camponeses (÷4); abaixo disso dá bônus.

## Construções e menus (V0.12)
- Painel de construção redesenhado: cartões com ícone vetorial por construção, nível em 3 marcadores, efeito, empregos e líquido mensal em uma linha, rolagem vertical e "Ver detalhes" para a conta completa. O dock agora tem 4 abas (Governo, Recursos, Indústria, Infra) sem texto cortado.
- 4 construções novas: **Hospital** (Governo: +0,03%/mês de crescimento por nível), **Mercado** (Infra: +8% de imposto da província por nível), **Ferrovia** (Infra, tec. 2: +12% de produção por nível) e **Cais comercial** (Infra, só litoral: +60 de comércio marítimo por nível). Manutenção de hospital/mercado/cais aparece no Orçamento.

## Layout e mapa (V0.12)
- Interface mais suave e centrada: cantos arredondados, bordas discretas, janelas centrais que se ajustam à tela (até 92% x 94%), dock inferior adaptável, painel de província mais estreito, painel de exército com largura própria e aviso (toast) proporcional. Baseado em `geoempire8_layout_rework_v1`, adaptado ao `hud.gd` desta branch.
- Mapa remodelado (estilo Age of History 3 / Victoria): oceano com vinheta radial, faixa de águas rasas na costa (`CoastHalo`), divisões de província claras e translúcidas, fronteiras de país escuras com sombra suave, leve mistura da cor do país com o terreno e nomes em serifa para oceanos.

## IA estratégica (V0.15, fase 1)
`AiBrain` substitui a antiga regra "ataca o vizinho mais fraco". Ciclo mensal: **avaliação nacional** (força própria, reservas de 6 meses de despesa, estabilidade ≥ 35), **interesses** (reivindicações = províncias núcleo em mãos do rival, hostilidade, oportunismo), **preparação** (recruta até +2/+4 regimentos), **pressão diplomática** (relação com o alvo cai 3/mês, aviso ao jogador, cortejo e alianças com quem também odeia o alvo).
- Razão de forças exigida (própria / estimada do rival): 75% com 2+ reivindicações, 90% com 1, 130% com hostilidade forte, 180% com hostilidade, 250% por oportunismo. Sem razão excepcional, nada de atacar uma potência mais forte.
- **Informação limitada:** a IA vê só regimentos e navios do rival (não tecnologia nem tesouro), com ruído determinístico de ±15% a ±45% (menor com tecnologia e alfabetização, muda a cada semestre) e aliados do rival entram com peso menor e mais incerteza. Não usa `rng` no plano: segue determinístico no multiplayer.

### IA estratégica v2: objetivos de guerra ramificados
- Estudo de referência: Victoria 3 (estratégias e "desejos" por país, objetivos pontuados, neutralidade/confiança/ousadia, pesos com aleatoriedade), HoI4 (estratégias por país, justificativa antes da guerra, planos de frente) e Age of History (IA agressiva guiada por relações e vizinhança).
- `data/ai_profiles.json`: personalidade por país (ambição, ousadia, rivais, reivindicações, protegidos, "balance", pesos por objetivo). Países sem perfil recebem uma personalidade derivada do id e do tamanho.
- 10 objetivos de guerra, cada um com razão de forças exigida e **tensão** mínima: reconquista, unificação, intervenção em defesa de protegido, reivindicação histórica, rivalidade, estreitos, contenção do hegemon, oportunismo (alvo instável ou em guerra), recursos raros e expansão. Objetivos "frios" passam antes pela fase de pressão (relação cai 3/mês), o que dá ao jogador meses de aviso com o motivo.
- Equilíbrio de poder: uma potência dominante (≥160% da segunda e ≥250% da mediana) passa a ser vista com desconfiança pelos países "balance" (relação −1/mês) e vira alvo de contenção.
- Defesa: vizinho hostil bem mais forte faz a IA recrutar mais e procurar aliados.
- Campanha: exércitos priorizam núcleos próprios, capitais, portos e recursos raros do inimigo.

## Diplomacia 2.0, vassalos e anexação (V0.12)
- **Pontuação de guerra** (0-100) por par em guerra: % das províncias do inimigo tomadas desde o início + 30 pela capital. Guardada em `wars` (salva e restaurada).
- **Termos de paz** (`Cmd.make_peace(alvo, termo)`): paz branca, indenização (≥15 pts), vassalizar (≥45) e anexar o país (≥75). IAs vencedoras ditam os termos nas guerras entre IAs (após 120 dias; empate longo vira paz branca).
- **Vassalos:** pagam 25% da renda como tributo, seguem o suserano nas guerras, não declaram guerra nem fazem alianças e não podem ser atacados pelo suserano. O suserano pode **anexar** (após 360 dias, custo 60 por província) ou **libertar**. O vassalo se rebela se o suserano some ou cai abaixo de 15% de estabilidade. IAs anexam vassalos quando têm ouro.
- **Janela Diplomacia** (ícone de bandeira na lateral ou botão "Diplomacia" no cartão da província): lista de países com situação e opinião, detalhes do país escolhido e ações (melhorar relações, aliança, embargo, guerra, termos de paz, anexar/libertar vassalo).

## Negociação de paz com a IA (partes A+B)

- `scripts/core/ai_diplomacy.gd`: calcula o **cansaço de guerra** da IA (placar, capital perdida, exércitos, tesouro/déficit, estabilidade, duração, núcleos ocupados).
- Mensalmente a IA em guerra com um jogador pode **propor paz**: branca, indenização, vassalagem (ou ela mesma cobrando, se dominante). A proposta expira em 60 dias; recusar gera 90 dias de carência.
- O jogador responde pelo painel no topo (Aceitar/Recusar) → comandos `accept_peace` / `reject_peace`. Ofertas e carências entram em salvar/carregar e no hash.
- Propostas do jogador à IA são aceitas conforme o cansaço (branca 15, indenização 30, vassalo 55, anexação 70); a janela de Diplomacia mostra a "Disposição a negociar".
- Parte C (personalidades diplomáticas) e contrapropostas: próximas etapas.


## Auditoria técnica (etapas 1 e 3)

- `tools/acceptance_test.gd`: teste de aceitação headless (mundo, determinismo, salvar/carregar, guerra/paz/vassalagem). Roda no CI e falha o build.
- `tools/economy_audit.gd`: simula 10 anos sem jogador e imprime estatísticas anuais (tesouro, saldo, preços, desemprego, PIB, população) e alertas. Informativo no CI.
- Corrigidos: bônus de capital nunca aplicado, conquista contada em dobro, placar fora do hash, renda/despesa fora do save, erro de script ao fundir exércitos, IA que nunca investia.

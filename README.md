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

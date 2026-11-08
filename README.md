# GeoEmpire

Grand strategy para celular (Android), inspirado em **Age of History** e **Victoria 3**.
Feito em **Godot 4.3** (GDScript, renderer GL Compatibility), com build por GitHub Actions.
O mapa é **original**: a Terra em 1836, gerada a partir de dados abertos do Natural Earth (domínio público).

## Como rodar

- Abra a pasta no Godot 4.3+ e rode (`F5`). No PC: arraste com o botão esquerdo, roda do mouse dá zoom.
- No celular: arraste com 1 dedo, pinça com 2, toque curto seleciona a província ou o exército.
- O APK de debug sai do workflow **Build APK (Godot)** (artefato `geoempire-apk`).

## Como jogar (versão base)

- Você começa como o Reino Unido em 1 jan 1836. Toque numa província de outro país e use **Assumir país** para trocar.
- **Economia:** cada província produz conforme população, terreno e recurso. O país cobra impostos (`+`/`-` ajusta a taxa) e paga manutenção de províncias e regimentos. **Oficina** aumenta a produção; **Quartel** aumenta a mão de obra.
- **Exército:** em província sua, **Recrutar** (30 de ouro + 1000 de mão de obra; 30 dias de treino). Toque no marcador do exército para selecioná-lo e depois numa província para marchar. Exércitos parados do mesmo dono se fundem.
- **Eventos:** surgem todo mês (sorteio determinístico). Escolha uma opção; sem escolha em 30 dias vale a primeira.
- Ainda **não há guerra, diplomacia nem IA**; exércitos de países diferentes apenas coexistem.

## Estrutura

```
data/world.json            mundo 1836 (1114 províncias, 74 países, 3072x1394) - gerado
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

Requer `numpy` e `scipy`. `--density` maior = menos províncias (mapa mais leve).

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

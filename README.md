# GeoEmpire

Grand strategy para celular (Android), inspirado em **Age of History 3** e **Victoria 3**.
Feito em **Godot 4.3** (GDScript, renderer GL Compatibility), com build por GitHub Actions.

## Como rodar

- Abra a pasta no Godot 4.3+ e rode (`F5`). No PC: arraste com o botão esquerdo, roda do mouse dá zoom.
- No celular: arraste com 1 dedo, pinça com 2, toque curto seleciona a província.
- O APK de debug sai do workflow **Build APK (Godot)** (artefato `geoempire-apk`).

## Estrutura

```
data/world.json            mundo gerado (14 países, 247 províncias)
tools/generate_world.py    gera data/world.json (python3 tools/generate_world.py [seed])
scenes/main.tscn           cena mínima; os nós são montados por código em scripts/main.gd
scripts/core/              ENGINE
  events.gd                barramento de sinais (autoload Events)
  game_state.gd            estado + tempo + simulação + comandos + hash/snapshot (autoload Game)
  commands.gd              comandos de jogo (Cmd): única forma de alterar o estado
  province.gd country.gd game_clock.gd
scripts/map/               MAPA
  map_view.gd              desenho por províncias, 4 modos de mapa, seleção
  map_camera.gd            pan/pinça/inércia/zoom, toque curto = tap
scripts/ui/hud.gd          HUD (barra superior, painel de província, impostos)
scripts/net/p2p_network.gd PRÉ-ESTRUTURA do multiplayer P2P (autoload Net)
```

## Regras para manter o online viável

1. O estado só muda por `Game.apply_command()` / `_simulate_*()`.
2. Sem `randf()`, `Time` ou `OS` na simulação; use `Game.rng` e inteiros (economia em `int`).
3. A UI só chama `Game.submit_command(Cmd.xxx(...))`.
4. Novo comando = constante + factory em `commands.gd` + tratamento em `Game.apply_command`.

## Roadmap (por partes)

- [x] **1. Engine**: tempo, comandos, economia básica, snapshot/hash, save/load
- [x] **2. Mapa**: províncias, modos de mapa, zoom/pan/pinça, seleção, HUD
- [x] **P2P (pré-estrutura)**: lockstep com host sequenciador sobre ENet
- [ ] 3. Menu inicial e escolha de país, salvar/carregar na UI
- [ ] 4. Economia e populações (produção, comércio, pops, indústria)
- [ ] 5. Exércitos, movimento entre províncias, guerra e conquista
- [ ] 6. Diplomacia (relações, alianças, tratados de paz)
- [ ] 7. IA dos países
- [ ] 8. Eventos e tecnologias
- [ ] 9. Multiplayer: lobby, WebRTC com sinalização, reconexão
- [ ] 10. Polimento: áudio, tutorial, balanceamento, performance

# GeoEmpire 8 — Roadmap e guia do projeto

Branch de trabalho: `v0.12-base-historica` (não fazer merge na `main` antes da aceitação).
Motor: Godot 4.3, GDScript, GL Compatibility. Alvo: Android.

## As 12 fases

| # | Fase | Estado |
|---|------|--------|
| 1 | Desempenho (mês fatiado, cache, throttle de UI) | feita (v0.13.x) |
| 2 | Mundo e IA (pressão, finanças e espionagem da IA, infâmia, vitória/derrota) | feita (v0.14.0) |
| 3 | Economia de mercado (métodos de produção das fábricas) | feita no código (v0.15.0), falta validar no aparelho |
| 4 | Política interna (6 classes, 5 correntes ligadas às leis) | feita no código (v0.16.0), falta validar no aparelho |
| 5 | Governo (orçamento por ministérios, decretos) | feita no código (v0.17.0), falta validar no aparelho |
| 6 | Diplomacia (jogadas, casus belli, coalizões, tratados) | pendente |
| 7 | Guerra (frentes, logística, comandantes, naval) | pendente |
| 8 | Tecnologia e cultura (eras, ideologias, prestígio) | pendente |
| 9 | Eventos e história (1836–2012, tela de fim de jogo) | pendente |
| 10 | Interface (tutorial, tela de país, mapa por modos) | pendente |
| 11 | Online (P2P/lockstep, sync de saves) | pendente |
| 12 | Polimento (áudio, balanceamento, segurança, lançamento) | pendente |

## Regras de arquitetura (não quebrar)

1. **Determinismo.** Todo estado muda só por `Game.apply_command` ou `_simulate_*`. Só inteiros.
2. **Estado novo = salvar + hash.** Qualquer variável de simulação entra em `serialize_state`, `load_state` e `state_hash`. Dados só de apresentação (logs, histórico de gráficos, caches de UI) não entram.
3. **Mês fatiado.** `_simulate_month` e a versão fatiada rodam os mesmos estágios (`STAGE_NAMES`). Um estágio novo precisa dar o mesmo hash nas duas versões (há teste com `month_budget_us=1`).
4. **Comandos** ficam em `scripts/core/commands.gd`, com validação `can_*` em `game_state.gd` (a UI usa o mesmo `can_*`).
5. **Godot headless.** Testes `--script` não compilam scripts que citam autoloads (`Events` etc.); exponha o resultado por retorno em `Game`.
6. Não inferir tipo com `:=` a partir de `Variant`.

## Mapa do código

- `scripts/core/` — simulação (`game_state.gd`, `province.gd`, `country.gd`, `economy_manager.gd`, `ai_*.gd`, `commands.gd`).
- `scripts/ui/` — interface (`hud.gd`, `ui_kit.gd`).
- `scripts/system/` — log, breadcrumb e diagnóstico de queda.
- `data/` — conteúdo em JSON (changelog, eventos).
- `tools/` — `acceptance_test.gd` (regras), `economy_audit.gd` (economia).

## Como testar e lançar

1. `git push` na branch; o GitHub Actions roda smoke, `acceptance_test.gd` e `economy_audit.gd`.
2. `gh workflow run "Build APK (Godot)" --ref v0.12-base-historica` gera o APK em `latest-apk`.
3. O CI não valida o aparelho. A validação real é o log exportado (`GeoEmpire_log_*.txt`).
4. Cada fase: atualizar `data/changelog_fallback.json`, `config/version` em `project.godot` e esta tabela.

## Referências estudadas (só documentação pública)

Victoria 3 (métodos de produção, infâmia), Age of History 3, Geopolitical Simulator. Código proprietário desses jogos não é usado.

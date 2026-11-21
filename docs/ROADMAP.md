# GeoEmpire 8 — Roadmap e guia do projeto

Branch de trabalho: `v0.12-base-historica` (não fazer merge na `main` antes da aceitação).
Motor: Godot 4.3, GDScript, GL Compatibility. Alvo: Android.

## Trilha A — Base (fases 1 a 6, concluídas)

| # | Fase | Estado |
|---|------|--------|
| 1 | Desempenho (mês fatiado, cache, throttle de UI) | feita (v0.13.x) |
| 2 | Mundo e IA (pressão, finanças e espionagem da IA, infâmia, vitória/derrota) | feita (v0.14.0) |
| 3 | Economia de mercado (métodos de produção das fábricas) | feita (v0.15.0) |
| 4 | Política interna (correntes ligadas às leis) | feita (v0.16.0) |
| 5 | Governo (orçamento por ministérios, decretos) | feita (v0.17.0) |
| 6 | Diplomacia (casus belli, tratados) | feita (v0.18.0), falta validar no aparelho |

Fases antigas 7 a 12 (guerra, tecnologia e cultura, eventos e história, interface, online, polimento) ficam em pausa até a Trilha B terminar.

## Trilha B — Economia e política (25 etapas, foco atual)

Economia
| # | Etapa | Estado |
|---|-------|--------|
| B1 | Pops reais: população por profissão em cada província | feita no código (v0.19.0) |
| B2 | Salários e padrão de vida por pop | feita no código (v0.20.0), só leitura |
| B3 | Necessidades e consumo: cestas de bens por classe | feita no código (v0.21.0) |
| B4 | Mercados: oferta, demanda e preço por mercado regional | feita no código (v0.22.0): alimento regional e fome; preço regional fica para B11 |
| B5 | Cadeias produtivas ampliadas: novos bens e edifícios | feita no código (v0.23.0): papel e máquinas |
| B6 | Métodos de produção para fazendas, minas e fábricas, por tecnologia | feita no código (v0.24.0) |
| B7 | Propriedade: capitalistas privados x Estado, dividendos, investimento privado | feita no código (v0.25.0); nacionalização fica para B23 |
| B8 | Comércio exterior: rotas, tarifas, balança comercial | feita no código (v0.26.0) |
| B9 | Moeda, inflação, juros e dívida pública | feita no código (v0.27.0) |
| B10 | Impostos detalhados por classe, consumo e tarifa; evasão | feita no código (v0.31.0) |
| B11 | Infraestrutura e transporte entre mercados; comboios marítimos | feita no código (v0.32.0) |
| B12 | Ciclos econômicos: expansão, recessão, crises | feita no código (v0.33.0): risco, pânico; ranking e gráficos |
| B13 | Desigualdade e bem-estar: pobreza, natalidade e mortalidade | pendente |

Política
| # | Etapa | Estado |
|---|-------|--------|
| B14 | Partidos por corrente, programas e filiação por classe | pendente |
| B15 | Eleições e parlamento: cadeiras, coalizão, aprovação | pendente |
| B16 | Grupos de interesse: industriais, latifundiários, sindicatos, militares, Igreja | pendente |
| B17 | Leis ampliadas e votação das leis no parlamento | pendente |
| B18 | Movimentos: sindicatos, greves, protestos | pendente |
| B19 | Golpes, revoluções e guerras civis; mudança de regime | pendente |
| B20 | Reformas, concessões e repressão: crise de legitimidade | pendente |
| B21 | Burocracia: capacidade do Estado e corrupção | pendente |
| B22 | Cultura, religião e minorias; propaganda | pendente |
| B23 | Política econômica avançada: planejamento, subsídios, monopólios, nacionalização | pendente |
| B24 | IA econômica e política reagindo a crises | pendente |

Fechamento
| # | Etapa | Estado |
|---|-------|--------|
| B25 | Balanceamento, painéis finais de economia e política, auditorias | pendente |

## Trilha C — Nova HUD (referência visual enviada em 20/11/2026)

Identidade: interface estratégica premium, painéis modulares, cores vivas, leve para celular (sem transparência pesada nem animação constante). Mantém todos os sistemas existentes.
Layout de referência: topo com indicadores nacionais e velocidade; esquerda com ficha do país; centro com o mapa; direita com eventos e província selecionada; parte inferior com Governo, Economia, Sociedade, Diplomacia, Militar, Pesquisa, Leis e Estatísticas.
Não serão usados retratos, bandeiras reais nem imagens do mockup; todo o visual será desenhado no próprio jogo.

| # | Etapa | Estado |
|---|-------|--------|
| C1 | Tema visual: paleta, molduras e bandeira ondulando | feita no código (v0.28.0), falta ver no aparelho |
| C1b | Gráfico do mapa-múndi: oceano, costas, fronteiras, cores | feita no código (v0.29.0), falta ver no aparelho |
| C8a | Desempenho: resolução 720p, IA diária, suprimentos | feita no código (v0.30.0), falta medir no aparelho |
| C2 | Barra superior com indicadores e controle de velocidade | pendente |
| C3 | Ficha do país à esquerda, recolhível | pendente |
| C4 | Eventos e província selecionada à direita | pendente |
| C5 | Barra inferior de 8 categorias, cada uma abrindo seu painel | pendente |
| C6 | Painéis Governo, Sociedade e Estatísticas reorganizados | pendente |
| C7 | Adaptação a telas pequenas e modo paisagem | pendente |
| C8 | Passada de desempenho e teste no aparelho | pendente |

Regra de ritmo: uma etapa por vez, com CI verde, changelog e versão; entre etapas o log do aparelho é conferido.

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


Pesquisa de referência (Victoria 3 e história econômica): `docs/ECONOMIA_PESQUISA.md`.

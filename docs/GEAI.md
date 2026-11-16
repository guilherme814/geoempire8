# GEAI — GeoEmpire Advanced Intelligence

## 1. Auditoria do sistema existente (v0.12-base-historica)

| Sistema | Arquivo | Situação | Lacuna para o GEAI |
|---|---|---|---|
| Estratégia (quem atacar e por quê) | `ai_brain.gd` | Bom: 10 objetivos, personalidade (ambição, ousadia, pesos), percepção incerta da força rival, preparação/pressão/guerra | Não enxerga economia de guerra nem memória; personalidade militar inexistente |
| Operação militar | `ai_war.gd` | Camada utility por exército: recuo, concentração, defesa, ofensiva, 1 objetivo por país | Não separa frentes (multi-inimigo), sem prioridade entre regiões, sem plano ofensivo/defensivo explícito |
| Batalha | `game_state._advance_war` | Round diário, tecnologia e suprimento afetam perdas | Sem mudanças necessárias |
| Movimentação | `_order_move`, `find_path`, `_merge_stationary` | Marcha por caminho, exércitos parados se fundem | Sem mudanças necessárias |
| Logística | `_update_supply` | Capital/depósitos, ratio, desgaste | IA ainda não constrói depósito conforme campanha |
| Economia de guerra | `_ai_recruit`, `_ai_invest`, `estimate_monthly` (upkeep_army) | Recruta por tamanho/estágio do plano | Não limita guerra pela capacidade de sustento |
| Diplomacia/alianças | `AiBrain.court_allies`, `_start_war` (aliados entram) | Aliança por afinidade; chamada automática | Sem coordenação de operações conjuntas |
| Paz | `ai_diplomacy.gd` (cansaço de guerra) | Funciona (jogador x IA e IA x IA) | Peace C pendente (contrapropostas) |
| Personalidades | `data/ai_profiles.json` (29 países) | Ambição, ousadia, rivais, pesos | Só estratégicas; falta doutrina militar |

Princípio: não recriar nada disso; o GEAI entra como camadas novas sobre as mesmas APIs.

## 2. Arquitetura

```
Estratégica  AiBrain      quem / por quê / quando            (existe)
Teatros      AiTheater    região, objetivo, prioridade, ameaça, tropas necessárias,
                          logística, plano (ofensivo / defensivo / manter) + condições
Operacional  AiWar        ordens por exército segundo teatro + doutrina do comandante
Doutrina     AiWar.PERSONALITIES  agressivo, cauteloso, defensivo, oportunista, estratégico, imprevisível
Memória      (etapa 5)    registro limitado de eventos que ajusta prioridades
Economia     (etapa 4)    sustentabilidade de guerra, recrutamento e depósitos por teatro
```
Todas as camadas são funções do estado do jogo (sem rng, ids em ordem): determinísticas no P2P. O que for memória será serializado e entrar no hash.

## 3. Plano incremental
1. **Teatros de guerra** (feito): um teatro por inimigo, prioridade por ameaça/risco/capital, necessidades de tropa, atribuição de exércitos, plano e condições de mudança.
2. **Doutrinas de comandante** (feito): seis personalidades que alteram limiares, pesos de alvo e plano.
3. Planejamento ramificado (alternativas A–E avaliadas por custo/risco/oportunidade).
4. Economia e logística de guerra (sustento, recrutamento por teatro, depósitos).
5. Memória estratégica limitada (ring buffer serializado e hasheado).
6. Coordenação com aliados e coalizões; operações conjuntas.
7. Paz inteligente (parte C) e painel de intenções.
8. Bateria de cenários de longo prazo com métricas.

## 4. Limitações conhecidas (honestidade)
- Os testes validam regras e cenários montados; **não provam** que a IA seja estrategicamente inteligente. Isso só se vê em partidas longas e na comparação de métricas.
- Limiares de doutrina são estimativas, ainda sem calibração.
- Sem estado persistente nos teatros, o plano é reavaliado a cada 5 dias, sem histerese.

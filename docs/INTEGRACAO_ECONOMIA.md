# Integração — Nova camada econômica GeoEmpire 8

Compatibilidade-alvo: Godot 4.3+, projeto atual do GeoEmpire 8.

## O que está incluído

- `scripts/core/economy_manager.gd`: camada analítica que lê o estado econômico atual do autoload `Game`, registra séries mensais, calcula PIB nominal/real, PIB per capita, inflação estimada, crescimento, balança comercial, valor agregado industrial, fluxo de investimento privado, capacidade estimada de emprego, rankings, mercado e gargalos.
- `scripts/ui/gdp_chart_panel.gd`: controle gráfico reutilizável para curvas mensais. Aceita tanto arrays numéricos quanto snapshots produzidos pelo EconomyManager.
- O painel não substitui `Game.estimate_monthly()`, `Game.market_tables()` ou as fórmulas existentes em `Province`.

## 1. Copiar os arquivos

Copie as pastas `scripts/` deste pacote para a raiz do projeto, mantendo os caminhos.

## 2. Registrar o autoload

Em `project.godot`, na seção `[autoload]`, acrescente:

```ini
EconomyManager="*res://scripts/core/economy_manager.gd"
```

Mantenha os autoloads existentes (`Events`, `Game`, `Net`) sem removê-los.

## 3. Registrar os snapshots mensais

Em `scripts/core/game_state.gd`, dentro de `_simulate_month()`, localize:

```gdscript
_roll_events()
Events.month_changed.emit(clock.to_dict())
```

Insira a chamada abaixo imediatamente antes de `Events.month_changed.emit(...)`:

```gdscript
EconomyManager.record_month(self)
```

O trecho ficará:

```gdscript
_roll_events()
EconomyManager.record_month(self)
Events.month_changed.emit(clock.to_dict())
```

A função é chamada depois do cálculo de receitas, despesas, comércio e tesouro. Assim, o registro representa o mês recém-concluído.

## 4. Mostrar a curva no painel Economia

Em `scripts/ui/hud.gd`, dentro de `_refresh_economy()`, depois de criar o bloco `top` e antes de criar `cols`, adicione:

```gdscript
var gdp_chart := GDPChartPanel.new()
gdp_chart.custom_minimum_size = Vector2(0, 190)
gdp_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
gdp_chart.set_metric("gdp_real", "PIB REAL — EVOLUÇÃO MENSAL")
gdp_chart.update_chart(EconomyManager.get_history(c.id))
body.add_child(gdp_chart)
```

Para mostrar saldo fiscal em outro gráfico, use:

```gdscript
var balance_chart := GDPChartPanel.new()
balance_chart.custom_minimum_size = Vector2(0, 170)
balance_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
balance_chart.set_metric("monthly_balance", "SALDO FISCAL MENSAL")
balance_chart.update_chart(EconomyManager.get_history(c.id))
body.add_child(balance_chart)
```

## 5. Atualizar a curva quando o mês virar

No método `_on_month_changed()` existente em `hud.gd`, depois da atualização dos indicadores, atualize a janela econômica se estiver aberta:

```gdscript
if _windows.has("eco") and _windows["eco"].visible:
    _refresh_economy()
```

Confirme o nome e a estrutura de `_windows` no arquivo atual antes de inserir. Se a janela não usar `visible`, atualize o painel pelo mecanismo de refresh já existente.

## 6. API disponível

```gdscript
# Relatório econômico detalhado de um país.
var report: Dictionary = EconomyManager.country_report(Game, country_id)

# Histórico mensal (últimos 120 registros).
var history: Array = EconomyManager.get_history(country_id)

# Ranking mundial por PIB nominal.
var ranking: Array = EconomyManager.global_rankings(Game)

# Oferta, demanda, preço, importações e exportações.
var market: Array = EconomyManager.market_report(Game, country_id)

# Gargalos e excedentes de mercado.
var alerts: Array = EconomyManager.bottlenecks(Game, country_id)
```

Campos principais de `country_report`:
- `gdp_nominal`, `gdp_real`, `gdp_per_capita_x100`
- `gdp_growth_pct`, `nominal_growth_pct`, `inflation_pct` (no snapshot histórico)
- `price_index`
- `production_primary`, `production_industry_gross`, `industry_value_added`
- `monthly_income`, `monthly_expense`, `monthly_balance`, `treasury`
- `trade_balance`, `imports_value`, `exports_value`
- `investment_flow`
- `estimated_jobs`, `labor_force_estimate`, `employment_capacity_pct`, `unemployment_proxy_pct`
- `standard_of_living_x10`, `literacy_x10`, `stability`
- `top_provinces`, `goods_output`

## Limites e decisões deliberadas

1. O histórico é mantido em memória e ainda não é incluído no savegame. Para persistência entre sessões, será necessário versionar o formato de save e salvar/restaurar a série por país.
2. O emprego é uma estimativa de capacidade com base em `Province.JOBS_PER_LEVEL`. O próprio projeto declara esses empregos como informativos; ainda não existe contratação individual nem desemprego simulado.
3. `unemployment_proxy_pct` é um indicador aproximado, não uma taxa real de desemprego. Quando ainda não há capacidade de empregos registrada, retorna `-1` (indisponível), em vez de afirmar desemprego de 100%.
4. `investment_flow` estima 15% do lucro líquido positivo das fábricas privadas no mês (e fica zerado quando as fábricas são estatais). Não é um fundo acumulado e não pode financiar construções até ser integrado ao sistema de comandos, validação e sincronização.
5. Dívida pública, juros, moeda, reservas, estoques físicos, consumo por classe e serviços ainda não existem como sistemas completos no motor atual. Não são inventados neste pacote.
6. PIB real usa o índice de preços nacional ponderado por oferta/demanda disponível. É uma aproximação de deflação, não uma série histórica oficial de preços.
7. Os dados analíticos não alteram o estado simulado e não entram no hash P2P. Todos os peers calculam os mesmos snapshots a partir do mesmo estado, desde que usem a mesma versão do código.
8. A economia existente trabalha em unidades inteiras de ouro e usa atualização mensal. Não adicionar relógio de sistema, aleatoriedade não determinística ou cálculos locais que modifiquem o estado.

## Testes recomendados antes de integrar à branch principal

- Abrir o projeto no Godot 4.3+ e verificar erros de parser.
- Iniciar uma campanha de 1836 e avançar dois meses.
- Confirmar que cada país vivo recebe exatamente um snapshot por mês.
- Verificar que o PIB real varia quando os preços mudam, mas não se confunde com o PIB nominal.
- Conferir países sem províncias, população zero e mercados sem oferta.
- Comparar os totais com `Game.estimate_monthly()` e `Game.market_tables()`.
- Em multiplayer, iniciar dois peers, avançar meses e comparar `Game.state_hash()` antes e depois da inclusão do módulo.
- Não considerar o APK validado apenas porque a exportação terminou: instalar e abrir em Android real.

## Próxima fase econômica

A próxima expansão deve introduzir, em mudanças separadas e testáveis:
- grupos populacionais com renda e cesta de consumo;
- contratação e desemprego reais;
- estoques físicos e logística;
- investimento privado acumulado com comandos P2P;
- dívida pública, juros e serviço da dívida;
- setores de serviços e infraestrutura;
- orçamento detalhado por ministério e políticas de subsídio.

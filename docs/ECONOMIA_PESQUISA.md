# Pesquisa de economia — referência para as etapas B12–B25

Fontes lidas nesta rodada (o wiki do Victoria 3 e o diário de desenvolvimento #10 não puderam ser
acessados: bloqueio de robôs / validação de navegador; o fórum só deu títulos):
- Paradox, Dev Diary #38 (rotas comerciais e tarifas) e #39 (rotas marítimas e comboios).
- Wikipédia: Panic of 1837, Zollverein, Corn Laws, Industrial Revolution.

## Victoria 3 — o que copiar (comércio)
- Comércio entre mercados sem fronteira terrestre exige **rota marítima**; o custo em **comboios**
  cresce com o nº de nós de mar e a quantidade de bens. Comboios vêm de **portos**.
  → B11: custo por estreito atravessado, capacidade = portos + cais + navios, bloqueio zera.
- Falta de comboios pune todas as rotas; frotas inimigas "raideiam" e reduzem a efetividade.
  → Próximo passo possível: raid graduado (hoje o bloqueio é tudo-ou-nada).
- **Centros comerciais** surgem em capitais de mercado e portos; rendem dos dois lados da rota.
  → B11: +4%/nível de cais (máx. 30%).
- **Tarifas** valem para importação e exportação; mais tarifa reduz eficiência do comércio e o lucro.
  **Embargos** reduzem o fluxo sem zerar. **Portos de tratado** e **uniões aduaneiras** dão acesso a
  mercados bloqueados; na união aduaneira o país perde o controle da tarifa mas recebe parte da receita.

## História 1830–1850 — o que modelar
- **Ferrovias:** primeira linha interurbana em 1830 (Liverpool–Manchester); canais superados a partir de
  1840; telégrafo nos anos 1840; correio de tarifa única em 1840. → Ferrovia/telégrafo como infraestrutura.
- **Têxteis e ferro:** algodão chegou a 22% do valor agregado britânico em 1831; alto-forno de ar
  quente (1828) cortou o carvão por tonelada de ferro. Vapor: 10 mil hp (1800) → 210 mil (1815).
- **Urbanização e salários:** população inglesa 8,3 mi (1801) → 17 mi (1850); salários reais cresceram
  pouco (~15% entre 1780 e 1850, estimativa contestada). → Desigualdade e pobreza (B13).
- **Pânico de 1837:** Banco da Inglaterra subiu juros de 3% para 5%; algodão caiu ~25%; especulação de
  terras e drenagem de moeda; corrida aos bancos (10/5/1837, NY suspende conversão); >40% dos bancos
  quebraram; deflação 1837–1844; recuperação parcial em 1838–39, fim só nos anos 1840; febre do ouro
  (1848) expandiu a moeda. → B12: ciclos de crédito, corrida bancária, deflação, gatilho por juros altos
  + queda de preço de commodity + dívida privada.
- **Zollverein (1834):** fim das tarifas internas entre estados alemães, tarifa comum externa, divisão de
  receita (censo de 1834 para a partilha); antes, uma carga Königsberg–Colônia era taxada ~80 vezes.
  Efeito sobre a indústria é debatido pelos historiadores. → Uniões aduaneiras na diplomacia.
- **Leis dos Cereais (Reino Unido):** tarifa **móvel** (1828: ~34s 8d com trigo ≤52s; 1s a 73s); protege
  proprietários, encarece comida e custo industrial; revogação em 1846 (fome na Irlanda, Peel,
  Anti-Corn Law League); beneficiou os 90% mais pobres e custou aos 10% mais ricos.
  → Tarifa de alimento com escala móvel e conflito proprietários × industriais (grupos de interesse).

## Mapa de ideias para as próximas etapas
- **B12 Ciclos:** fase (expansão/pico/recessão/depressão) derivada de juros, preço de commodity e
  crédito privado; corrida bancária com perda de capital privado; deflação prolongada.
- **B13 Bem-estar:** pobreza/natalidade/mortalidade ligadas a preço de alimento e saneamento.
- **B14–B24 Política:** proprietários × industriais × operários como grupos de interesse (tarifa de
  cereais, imposto, voto de leis); união aduaneira como tratado; partilha de receita.
- **Tarifas:** tarifa de exportação e tarifa móvel de alimentos; embargo parcial por bem.
- **Marítimo:** raid graduado de comboios; portos de tratado; rotas com nome (Atlântico, Suez/Canal,
  Pacífico) nas passagens que já existem em `data/sea_gates.json`.

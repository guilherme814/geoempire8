# B19 — Golpes, revoluções, secessões e guerra civil: análise de projeto

Estado: **análise, sem código**. Objetivo: o relógio da revolução (B18) passar a ter consequência real,
de forma realista, justa para o jogador e determinística. Só depois desta análise começa a integração.

## 1. Referências (Paradox, Victoria 3)
- Dev diary #41 (Revoluções): o movimento político tem *apoio* (força da revolta) e *radicalismo* (chance de
  revoltar). Radicalismo vem de pops radicais e do clout de grupos de interesse irritados. Ao passar do limiar
  há levante armado; os estados que se levantam são os do apoio do movimento; forma-se um país rebelde com
  leis alteradas e a mesma tecnologia; é uma guerra sem paz branca (um lado anexa o outro); generais
  desertam; evita-se cedendo às demandas, melhorando a vida dos radicais, reprimindo (decretos) ou com
  polícia/guarda nacional.
- Dev diary #130: toda guerra civil é iniciada por movimento radical; tipos têm tendência (minoria cultural →
  secessão; monarquista → revolução); revolução exige um grupo de interesse irritado ao lado do movimento;
  secessão ocorre quando o movimento é extremo e sem grupo que o apoie; movimento militar leva estados com
  quartéis; a capital pode se rebelar.
- Dev diary #42 (secessões culturais) e #14 (movimentos).

## 2. O que já temos (B15–B18)
radicalização por corrente (`radical[5]`), agitação por província (`unrest`), relógio `rev_clock` 0..12,
grupos de interesse (Militares e Clero ainda sem efeito), parlamento e votação de leis, `core_owner` por
província, países mortos (slot sem províncias) e vassalagem (`_free_vassal`).
Limitações: não há cultura/religião por província (usar `core_owner` como proxy de nação); o número de
países é fixo no save (não dá para criar país novo, só reaproveitar slot morto).

## 3. Desenho proposto
**Gatilho.** `rev_clock` chega a 12. Escolhe-se o *tipo* pela corrente dominante (`radical` máx.) e pelos grupos:
| Situação | Resultado |
|---|---|
| Militares poderosos e corrente reacionária/conservadora/nacionalista | **Golpe militar**: rápido, sem guerra; governo vira Autocracia, leis de imprensa/militar endurecem, parlamento dissolvido, Militares ganham clout. |
| Corrente socialista ou liberal dominante e grupo aliado irritado | **Revolução**: troca de regime (lei "Sistema de governo" e 2–4 leis conforme a corrente), parlamento reiniciado, estabilidade reposta a 40, rebeldes somem, nova eleição em 12 meses. |
| Corrente nacionalista e províncias de `core_owner` de um país morto | **Secessão**: essas províncias voltam ao país histórico (slot morto) como independente; guerra só se o jogador contestar. |
| Revolução + ≥ 35% das províncias rebeldes e slot morto livre | **Guerra civil** (fase B19c): rebeldes assumem as províncias rebeldes num slot morto, com leis do movimento e metade do tesouro; exércitos divididos pela localização; guerra sem paz branca. |
Todas as escolhas usam só estado salvo e aritmética inteira (sem sorteio, ou sorteio por hash de data+id).

**Ordem de entrega (cada uma com CI verde):**
- **B19a** golpe e revolução (troca de regime, sem divisão do país), aviso no relógio (6/9/12), tela de evento
  com a causa e o resultado, crônica.
- **B19b** secessão por `core_owner` com efeito de mapa (faixa/bandeira nascendo).
- **B19c** guerra civil: divisão de províncias e exércitos, sem paz branca, vitória rebelde ou legalista.

## 4. Jogador e IA
- Jogador: 3 avisos antes (6, 9, 11) com a causa e botões de saída (B20: concessões, repressão, estado de sítio).
  Derrubada do jogador não é *game over*: continua no regime novo (ou, na guerra civil, na facção que escolher).
- IA: B24 passa a reagir (reprimir, ceder, reformar) para não haver revoluções em massa.
- Calibragem: meta de **0 a 3 revoluções em 10 anos no mundo** na auditoria (nova linha no `economy_audit`).

## 5. Estado novo e riscos
Salvar: `rev_type`, `rev_cd` (carência de 60 meses após revolução), `coup_cd`; entram em `serialize/load/hash`
com padrão para saves antigos. Riscos: quebrar determinismo ao reatribuir exércitos (processar por id
ascendente); `transfer_province` e geometria (reusar `_refresh_country_geometry`); jogador sem províncias;
alianças/vassalos do país que cai (reusar a limpeza do `_annex_country`).

## 6. Fases seguintes, refinadas para imersão e realismo
| Etapa | Conteúdo | Por que importa |
|---|---|---|
| B20 | Concessões, repressão, estado de sítio, polícia secreta/guarda nacional; custo político | agência do jogador antes da crise |
| B22 (antecipada) | Cultura/religião por província, minorias, assimilação, propaganda | secessões e movimentos realistas (hoje só proxy) |
| B21 | Burocracia, corrupção, instituições (Victoria 3) | capacidade do Estado de reprimir/arrecadar |
| B23 | Planejamento, subsídios, monopólios, nacionalização | alinha economia e política |
| B13 | Desigualdade, pobreza, natalidade/mortalidade | alimenta radicais com dados reais |
| B24 | IA reagindo a crises | mundo vivo |
| B25 | Balanceamento e auditorias | fechar a trilha |
Camada de imersão transversal: **crônica** do país (linha do tempo salva), eventos históricos com escolha
(Primavera dos Povos 1848, Comuna 1871 etc. como pressão extra, não roteiro fixo), líderes nomeados nos grupos
de interesse, manchetes no HUD e efeitos de mapa para cada fenômeno.

## 7. Decisões que assumo como padrão (mude se quiser)
1. Entregar em 3 passos (B19a → B19b → B19c). 2. Cultura por província antes da guerra civil completa, se
a secessão por `core_owner` parecer rasa. 3. Revoluções não são *game over*.

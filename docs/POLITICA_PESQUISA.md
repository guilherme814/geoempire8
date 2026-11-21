# Política — análise do Victoria 3 e plano para o GeoEmpire 8

Fontes (diários oficiais da Paradox lidos nesta rodada): Dev Diary #6 (grupos de interesse), #45
(eleições), #46 (partidos políticos), #80 (promulgação de leis e relógio da revolução). O fórum e o wiki
bloqueiam leitura automática; os diários em paradoxinteractive.com abriram.

## Como o Victoria 3 estrutura a política
1. **Grupos de interesse (IG):** conjuntos de pops com visões políticas comuns. Cada um tem
   ideologia (define leis que apoia/odeia), **poder político** (pops mais ricas/estratificadas pesam
   mais), **clout** (fatia do poder total: Poderoso / Influente / Marginalizado), **líder** (pode mudar a
   ideologia do grupo), **aprovação** (leis atuais, estar no governo ou na oposição, % de leais e
   radicais) e **traços** (bônus quando felizes, ônus quando infelizes; marginalizados não ativam nada).
2. **Eleições:** a cada **4 anos** onde há leis de voto; campanha de 6 meses; cada partido tem
   **momentum** (sorte, eventos, popularidade dos líderes); quem vota depende da lei de distribuição do
   poder: voto por terra (aristocratas, capitalistas, clero, oficiais) → por riqueza → censitário
   (alfabetizados pesam mais) → universal. Discriminados e pops sem grupo ficam de fora.
   O resultado dá poder político aos IG, pesa forte na **legitimidade**; ganhar o voto não forma
   governo sozinho — o jogador escolhe o governo.
3. **Partidos:** só em países com eleições; são **alianças de IG** (até 11 tipos: liberal, conservador,
   comunista, fascista, agrário...); formam e dissolvem dinamicamente; IG troca de partido conforme
   ideologia, líder e condições nacionais; o governo entra/sai como blocos de partidos.
4. **Leis:** promulgação em **3 fases** (cada checagem: sucesso/avança/debate/trava, conforme apoio e
   oposição dos IG do governo); até **3 reveses** (o 3º falha de vez); cancelar gera **2 anos** de
   carência e, se um movimento político defendia a lei, sua radicalização dispara.
5. **Movimentos políticos e revolução:** movimento vira **revolucionário** quando a radicalização é
   alta; o **relógio da revolução** enche com eventos e clout; pode levar um ou vários estados.
6. **Legitimidade:** efeito da eleição + leis + atitude dos IG; afeta a eficácia do governo.

## O que o GeoEmpire 8 já tem (derivado, sem partidos)
6 classes com satisfação, 5 correntes ideológicas (conservadorismo, liberalismo, socialismo,
nacionalismo, reacionarismo), poder político por classe (alfabetização pesa), "encaixe" das leis com
cada corrente, legitimidade e estabilidade, líderes históricos (só apresentação), decretos/orçamento.
**Faltam:** partidos, eleições e parlamento, grupos de interesse com clout, movimentos radicais e
revolução/golpe, votação das leis, carência/revés na promulgação.

## Plano adaptado (mobile, determinístico, poucos estados novos)
| Etapa | Conteúdo | Estado novo |
|---|---|---|
| B14+B15 | **Partidos por corrente + eleições a cada 4 anos + parlamento (100 cadeiras)**. Sufrágio vem da lei de governo: autocracia sem eleição; monarquia constitucional = voto censitário (aristocratas, burguesia, funcionários); república = voto amplo. Resultado: cadeiras, apoio ao governo, ±estabilidade | `elect_cd`, `seats[5]` |
| B16 | **Grupos de interesse** (Industriais, Latifundiários, Sindicatos, Militares, Clero) derivados das classes: clout, aprovação, traços | derivado |
| B17 | **Votação das leis no parlamento** em 3 fases, reveses e carência de 2 anos; apoio parlamentar | `law_try` |
| B18 | **Movimentos**: radicalização por corrente insatisfeita; greves e protestos | `radical[5]` |
| B19 | **Revolução/golpe**: relógio da revolução, perda de províncias, mudança de regime | `rev_clock` |
| B20–B24 | Legitimidade e reformas/repressão, burocracia e corrupção, cultura/religião/minorias, política econômica avançada, IA reagindo | a definir |

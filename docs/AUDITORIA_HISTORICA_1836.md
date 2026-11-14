# Auditoria histórica — GeoEmpire 1836

Aplicada por `tools/historical_fixes.py` (idempotente) sobre `data/world.json`, `data/history_1836.json`,
`data/flags.json` e `data/ai_profiles.json`. Fontes: Maddison Project 2020, censo dos EUA de 1840,
censos britânicos de 1831/1841, estimativas provinciais Qing c.1850, literatura geral.

## Corrigido

| Tema | Problema | Correção |
|---|---|---|
| População por província | O total por país era histórico, mas a divisão interna seguia a geografia atual: Flórida 1,7 M, Taipé 15 M, Guiana Francesa 2 M, Canadá/Austrália com mais gente que a Inglaterra, Irlanda quase vazia | Redistribuída em EUA (censo 1840), Qing (≈1850), Reino Unido (Inglaterra/Escócia/Irlanda + colônias), França, Japão, Países Baixos (Java), Rússia (Sibéria/Alasca), México (Texas/Califórnia/Utah) |
| Reino Unido | Núcleo (GB + Irlanda) subestimado | ≈ 25 M no núcleo + colônias ≈ 5 M; total 30,5 M |
| Argélia | Toda a Argélia era francesa (5,9 M) | Só Argel é francesa (≈150 mil). Mascara/Médéa viram o **Emirado de Abd al-Qadir** (novo país). Constantina (Batna, Sétif, M'Sila, Oum el Bouaghi) volta ao Império Otomano |
| Sultanato de Sulu | Pertencia à Espanha | Independente (sem dono) |
| Norte de Sumatra | Pertencia aos Países Baixos | Passa a Aceh |
| Escravidão (flag) | Países Baixos, Espanha, Portugal, Dinamarca, Suécia, Otomano, Egito, Marrocos, Sokoto, Pérsia, Nova Granada e Peru estavam sem escravidão | Marcados com escravidão (colônias/instituição vigente em 1836) |
| México | "República federal": o federalismo acabou em 1835 | República centralista instável |
| Peru | "Confederação": a Confederação Peru-Boliviana só nasce em out. 1836 | República em guerra civil |
| Nomes | "Đại Nam" (nome adotado em 1839); "Confederação Marata" (extinta em 1818); "Württemberg" (também inclui Baden) | "Việt Nam", "Estados Maratas", "Württemberg e Baden" |
| Eventos | Coroação de Vitória (1837), Paris 1848, Sabinada (1837), Balaiada (1838), Maioridade (1840) | Já tinham data própria: nenhum evento chega antes da hora |

## Pendente (por gravidade)

**Alta**
- A divisão do mapa usa **fronteiras administrativas modernas**: muitas províncias de 1836 não existem (ex.: Alemanha reduzida a poucos blocos). Reconstruir as fronteiras de 1836 exige redesenhar o mapa.
- Estados alemães faltantes: Baden (fundido a Württemberg), Oldenburg, Nassau, Brunswick, cidades hanseáticas.
- República do Texas (independência em março de 1836) segue como província mexicana.
- Cáucaso: Daguestão e Chechênia aparecem como russos, mas o Imamado de Xamil (1834) os controlava de fato.
- Distribuição da população dentro de Japão, Brasil, Argentina, Rússia europeia, Otomano e Índia ainda herda a distribuição moderna.

**Média**
- Países Baixos: Bornéu e Sulawesi controlados só parcialmente na época.
- Montenegro e Hamburgo/Frankfurt inexistentes; Luxemburgo/Limburgo sem tratamento especial até 1839.
- Estados Maratas, Mysore e outros principados da Índia eram protetorados britânicos: aqui são países jogáveis independentes.
- África subsaariana tem poucos estados (Bornu, Axante, Daomé, Buganda faltam).
- Custos de construção e recrutamento em £ não foram calibrados com preços reais (a escala foi ancorada no PIB).

**Baixa**
- Rússia e Áustria usam PIB per capita estimado (Maddison não cobre o império inteiro).
- Governos/ideologias de ~40 países pequenos usam o perfil padrão (sem entrada própria em `history_1836.json`).

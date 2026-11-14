#!/usr/bin/env python3
"""Correções históricas de 1836 aplicadas a data/world.json e data/history_1836.json (idempotente).
Fontes: censo dos EUA de 1840, estimativas provinciais Qing c.1850, censos britânicos 1831/1841,
Maddison Project e literatura geral. Veja docs/AUDITORIA_HISTORICA_1836.md."""
import json, sys

W = 'data/world.json'
H = 'data/history_1836.json'
F = 'data/flags.json'
w = json.load(open(W))
if w.get('historical_fixes_v1'):
    print('já aplicado'); sys.exit(0)
tag_of = {c['tag']: c['id'] for c in w['countries']}
by_name = {}
for p in w['provinces']:
    by_name.setdefault(p['name'], []).append(p)


def prov(name, owner_tag=None):
    for p in by_name[name]:
        if owner_tag is None or p['owner'] == tag_of[owner_tag]:
            return p
    raise KeyError(name)


def set_owner(name, from_tag, to_tag):
    p = prov(name, from_tag)
    p['owner'] = tag_of[to_tag] if to_tag else None


def provs_of(tag):
    return [p for p in w['provinces'] if p['owner'] == tag_of[tag]]


def redistribute(tag, targets=None, mult=None, total=None, default=None, rule=None):
    """targets: nome -> milhões (valor absoluto). mult: palavra-chave -> fator sobre a pop atual.
    rule: função(p)->fator. Demais províncias dividem o resto proporcionalmente.
    O total do país é preservado (ou `total`, em milhões)."""
    ps = provs_of(tag)
    target_total = (total if total is not None else sum(p['pop'] for p in ps) / 1e6)
    fixed = {}
    for p in ps:
        if targets and p['name'] in targets:
            fixed[id(p)] = targets[p['name']] * 1e6
    free = [p for p in ps if id(p) not in fixed]
    weights = {}
    for p in free:
        f = 1.0
        if mult:
            for k, v in mult.items():
                if k.lower() in p['name'].lower():
                    f *= v
        if rule:
            f *= rule(p)
        if default is not None and not (targets and p['name'] in targets):
            f *= 1.0
        weights[id(p)] = max(1.0, p['pop'] * f)
    rest = target_total * 1e6 - sum(fixed.values())
    if free:
        wsum = sum(weights.values())
        for p in free:
            fixed[id(p)] = max(100.0, rest * weights[id(p)] / wsum)
    s = sum(fixed.values())
    scale = target_total * 1e6 / s
    for p in ps:
        p['pop'] = max(100, int(round(fixed[id(p)] * scale)))


# ------------------------------------------------------------------ nomes
for c in w['countries']:
    if c['tag'] == 'WUR': c['name'] = 'Württemberg e Baden'
    if c['tag'] == 'MAR': c['name'] = 'Estados Maratas'
    if c['tag'] == 'VNM': c['name'] = 'Việt Nam'

# ------------------------------------------------------------------ Argélia (1836)
# Argel e arredores franceses; Mascara/Médéa: emirado de Abd al-Qadir; Constantina: beilicado otomano.
new_id = len(w['countries'])
w['countries'].append({'id': new_id, 'tag': 'ABD', 'name': 'Emirado de Abd al-Qadir', 'color': '#2e7d4f',
                       'capital': prov('Mascara')['id'], 'pop_total': 1.5})
tag_of['ABD'] = new_id
set_owner('Mascara', 'FRA', 'ABD'); set_owner('Médéa', 'FRA', 'ABD')
for n in ('Batna', 'Sétif', "M'Sila", 'Oum el Bouaghi'):
    set_owner(n, 'FRA', 'OTT')
for n, v in (('Algiers', 150000), ('Mascara', 900000), ('Médéa', 600000), ('Batna', 350000), ('Sétif', 500000),
             ("M'Sila", 250000), ('Oum el Bouaghi', 300000)):
    prov(n)['pop'] = v

# Sultanato de Sulu era independente
for n in ('Sulu', 'Tawi-Tawi'):
    set_owner(n, 'ESP', None)
# Norte de Sumatra: fora do controle holandês em 1836 (Aceh e reinos batak)
for n in ('Sumatera Utara I', 'Sumatera Utara II', 'Sumatera Utara III'):
    set_owner(n, 'NED', 'ACE')

# ------------------------------------------------------------------ população por província
redistribute('USA', targets={
    'New York': 2.43, 'Pennsylvania': 1.72, 'Ohio': 1.52, 'Virginia': 1.0, 'West Virginia': 0.22, 'Tennessee': 0.83,
    'Kentucky': 0.78, 'North Carolina': 0.75, 'Massachusetts': 0.74, 'Georgia': 0.69, 'Indiana': 0.69,
    'South Carolina': 0.59, 'Alabama': 0.59, 'Maine': 0.50, 'Illinois': 0.48, 'Mississippi': 0.38, 'Missouri': 0.38,
    'Louisiana': 0.35, 'New Hampshire': 0.28, 'Michigan': 0.21, 'Arkansas': 0.10, 'Florida': 0.054, 'Iowa': 0.043,
    'Wisconsin': 0.03, 'Washington,  D.C.': 0.033, 'Oklahoma': 0.03, 'Minnesota': 0.001, 'Kansas': 0.001,
    'Nebraska': 0.001})

redistribute('QNG', targets={
    'Guangdong': 28, 'Beijing': 28, 'Jiangsu': 44, 'Shandong': 37, 'Xinjiang I': 1.2, 'Xinjiang II': 0.5,
    'Xinjiang III': 0.05, 'Xinjiang IV': 0.2, 'Qinghai': 1.0, 'Taipei': 2.5, 'Heilongjiang': 0.3, 'Liaoning': 3.0,
    'Sichuan Leste': 30, 'Sichuan Oeste': 2, 'Chongqing': 12, 'Hubei': 33, 'Henan': 29, 'Anhui': 37, 'Hunan': 20,
    'Guangxi': 8, 'Zhejiang': 30, 'Fujian': 25, 'Shanxi': 15, 'Jiangxi': 24, 'Shaanxi': 14, 'Guizhou': 7,
    'Inner Mongol I': 0.6, 'Inner Mongol II': 0.8, 'Inner Mongol III': 0.01, 'Inner Mongol IV': 0.05,
    'Inner Mongol V': 0.5, 'Amur': 0.05, 'Jilin': 0.5, 'Yunnan IV': 5, 'Yunnan V': 0.8, 'Yunnan III': 0.5,
    'Yunnan I': 0.3, 'Yunnan II': 0.1, 'Gansu I': 6, 'Gansu III': 7, 'Gansu II': 0.5, 'Ningxia': 1.5, 'Hainan': 1.5,
    'Xizang I': 0.25, 'Xizang II': 0.25, 'Xizang III': 0.25, 'Xizang IV': 0.25, 'Xizang V': 0.25, 'Xizang VI': 0.25,
    "Primor'ye": 0.01}, default=0.05, rule=lambda p: 0.0)   # aimags da Mongólia: ~0,05 M cada

# Reino Unido: núcleo (Inglaterra/Gales, Escócia, Irlanda) + colônias (censos 1831/1841)
gbr = {'London': 2.4, 'Lincolnshire': 4.4, 'Cumbria': 3.6, 'North East': 2.6, 'Dorset': 1.2, 'Devon': 0.9,
       'Gwynedd': 0.7, 'Dumfries and Galloway': 1.0, 'Scottish Borders': 0.6, 'Aberdeenshire': 0.5,
       'Perthshire and Kinross': 0.35, 'Highland': 0.2, 'Argyll and Bute': 0.1, 'Eilean Siar': 0.03,
       'Shetland Islands': 0.03, 'Dublin': 2.2, 'Cork': 1.8, 'Donegal': 1.1, 'Mayo': 1.2, 'Sligo': 0.6, 'Laoighis': 0.9,
       'Ontario Leste': 0.25, 'Ontario Oeste': 0.15, 'Québec I': 0.55, 'Québec II': 0.01, 'Québec III': 0.001,
       'Nova Scotia': 0.20, 'New Brunswick': 0.15, 'Prince Edward Island': 0.05, 'Newfoundland and Labrador': 0.07,
       'Canberra': 0.05, 'Victoria': 0.005, 'Tasmania I': 0.015, 'Tasmania II': 0.015, 'Tasmania III': 0.01,
       'Western Australia I': 0.001, 'Western Australia II': 0.001, 'Western Australia III': 0.001,
       'Western Australia IV': 0.001, 'Western Australia V': 0.001, 'Western Cape': 0.25, 'Eastern Cape': 0.15,
       'Northern Cape': 0.02, 'Colombo': 0.8, 'Puttalama': 0.35, 'Georgetown': 0.09, 'Pulau Pinang': 0.04,
       'Melaka': 0.03, 'Kingston': 0.38, 'Port Louis': 0.1, 'Belmopan': 0.01, 'Port-of-Spain': 0.04, 'Banjul': 0.005,
       'Falkland Islands': 0.0005, 'Ionioi Nisoi Norte': 0.1, 'Ionioi Nisoi Sul': 0.1}
redistribute('GBR', targets=gbr, total=None)
gbr_sum = sum(p['pop'] for p in provs_of('GBR'))
# o total passa a ser o das metas (o resto, ilhas das Bahamas etc., é desprezível)
for c in w['countries']:
    if c['tag'] == 'GBR':
        c['pop_total'] = round(sum(gbr.values()) + 0.05, 2)
redistribute('GBR', targets=gbr, total=sum(gbr.values()) + 0.05)

redistribute('FRA', targets={'Guyane française': 0.02, 'La Réunion': 0.11, 'Guadeloupe': 0.13, 'Martinique': 0.12,
                             'Algiers': 0.15, 'Monaco': 0.007}, total=33.8)
redistribute('JAP', targets={'Hokkaidō': 0.06, 'Niigata': 1.5, 'Nagasaki': 0.5, 'Kagoshima': 0.9,
                             'Okinawa Sul': 0.12, 'Okinawa Norte': 0.05})
redistribute('NED', targets={'The Hague': 1.3, 'Amsterdam': 1.3, 'Luxembourg': 0.17, 'Paramaribo': 0.06,
                             'Jakarta': 1.8, 'Jawa Tengah': 3.0, 'Jawa Timur': 2.9}, total=11.8)
redistribute('RUS', rule=lambda p: (0.005 if p['name'].startswith('Alaska') else (0.12 if p['lon'] > 60 else 1.0)))
redistribute('MEX', mult={'Texas': 0.04, 'California': 0.04, 'Nevada': 0.02, 'Utah': 0.02, 'Arizona': 0.03,
                          'New Mexico': 0.2, 'Baja': 0.1})
redistribute('ABD', targets={'Mascara': 0.9, 'Médéa': 0.6})
redistribute('OTT', total=25.4)   # inclui Constantina

# pop_total de cada país = soma das províncias
sums = {}
for p in w['provinces']:
    if p['owner'] is not None:
        sums[p['owner']] = sums.get(p['owner'], 0) + p['pop']
for c in w['countries']:
    if c['id'] in sums:
        c['pop_total'] = round(sums[c['id']] / 1e6, 3)
w['historical_fixes_v1'] = True
json.dump(w, open(W, 'w'), ensure_ascii=False, separators=(',', ':'))

# ------------------------------------------------------------------ flags
f = json.load(open(F))
f['ABD'] = {'t': 'h', 'c': ['#2e7d4f', '#ffffff']}
json.dump(f, open(F, 'w'), ensure_ascii=False, indent=1)

# ------------------------------------------------------------------ história
h = json.load(open(H))
for t in ('NED', 'ESP', 'POR', 'DEN', 'SWE', 'OTT', 'EGY', 'MOR', 'SOK', 'IRN', 'NGR', 'PER'):
    if t in h: h[t]['slavery'] = True
if 'PER' in h:
    h['PER']['gov'] = 'republica_em_guerra_civil'; h['PER']['orient'] = 'caudilhismo_pre_confederacao'
if 'MEX' in h:
    h['MEX']['gov'] = 'republica_centralista_instavel'; h['MEX']['orient'] = 'centralismo_santannista'
h['ABD'] = {'gov': 'emirado_de_resistencia', 'orient': 'islamismo_sufi_anticolonial', 'stab': 3, 'cent': 2, 'cap': 1,
            'tax': 1, 'ind': 1, 'urb': 1, 'trade': 1, 'slavery': True, 'army': 2, 'navy': 0, 'mil': 3}
json.dump(h, open(H, 'w'), ensure_ascii=False, indent=1)
print('ok')

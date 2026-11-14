#!/usr/bin/env python3
"""Segunda leva de correções de 1836 (idempotente): República do Texas, Imamado do Cáucaso, Montenegro
e guerras que já estavam em curso em 1º de janeiro de 1836. Veja docs/AUDITORIA_HISTORICA_1836.md."""
import json, sys
W, H, F, A = 'data/world.json', 'data/history_1836.json', 'data/flags.json', 'data/ai_profiles.json'
w = json.load(open(W))
if w.get('historical_fixes_v2'):
    print('já aplicado'); sys.exit(0)
tag_of = {c['tag']: c['id'] for c in w['countries']}


def prov(name):
    return next(p for p in w['provinces'] if p['name'] == name)


def new_country(tag, name, color, capital_name, pop_by_province, owner_from):
    cid = len(w['countries'])
    w['countries'].append({'id': cid, 'tag': tag, 'name': name, 'color': color,
                           'capital': prov(capital_name)['id'], 'pop_total': round(sum(pop_by_province.values()) / 1e6, 3)})
    tag_of[tag] = cid
    for n, pop in pop_by_province.items():
        p = prov(n)
        p['owner'] = cid
        p['pop'] = pop
    return cid


new_country('TEX', 'República do Texas', '#1f4e9c', 'Texas II',
            {'Texas I': 15000, 'Texas II': 30000, 'Texas III': 25000}, 'MEX')
new_country('CAU', 'Imamado do Cáucaso', '#3b7a3b', 'Dagestan', {'Dagestan': 810000}, 'RUS')
new_country('MNE', 'Principado de Montenegro', '#a31621', 'Nikšic', {'Nikšic': 100000}, 'OTT')

# pop_total dos países que perderam províncias
sums = {}
for p in w['provinces']:
    if p['owner'] >= 0:
        sums[p['owner']] = sums.get(p['owner'], 0) + p['pop']
for c in w['countries']:
    if c['id'] in sums:
        c['pop_total'] = round(sums[c['id']] / 1e6, 3)
w['historical_fixes_v2'] = True
json.dump(w, open(W, 'w'), ensure_ascii=False, separators=(',', ':'))

f = json.load(open(F))
f['TEX'] = {'t': 'h', 'c': ['#ffffff', '#bf0a30']}
f['CAU'] = {'t': 'plain', 'c': '#2e7d32'}
f['MNE'] = {'t': 'h', 'c': ['#c40308', '#1d3c85', '#ffffff']}
json.dump(f, open(F, 'w'), ensure_ascii=False, indent=1)

h = json.load(open(H))
h['TEX'] = {'gov': 'republica_provisoria', 'orient': 'colonizacao_anglo_americana', 'stab': 2, 'cent': 1, 'cap': 1, 'tax': 1,
            'ind': 1, 'urb': 1, 'trade': 1, 'slavery': True, 'army': 1, 'navy': 0, 'mil': 2}
h['CAU'] = {'gov': 'imamado_teocratico_de_guerra', 'orient': 'islamismo_naqshbandi_anti_russo', 'stab': 3, 'cent': 1, 'cap': 1,
            'tax': 1, 'ind': 1, 'urb': 1, 'trade': 1, 'slavery': True, 'army': 2, 'navy': 0, 'mil': 3}
h['MNE'] = {'gov': 'principado_teocratico', 'orient': 'ortodoxia_njegos', 'stab': 3, 'cent': 1, 'cap': 1, 'tax': 1, 'ind': 1,
            'urb': 1, 'trade': 1, 'slavery': False, 'army': 1, 'navy': 0, 'mil': 3}
# guerras já em curso em 1/1/1836: [atacante, alvo]
h['_start_wars'] = [['MEX', 'TEX'], ['FRA', 'ABD'], ['RUS', 'CAU']]
json.dump(h, open(H, 'w'), ensure_ascii=False, indent=1)

a = json.load(open(A))
a['TEX'] = {'ambition': 30, 'boldness': 55, 'rivals': ['MEX'], 'claims': [], 'protect': [], 'balance': False,
            'weights': {'rivalry': 140}}
a['CAU'] = {'ambition': 20, 'boldness': 60, 'rivals': ['RUS'], 'claims': [], 'protect': [], 'balance': False,
            'weights': {'rivalry': 160}}
a['MNE'] = {'ambition': 15, 'boldness': 50, 'rivals': ['OTT'], 'claims': [], 'protect': [], 'balance': False,
            'weights': {'rivalry': 120}}
json.dump(a, open(A, 'w'), ensure_ascii=False, indent=1)
print('ok')

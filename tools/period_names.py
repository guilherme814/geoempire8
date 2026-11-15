#!/usr/bin/env python3
"""Aplica nomes de época (1836) em data/world.json: províncias, cidades e capitais.
Idempotente (flag period_names_v1). Só toca em texto exibido; ids e geometria ficam iguais."""
import json, sys, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PATH = os.path.join(ROOT, "data", "world.json")

# nome moderno -> nome de 1836 (PT-BR). Vale para 'name' e 'city'.
NAMES = {
    "Istanbul": "Constantinopla", "Izmir": "Esmirna", "Ankara": "Angora", "Bursa": "Brusa",
    "Tokyo": "Edo", "Beijing": "Pequim", "Taipei": "Formosa Norte", "Guangdong": "Cantão",
    "Ulaanbaatar": "Urga", "Seoul": "Hanyang", "Yangon": "Rangum", "Naypyidaw": "Ava",
    "Mandalay": "Ava", "Kuala Lumpur": "Selangor", "Dhaka": "Daca", "New Delhi": "Délhi",
    "Maharashtra": "Bombaim", "Mumbai": "Bombaim", "Tamil Nadu": "Madras", "Chennai": "Madras",
    "West Bengal": "Bengala", "Kolkata": "Calcutá", "Jakarta": "Batávia", "Kyiv": "Kiev",
    "Kyiv (cidade)": "Kiev", "Tallinn": "Reval", "Sverdlovsk": "Ecaterimburgo",
    "Kirov": "Viatka", "Volgograd": "Tsarítsin", "Nur-Sultan": "Akmolinsk", "Astana": "Akmolinsk",
    "Belmopan": "Belize", "Hanoi": "Thang Long", "Da Nang": "Tourane", "Ho Chi Minh City": "Saigon",
    "Bengaluru": "Bangalore", "Thiruvananthapuram": "Trivandrum", "Kerala Sul": "Travancore",
    "Kerala Norte": "Malabar", "Karnataka": "Mysore", "Telangana": "Haiderabade",
    "Chandigarh": "Lahore", "Punjab": "Panjabe", "Karachi": "Carachi", "Kota Kinabalu": "Brunei",
    "Banda Aceh": "Kutaraja", "Ipoh": "Perak", "Riyadh": "Diriyah", "Qom": "Teerã",
    "Jalalabad": "Cabul", "Beni Suef": "Cairo", "Dese": "Gondar",
    "Amhara": "Amara", "Mostaganem": "Mascara", "Makhachkala": "Temir-Khan-Shura",
    "Sankt-Peterburg": "São Petersburgo", "St.  Petersburg": "São Petersburgo", "Moscow": "Moscou",
    "Warsaw": "Varsóvia", "Masovian": "Mazóvia", "Helsinki": "Helsinque", "Oslo": "Cristiânia",
    "Prague": "Praga", "Vienna": "Viena", "Lisbon": "Lisboa", "Athens": "Atenas", "Brussels": "Bruxelas",
    "Munich": "Munique", "Florence": "Florença", "Naples": "Nápoles", "Rome": "Roma", "Turin": "Turim",
    "Belgrade": "Belgrado", "Bucharest": "Bucareste", "Sofia": "Sófia", "Zagreb": "Agram",
    "Budapest": "Buda e Peste", "Bern": "Berna", "Cairo": "Cairo", "Algiers": "Argel",
    "Tunis": "Túnis", "Baghdad": "Bagdá", "Damascus": "Damasco", "Aleppo": "Alepo",
    "Tehran": "Teerã", "Kabul": "Cabul", "Kathmandu": "Catmandu", "Bangkok": "Krung Thep",
    "Hawaii III": "Maui", "Wailuku": "Lahaina", "Lagos": "Lagos", "Baku": "Baku",
    "Yerevan": "Erevan", "Tbilisi": "Tíflis", "Rio Branco": "Seringal Acre", "Acre": "Território do Acre",
    "Brasília": "Planalto Central", "Rondônia": "Mato Grosso Oeste", "Amapá": "Guiana Brasileira",
    "Roraima": "Alto Rio Branco", "Tocantins": "Goiás Norte", "Ottawa": "Bytown",
    "Bogota": "Santa Fé de Bogotá", "Sucre": "Chuquisaca", "Fargona": "Kokand", "Nukus": "Khiva",
    "Samarkand": "Samarcanda", "Taza": "Fez", "Pietermaritzburg": "Zululândia",
    "Fukushima": "Mutsu", "Aomori": "Mutsu", "Hokkaidō": "Ezo", "Okinawa": "Ryukyu",
    "Chongqing": "Sichuan Leste", "Nanjing": "Jiangning", "Ho Chi Minh": "Saigon",
    "Phnom Penh": "Udong", "Vientiane": "Vientiane", "Naypyidaw (cidade)": "Ava",
    "Dhaka (cidade)": "Daca", "Colombo": "Colombo", "Chişinău": "Quichinau", "Chișinău": "Quichinau",
    "Minsk": "Minsk", "Vilnius": "Vilna", "Riga": "Riga", "Gdansk": "Danzig", "Greater Poland": "Posnânia",
    "Lesser Poland": "Galícia Ocidental", "Silesia": "Silésia", "Pomerania": "Pomerânia",
    "Kaliningrad": "Königsberg", "Bratislava": "Pressburgo", "Ljubljana": "Laibach",
    "Rijeka": "Fiume", "Cluj": "Klausenburg", "Timis": "Temesvár", "Brasov": "Kronstadt",
    "Cernăuți": "Czernowitz", "Chernivtsi": "Czernowitz", "Lviv": "Lemberg", "Ternopil'": "Tarnopol",
    "Ivano-Frankivs'k": "Stanislau", "Donets'k": "Yuzovka", "Dnipropetrovs'k": "Yekaterinoslav",
    "Dnipro": "Yekaterinoslav", "Odesa": "Odessa", "Kharkiv": "Carcóvia", "Luhans'k": "Lugansk",
    "Hovedstaden": "Copenhague", "Helsingfors": "Helsinque", "Turku": "Åbo", "Tartu": "Dorpat",
    "Mexico City": "Cidade do México", "Guatemala City": "Nova Guatemala", "Havana": "Havana",
    "Wellington": "Port Nicholson", "Canberra": "Nova Gales do Sul", "Sydney": "Sydney",
    "Honiara": "Ilhas Salomão", "Apia": "Samoa", "Dili": "Timor Português", "Bandar Seri Begawan": "Brunei",
}

# (tag) -> (id da província que passa a ser capital, rótulo da cidade em 1836)
CAPITALS = {
    "RUS": (52, "São Petersburgo"),
    "OTT": (570, "Constantinopla"),
    "NGR": (None, "Santa Fé de Bogotá"),
    "ABD": (None, "Mascara"),
    "BUR": (None, "Ava"),
    "VNM": (None, "Huế"),
    "BOL": (None, "Chuquisaca"),
    "HAI": (None, "Porto Príncipe"),
    "DEN": (None, "Copenhague"),
    "MNE": (None, "Cetinje"),
    "NAJ": (None, "Diriyah"),
    "IRN": (None, "Teerã"),
    "AFG": (None, "Cabul"),
    "EGY": (None, "Cairo"),
    "ETH": (None, "Gondar"),
    "ZUL": (None, "Ulundi"),
    "MAL": (None, "Perak"),
    "BRU": (None, "Brunei"),
    "ACE": (None, "Kutaraja"),
    "CAU": (None, "Dargo"),
    "KHI": (None, "Khiva"),
    "BUK": (None, "Bucara"),
    "KOK": (None, "Kokand"),
    "MOR": (None, "Fez"),
    "SIK": (None, "Lahore"),
    "SND": (None, "Haiderabade do Sind"),
    "JAP": (None, "Edo"),
    "QNG": (None, "Pequim"),
    "KOR": (None, "Hanyang"),
    "SIA": (None, "Krung Thep"),
    "HAW": (None, "Lahaina"),
}


def main() -> int:
    w = json.load(open(PATH, encoding="utf-8"))
    if w.get("period_names_v1"):
        print("já aplicado")
        return 0
    n = 0
    for p in w["provinces"]:
        for k in ("name", "city"):
            v = p.get(k) or ""
            if v in NAMES and NAMES[v] != v:
                p[k] = NAMES[v]
                n += 1
    byid = {c["tag"]: c for c in w["countries"]}
    for tag, (pid, label) in CAPITALS.items():
        c = byid.get(tag)
        if c is None:
            continue
        if pid is not None and w["provinces"][pid]["owner"] == c["id"]:
            old = w["provinces"][c["capital"]]
            old["capital_city"] = False
            c["capital"] = pid
            w["provinces"][pid]["capital_city"] = True
        cap = w["provinces"][c["capital"]]
        cap["city"] = label
    w["period_names_v1"] = True
    json.dump(w, open(PATH, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
    print("nomes alterados:", n)
    return 0


if __name__ == "__main__":
    sys.exit(main())

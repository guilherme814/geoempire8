"""Dados históricos do mapa de 1836 (usado por generate_world_1836.py).

Base geográfica: Natural Earth (domínio público) - divisões admin-1 modernas.
Cada divisão é atribuída ao Estado que a controlava por volta de 1836. É uma
aproximação de jogo (a granularidade é a das divisões modernas), não um atlas
histórico: fronteiras que cortam uma divisão moderna ficam do lado dominante.
"""
import colorsys
import math

# (chave, nome, cor, população em milhões, capital (lon, lat))
STATES = [
    ("GBR", "Reino Unido", "#c0392b", 26.5, (-0.13, 51.5)),
    ("FRA", "França", "#3b6fb6", 33.8, (2.35, 48.86)),
    ("RUS", "Império Russo", "#4f7a4c", 62.0, (30.3, 59.93)),
    ("PRU", "Prússia", "#55596e", 14.5, (13.4, 52.52)),
    ("AUT", "Império Austríaco", "#d8d09a", 34.0, (16.37, 48.2)),
    ("OTT", "Império Otomano", "#2f8f83", 24.0, (28.98, 41.01)),
    ("ESP", "Espanha", "#e08f2e", 16.0, (-3.7, 40.42)),
    ("POR", "Portugal", "#1f7a3c", 6.0, (-9.14, 38.72)),
    ("NED", "Países Baixos", "#f2a65a", 12.0, (4.9, 52.37)),
    ("BEL", "Bélgica", "#b8962e", 4.2, (4.35, 50.85)),
    ("SWE", "Suécia-Noruega", "#5aa0d8", 4.4, (18.07, 59.33)),
    ("DEN", "Dinamarca", "#d45b5b", 2.5, (12.57, 55.68)),
    ("SAR", "Sardenha-Piemonte", "#6e8ec4", 4.8, (7.68, 45.07)),
    ("SIC", "Duas Sicílias", "#8f6cc0", 8.0, (14.27, 40.85)),
    ("PAP", "Estados Papais", "#ece4c0", 2.8, (12.5, 41.9)),
    ("TUS", "Toscana", "#c98fa6", 1.5, (11.25, 43.77)),
    ("BAV", "Baviera", "#4db0e8", 4.3, (11.58, 48.14)),
    ("SAX", "Saxônia", "#86a84e", 1.7, (13.74, 51.05)),
    ("HAN", "Hanôver", "#a02f62", 1.7, (9.73, 52.37)),
    ("WUR", "Württemberg", "#a6703c", 3.0, (9.18, 48.78)),
    ("HES", "Hesse", "#c8a2de", 1.5, (8.65, 49.87)),
    ("MEC", "Mecklemburgo", "#8fbcaa", 0.65, (11.4, 53.63)),
    ("THU", "Estados da Turíngia", "#b5bc6c", 1.0, (11.03, 50.98)),
    ("SUI", "Suíça", "#d4d4d4", 2.2, (7.45, 46.95)),
    ("GRE", "Grécia", "#67bde6", 0.8, (23.73, 37.98)),
    ("SER", "Sérvia", "#a8507c", 0.9, (20.46, 44.8)),
    ("VAL", "Principados Danubianos", "#6d9140", 3.5, (26.1, 44.43)),
    ("USA", "Estados Unidos", "#2f4f9a", 15.5, (-77.04, 38.9)),
    ("MEX", "México", "#3e9a5a", 7.5, (-99.13, 19.43)),
    ("CAM", "Províncias Unidas da América Central", "#d6c04a", 1.5, (-90.5, 14.63)),
    ("HAI", "Haiti", "#b04a8a", 0.9, (-72.33, 18.54)),
    ("NGR", "Nova Granada", "#e6b84a", 2.0, (-74.07, 4.71)),
    ("VEN", "Venezuela", "#d97a3a", 1.0, (-66.9, 10.5)),
    ("ECU", "Equador", "#4aa89a", 0.7, (-78.5, -0.2)),
    ("PER", "Peru", "#c85a6a", 1.5, (-77.04, -12.05)),
    ("BOL", "Bolívia", "#7a9a3a", 1.1, (-65.26, -19.04)),
    ("BRZ", "Império do Brasil", "#3fae5a", 6.5, (-43.2, -22.9)),
    ("ARG", "Confederação Argentina", "#7fc4e8", 0.9, (-58.4, -34.6)),
    ("URU", "Uruguai", "#5a7fc8", 0.2, (-56.2, -34.9)),
    ("PAR", "Paraguai", "#c8645a", 0.4, (-57.6, -25.3)),
    ("CHL", "Chile", "#a83a4a", 1.3, (-70.65, -33.45)),
    ("HAW", "Reino do Havaí", "#e8a0b8", 0.1, (-156.68, 20.87)),
    ("QNG", "Dinastia Qing", "#e2cf3c", 400.0, (116.4, 39.9)),
    ("JAP", "Japão", "#d1495b", 30.0, (139.7, 35.7)),
    ("KOR", "Joseon", "#8ecae6", 13.0, (126.98, 37.57)),
    ("VNM", "Đại Nam", "#e2704f", 9.0, (107.6, 16.46)),
    ("SIA", "Sião", "#9b6de0", 4.6, (100.5, 13.75)),
    ("BUR", "Birmânia", "#a7c957", 4.5, (96.03, 21.9)),
    ("IRN", "Pérsia", "#86c084", 7.0, (51.4, 35.7)),
    ("AFG", "Afeganistão", "#6b5b95", 3.5, (69.2, 34.5)),
    ("NEP", "Nepal", "#d0607a", 3.0, (85.3, 27.7)),
    ("BIC", "Companhia das Índias Orientais", "#e87a7a", 95.0, (88.36, 22.57)),
    ("SIK", "Império Sikh", "#e8b04a", 4.5, (74.3, 31.55)),
    ("SND", "Emirados do Sinde", "#6ab0a0", 1.0, (68.37, 25.4)),
    ("HYD", "Hiderabade", "#8a4a9a", 10.0, (78.47, 17.38)),
    ("MYS", "Mysore", "#c8883a", 3.5, (76.64, 12.3)),
    ("TRV", "Travancore", "#4a8ac8", 1.5, (76.95, 8.5)),
    ("RAJ", "Rajputana", "#d4783a", 9.0, (75.8, 26.9)),
    ("MAR", "Confederação Marata", "#e8c84a", 12.0, (75.85, 22.7)),
    ("MAL", "Sultanatos Malaios", "#5ab87a", 1.5, (101.1, 4.6)),
    ("BRU", "Sultanato de Brunei", "#d8b0e0", 0.5, (114.94, 4.89)),
    ("ACE", "Aceh", "#4a9a6a", 0.4, (95.32, 5.55)),
    ("EGY", "Egito", "#c8a46a", 6.0, (31.24, 30.04)),
    ("NAJ", "Emirado de Najd", "#8a7a4a", 0.8, (46.7, 24.6)),
    ("OMA", "Omã", "#b84a4a", 1.5, (58.4, 23.6)),
    ("KHI", "Canato de Khiva", "#7a9ac8", 0.8, (60.36, 41.38)),
    ("BUK", "Emirado de Bucara", "#4a7a9a", 2.2, (64.4, 39.77)),
    ("KOK", "Canato de Cocanda", "#9ac84a", 3.0, (71.8, 40.4)),
    ("MOR", "Marrocos", "#c85a3a", 5.0, (-5.0, 34.03)),
    ("TUN", "Túnis", "#e07a5a", 1.0, (10.18, 36.8)),
    ("ETH", "Etiópia", "#7a4ab0", 7.0, (37.5, 12.6)),
    ("SOK", "Califado de Sokoto", "#5a9a4a", 8.0, (6.0, 13.0)),
    ("ZUL", "Reino Zulu", "#c87a9a", 0.4, (31.4, -28.3)),
    ("MAD", "Reino de Madagascar", "#6a4a9a", 2.5, (47.5, -18.9)),
]
STATE_KEYS = [s[0] for s in STATES]

_DEFAULT = {
    "GBR": "GBR", "IRL": "GBR", "FRA": "FRA", "ESP": "ESP", "PRT": "POR", "NLD": "NED", "BEL": "BEL",
    "LUX": "NED", "CHE": "SUI", "AUT": "AUT", "CZE": "AUT", "SVK": "AUT", "HUN": "AUT", "SVN": "AUT",
    "HRV": "AUT", "BIH": "OTT", "ALB": "OTT", "MKD": "OTT", "KOS": "OTT", "BGR": "OTT", "MNE": "OTT",
    "CYP": "OTT", "TUR": "OTT", "IRQ": "OTT", "LBY": "OTT", "MLT": "GBR", "SMR": "PAP", "VAT": "PAP",
    "MCO": "FRA", "LIE": "AUT", "AND": "ESP", "NOR": "SWE", "SWE": "SWE", "DNK": "DEN", "GRL": "DEN",
    "ISL": "DEN", "FRO": "DEN", "FIN": "RUS", "EST": "RUS", "LVA": "RUS", "LTU": "RUS", "BLR": "RUS",
    "MDA": "RUS", "ARM": "RUS", "AZE": "RUS", "SYR": "EGY", "LBN": "EGY", "ISR": "EGY", "PSE": "EGY",
    "JOR": "EGY", "EGY": "EGY", "TUN": "TUN", "MAR": "MOR", "IRN": "IRN", "AFG": "AFG", "NPL": "NEP",
    "BGD": "BIC", "LKA": "GBR", "THA": "SIA", "LAO": "SIA", "KHM": "VNM", "VNM": "VNM", "PHL": "ESP",
    "TLS": "POR", "BRN": "BRU", "SGP": "GBR", "CHN": "QNG", "HKG": "QNG", "MAC": "POR", "TWN": "QNG",
    "MNG": "QNG", "KOR": "KOR", "PRK": "KOR", "JPN": "JAP", "OMN": "OMA", "ETH": "ETH", "MDG": "MAD",
    "GNB": "POR", "CPV": "POR", "STP": "POR", "MUS": "GBR", "SYC": "GBR", "GMB": "GBR",
    "MEX": "MEX", "GTM": "CAM", "SLV": "CAM", "HND": "CAM", "NIC": "CAM", "CRI": "CAM", "BLZ": "GBR",
    "PAN": "NGR", "CUB": "ESP", "PRI": "ESP", "DOM": "HAI", "HTI": "HAI", "JAM": "GBR", "BHS": "GBR",
    "BRB": "GBR", "TTO": "GBR", "COL": "NGR", "VEN": "VEN", "ECU": "ECU", "PER": "PER", "BOL": "BOL",
    "BRA": "BRZ", "PRY": "PAR", "URY": "URU", "GUY": "GBR", "SUR": "NED", "FLK": "GBR",
}

_US_CORE = {
    "Maine", "New Hampshire", "Vermont", "Massachusetts", "Rhode Island", "Connecticut", "New York",
    "New Jersey", "Pennsylvania", "Delaware", "Maryland", "District of Columbia", "Virginia",
    "West Virginia", "North Carolina", "South Carolina", "Georgia", "Florida", "Alabama", "Mississippi",
    "Louisiana", "Tennessee", "Kentucky", "Ohio", "Indiana", "Illinois", "Michigan", "Wisconsin",
    "Minnesota", "Iowa", "Missouri", "Arkansas", "Kansas", "Nebraska", "Oklahoma",
}
_US_MEXICAN = {"Texas", "California", "Nevada", "Utah", "Arizona", "New Mexico"}
_CAN_BRITISH = {"Ontario", "Québec", "New Brunswick", "Nova Scotia", "Prince Edward Island",
                "Newfoundland and Labrador"}
_DE = {
    "Bayern": "BAV", "Baden-Württemberg": "WUR", "Sachsen": "SAX", "Thüringen": "THU", "Hessen": "HES",
    "Niedersachsen": "HAN", "Bremen": "HAN", "Hamburg": "HAN", "Schleswig-Holstein": "DEN",
    "Mecklenburg-Vorpommern": "MEC",
}
_IT = {
    "Piemonte": "SAR", "Valle d'Aosta": "SAR", "Liguria": "SAR", "Sardegna": "SAR",
    "Lombardia": "AUT", "Veneto": "AUT", "Friuli-Venezia Giulia": "AUT", "Trentino-Alto Adige": "AUT",
    "Emilia-Romagna": "PAP", "Marche": "PAP", "Umbria": "PAP", "Lazio": "PAP", "Toscana": "TUS",
}
_PL_PRU = {"Silesian", "Lower Silesian", "Opole", "Warmian-Masurian", "Lubusz", "West Pomeranian",
           "Pomeranian", "Kuyavian-Pomeranian", "Greater Poland"}
_PL_AUT = {"Lesser Poland", "Subcarpathian"}
_RO_AUT = {"Satu Mare", "Arad", "Bihor", "Timis", "Caras-Severin", "Maramures", "Cluj", "Bistrita-Nasaud",
           "Salaj", "Hunedoara", "Covasna", "Brasov", "Sibiu", "Mures", "Harghita", "Alba", "Suceava"}
_RO_OTT = {"Constanta", "Tulcea"}
_IN_SPECIAL = {
    "Punjab": "SIK", "Himachal Pradesh": "SIK", "Jammu and Kashmir": "SIK", "Ladakh": "SIK",
    "Chandigarh": "SIK", "Telangana": "HYD", "Karnataka": "MYS", "Kerala": "TRV", "Rajasthan": "RAJ",
    "Madhya Pradesh": "MAR", "Goa": "POR", "Dadra and Nagar Haveli and Daman and Diu": "POR",
    "Puducherry": "FRA", "Arunachal Pradesh": None, "Nagaland": None, "Manipur": None, "Mizoram": None,
    "Tripura": None, "Meghalaya": None, "Sikkim": None, "Andaman and Nicobar": None, "Lakshadweep": None,
}
_MY_PEN = {"Perlis", "Kedah", "Kelantan", "Perak", "Selangor", "Negeri Sembilan", "Johor", "Pahang",
           "Terengganu", "Kuala Lumpur", "Putrajaya"}
_SA_EGY = {"Makkah", "Al Madinah", "Tabuk", "Al Bahah"}
_SA_NAJ = {"Ar Riyad", "Al Quassim", "Ha'il", "Ash Sharqiyah", "Al Hudud ash Shamaliyah", "Al Jawf"}
_NG_SOK = {"Kebbi", "Niger", "Kwara", "Sokoto", "Zamfara", "Katsina", "Jigawa", "Kano", "Kaduna", "Bauchi",
           "Gombe", "Yobe", "Borno", "Adamawa", "Taraba", "Plateau", "Nassarawa", "Kogi",
           "Federal Capital Territory"}
_TZ_OMA = {"Tanga", "Pwani", "Dar-Es-Salaam", "Lindi", "Mtwara", "Zanzibar South and Central",
           "Kaskazini-Unguja", "Zanzibar West", "Kusini-Pemba", "Kaskazini-Pemba"}
_AO_POR = {"Luanda", "Bengo", "Cuanza Norte", "Cuanza Sul", "Benguela", "Namibe", "Cabinda", "Zaire"}
_MZ_POR = {"Maputo", "Gaza", "Inhambane", "Sofala", "Zambezia", "Nampula", "Cabo Delgado"}
_KZ_KOK = {"South Kazakhstan", "Zhambyl", "Qyzylorda", "Almaty", "Almaty City"}


def owner_for(a3, name, region, lon, lat):
    """Chave do Estado de 1836 dono da divisão admin-1, ou None (terra sem dono)."""
    n = (name or "").lower()
    if a3 == "DEU":
        return _DE.get(name, "PRU")
    if a3 == "ITA":
        return _IT.get(region, "SIC")
    if a3 == "POL":
        if name in _PL_PRU:
            return "PRU"
        return "AUT" if name in _PL_AUT else "RUS"
    if a3 == "ROU":
        if name in _RO_AUT:
            return "AUT"
        return "OTT" if name in _RO_OTT else "VAL"
    if a3 == "SRB":
        if lat > 45.0:
            return "AUT"
        return "OTT" if lat < 43.9 else "SER"
    if a3 == "GRC":
        if "ioni" in n:
            return "GBR"
        if name in ("Peloponnisos", "Attiki", "Stereá Elláda", "Dytiki Ellada"):
            return "GRE"
        return "OTT"
    if a3 == "UKR":
        return "AUT" if (lon < 26.8 and lat < 50.6) else "RUS"
    if a3 == "GEO":
        return "OTT" if "ajaria" in n else "RUS"
    if a3 == "RUS":
        if "kaliningrad" in n:
            return "PRU"
        if any(k in n for k in ("primor", "amur", "yevrey", "jewish")):
            return "QNG"
        if "sakhalin" in n:
            return None
        return "RUS"
    if a3 == "KAZ":
        if name in _KZ_KOK:
            return "KOK"
        return "KHI" if name == "Mangghystau" else "RUS"
    if a3 == "UZB":
        if name in ("Ferghana", "Namangan", "Andijon", "Tashkent", "Sirdaryo"):
            return "KOK"
        return "KHI" if name in ("Karakalpakstan", "Khorezm") else "BUK"
    if a3 == "TJK":
        return "KOK" if name == "Leninabad" else "BUK"
    if a3 == "KGZ":
        return "KOK"
    if a3 == "TKM":
        if name == "Tashauz":
            return "KHI"
        return "BUK" if name == "Chardzhou" else None
    if a3 == "PAK":
        if name == "Sind":
            return "SND"
        return None if name == "Baluchistan" else "SIK"
    if a3 == "IND":
        return _IN_SPECIAL.get(name, "BIC") if name in _IN_SPECIAL else "BIC"
    if a3 == "MMR":
        return "BIC" if name in ("Rakhine", "Tanintharyi") else "BUR"
    if a3 == "MYS":
        if name in _MY_PEN:
            return "MAL"
        if name in ("Pulau Pinang", "Melaka", "Labuan"):
            return "GBR"
        return "BRU"
    if a3 == "IDN":
        if "aceh" in n:
            return "ACE"
        return None if "papua" in n else "NED"
    if a3 == "SAU":
        if name in _SA_EGY:
            return "EGY"
        return "NAJ" if name in _SA_NAJ else None
    if a3 == "SDN":
        return None if "darfur" in n else "EGY"
    if a3 == "DZA":
        return "FRA" if lat > 35.2 else None
    if a3 == "KEN":
        return "OMA" if name == "Coast" else None
    if a3 == "TZA":
        return "OMA" if name in _TZ_OMA else None
    if a3 == "ZAF":
        if name in ("Western Cape", "Eastern Cape", "Northern Cape"):
            return "GBR"
        return "ZUL" if name == "KwaZulu-Natal" else None
    if a3 == "AGO":
        return "POR" if name in _AO_POR else None
    if a3 == "MOZ":
        return "POR" if name in _MZ_POR else None
    if a3 == "NGA":
        return "SOK" if name in _NG_SOK else None
    if a3 == "AUS":
        if name in ("New South Wales", "Victoria", "Tasmania", "Australian Capital Territory",
                    "Western Australia"):
            return "GBR"
        return None
    if a3 == "USA":
        if name in _US_CORE:
            return "USA"
        if name in _US_MEXICAN:
            return "MEX"
        if name == "Alaska":
            return "RUS"
        return "HAW" if name == "Hawaii" else None
    if a3 == "CAN":
        return "GBR" if name in _CAN_BRITISH else None
    if a3 == "ARG":
        return None if lat < -39.5 else "ARG"
    if a3 == "CHL":
        return None if lat < -38.5 else "CHL"
    return _DEFAULT.get(a3)


# ---------------------------------------------------------------------------
# Densidade de províncias: espaçamento alvo em km (retângulos; os últimos vencem)
# (lon0, lat0, lon1, lat1, km)
# ---------------------------------------------------------------------------
DENSITY_DEFAULT_KM = 440
DENSITY_RECTS = [
    # regiões esparsas
    (-180, 60, 180, 90, 800),      # ártico
    (45, 56, 180, 75, 800),        # Sibéria
    (-170, 52, -60, 75, 800),      # Canadá/Alasca
    (-17, 15, 36, 31, 780),        # Saara
    (36, 16, 60, 30, 700),         # Arábia
    (112, -35, 154, -12, 620),     # Austrália
    (-73, -12, -50, 4, 620),       # Amazônia
    (74, 32, 100, 40, 650),        # Tibete
    (50, 36, 90, 52, 560),         # Ásia Central
    (-75, -56, -62, -38, 640),     # Patagônia
    (12, -28, 26, -16, 640),       # Kalahari
    (-60, 60, -20, 85, 800),       # Groenlândia
    # regiões médias
    (-100, 20, -60, 35, 280),      # sudeste dos EUA
    (-100, 35, -65, 50, 280),      # nordeste dos EUA
    (-118, 14, -86, 33, 300),      # México
    (-60, -35, -34, -5, 340),      # Brasil leste
    (95, 5, 125, 25, 300),         # Sudeste Asiático continental
    (95, -10, 140, 8, 320),        # Indonésia
    (68, 6, 92, 36, 270),          # Índia
    (98, 20, 124, 42, 260),        # China
    (124, 33, 146, 46, 240),       # Coreia e Japão
    (44, 26, 62, 40, 340),         # Pérsia
    (-18, 28, 12, 38, 300),        # Magrebe
    (-2, 3, 12, 12, 400),          # Golfo da Guiné
    (30, 3, 46, 16, 420),          # Etiópia
    # núcleo europeu e mediterrâneo
    (-11, 34, 45, 62, 170),
    (10, 55, 32, 70, 300),         # Escandinávia/Finlândia
    (30, 44, 45, 62, 230),         # Rússia europeia
    (25, 28, 38, 38, 200),         # Levante/Egito
    (24, 23, 34, 31.5, 200),       # delta do Nilo
]

# ---------------------------------------------------------------------------
# Terreno: elipses (lon, lat, raio_lon, raio_lat, tipo)
# ---------------------------------------------------------------------------
MOUNTAINS = [
    (10, 46.5, 5.5, 1.8), (0, 42.7, 3.2, 0.7), (24, 47, 4.2, 1.5), (44, 42.5, 5.5, 1.1), (59, 58, 1.6, 8.0),
    (85, 28.5, 12, 2.4), (88, 33, 10, 3.2), (78, 41.5, 10, 2.5), (88, 49, 4.2, 2.2), (70, 35.5, 5, 1.6),
    (50, 32.5, 4.2, 3.2), (34, 37.5, 6, 1.1), (-3, 32, 7, 1.9), (38.5, 9, 3.2, 3.8), (-111, 45, 4.5, 12),
    (-121.5, 40, 2.2, 8), (-80, 38, 3.2, 6), (-104, 22, 3.2, 8), (13, 63, 3.2, 5.5), (-4.5, 57, 1.5, 1.3),
    (18, 43.5, 3.2, 2.6), (13.5, 42.5, 1.6, 3.2), (137.5, 36, 1.6, 2.2), (148.5, -30, 2.2, 12),
    (29, -29.5, 2.6, 3.2), (75.5, 15, 1.3, 7.5), (98, 25, 3.2, 5.2), (101, 31, 3.2, 4.2), (130, 62, 12, 4.2),
    (96, 52, 6, 2.2), (-72, -45, 2.2, 8), (-70.5, -30, 1.8, 8), (-68.5, -18, 2.4, 6), (-76, -9, 2.6, 6),
    (-77.5, -1, 2.0, 4), (-75.5, 5.5, 2.0, 4), (-71, 8.5, 1.8, 2.4), (-85, 12, 4, 3), (-91, 15, 3, 2),
    (47, 38.5, 3, 2), (120.5, 23.7, 0.7, 1.6), (46, 14, 3, 3), (6, 45, 1.5, 2),
]
DESERTS = [
    (-17, 15, 36, 31), (40, 18, 56, 30), (95, 38, 112, 46), (78, 37, 90, 41), (14, -28, 24, -18),
    (120, -32, 140, -20), (55, 37, 67, 44), (55, 28, 62, 35), (69, 24, 73, 29), (-71, -27, -68, -18),
    (-117, 28, -105, 36), (35, 22, 43, 31),
]
JUNGLES = [
    (-75, -10, -50, 4), (12, -5, 30, 4), (95, -8, 141, 10), (-92, 8, -83, 17), (-12, 4, 10, 8),
    (91, 22, 98, 28), (-82, 7, -77, 9), (105, 8, 110, 16), (-48, -26, -38, -18), (76, 8, 78, 12),
]


def terrain_for(lon, lat, mountain_score):
    if mountain_score >= 0.55:
        return "mountains"
    for (x0, y0, x1, y1) in DESERTS:
        if x0 <= lon <= x1 and y0 <= lat <= y1:
            return "desert" if mountain_score < 0.3 else "hills"
    if lat > 66 or (lat > 62 and lon > 60 and lon < 180):
        return "tundra"
    if mountain_score >= 0.3:
        return "hills"
    for (x0, y0, x1, y1) in JUNGLES:
        if x0 <= lon <= x1 and y0 <= lat <= y1:
            return "jungle"
    if lat > 53 and (lon > 20 or lon < -55) and -170 < lon:
        return "forest"
    if (-95 < lon < -70 and 30 < lat < 47) or (122 < lon < 146 and 33 < lat < 48) or \
            (14 < lon < 40 and 49 < lat < 55) or (-124 < lon < -120 and 42 < lat < 50) or \
            (-50 < lon < -42 and -28 < lat < -20):
        return "forest"
    return "plains"


def mountain_score(lon, lat):
    best = 0.0
    for (cx, cy, rx, ry) in MOUNTAINS:
        d = ((lon - cx) / rx) ** 2 + ((lat - cy) / ry) ** 2
        if d < 1.0:
            best = max(best, 1.0 - 0.8 * d)
    return best


# ---------------------------------------------------------------------------
# Recursos: (recurso, [(lon0, lat0, lon1, lat1, peso)])  -> sorteio ponderado
# ---------------------------------------------------------------------------
RESOURCE_REGIONS = {
    "gold": [(-123, 36, -119, 41, 5), (140, -38, 151, -30, 5), (60, 56, 62, 60, 3), (85, 52, 90, 56, 3),
             (26, -27, 29, -25, 4), (-47, -21, -42, -17, 4), (-77, 4, -74, 8, 3), (-74, -15, -70, -12, 3),
             (-3, 5, 0, 8, 4), (-9, 10, -5, 14, 3), (118, 62, 135, 66, 2)],
    "coal": [(-4, 52, 1, 56, 6), (6, 50, 8.5, 52, 6), (17, 49.5, 20, 51, 5), (3, 50, 6, 51, 5),
             (-83, 37, -77, 41, 6), (37, 47, 40, 49, 4), (111, 36, 113.5, 39.5, 4), (2, 50, 4, 51, 4),
             (14, 49, 17, 51, 3), (-90, 38, -86, 40, 4), (150, -34, 152, -32, 3), (122, 41, 125, 43, 3),
             (85, 23, 87, 25, 4), (28, -27.5, 30.5, -25, 3), (130, 33, 131.5, 34, 2)],
    "iron": [(15, 59, 20, 68, 5), (5, 48.5, 7, 49.5, 5), (-1.5, 54, 0, 55, 3), (-4, 51.5, -2.5, 52, 3),
             (14, 47, 15.5, 47.8, 3), (58, 55, 62, 60, 4), (-95, 46.5, -91, 48.5, 4), (-79, 40, -75, 41.5, 4),
             (-45, -21, -43, -19, 4), (-3.5, 43, -2.5, 43.5, 4), (18, 50, 19.5, 51, 3), (85, 22, 87, 24, 3),
             (117, 35, 119, 37, 3), (-77, 20, -75, 21, 2), (-89, 46, -87, 47, 4), (33, 47, 34, 48.5, 4)],
    "salt": [(19.5, 49.8, 20.5, 50.3, 6), (12.5, 47.5, 13.5, 48, 5), (-3, 53, -2, 53.5, 5), (-5, 21, -2, 23, 4),
             (35, 31, 36, 32, 4), (-113, 40, -111, 41.5, 4), (104, 29, 105.5, 30, 4), (39, 12, 42, 14.5, 4),
             (74.5, 26.5, 75.5, 27.5, 4), (11, 51.5, 12, 52, 4)],
    "cotton": [(-92, 30, -80, 36, 7), (30, 25, 33, 31.5, 6), (74, 16, 79, 23, 5), (70, 21, 73, 24.5, 4),
               (71, 40, 73, 41.5, 3), (-45, -12, -36, -5, 4), (-81, -8, -78, -4, 3), (32, 13, 34, 15, 4),
               (113, 29, 120, 34, 4), (34, 36.5, 36.5, 38, 3), (-90, 33, -88, 35, 3)],
    "sugar": [(-85, 17, -60, 23, 6), (-92.5, 29, -90, 31, 5), (-41, -14, -34, -5, 6), (106, -8, 114, -6, 5),
              (121, 9, 126, 13, 4), (-60, 5, -55, 8, 4), (55, -22, 58, -19, 4), (-72, 18, -68, 20, 4)],
    "coffee": [(-47, -24, -42, -20, 6), (-77, 4, -74, 7, 4), (106, -8, 112, -6, 4), (43, 12, 45, 16, 3),
               (36, 6, 39, 9, 3), (-69, 8, -65, 10.5, 4), (-91, 13, -87, 16, 3), (79, 6, 82, 8, 2)],
    "tea": [(110, 24, 122, 32, 6), (91, 25.5, 95, 28, 4), (137, 34, 140, 36, 3), (80, 6, 81.5, 7.5, 3)],
    "spices": [(126, -4, 132, 3, 5), (75, 9, 77, 13, 4), (96, -5, 106, 5, 3), (38, -7, 40, -4, 3)],
    "silk": [(8.5, 44.5, 13.5, 46.2, 4), (3.5, 44, 5.5, 46, 3), (118, 29, 122.5, 32.5, 6), (137, 35.5, 140, 37.5, 4),
             (48.5, 36.5, 51, 38, 3), (35, 36.5, 38.5, 38.5, 2), (87, 22, 89, 25, 3)],
    "wool": [(144, -38, 151, -31, 5), (-65, -42, -58, -35, 4), (-8, 37, -3, 41, 3), (-4.5, 53, 1, 56, 3),
             (18, -34, 27, -30, 4), (166, -47, 178, -37, 3), (-5, 56, -2, 58, 2)],
    "tobacco": [(-80, 36, -76, 38, 5), (-84, 21.5, -82, 23, 4), (-77, 38, -75.5, 39.5, 3), (35, 40.5, 37, 41.5, 3),
                (22, 40.5, 24, 42, 3), (-40, -14, -38, -11, 3), (98, 3, 100, 5, 3), (121, 16, 122, 18.5, 3)],
    "opium": [(84, 24, 88.5, 27, 5), (74.5, 22.5, 76, 24.5, 4), (100.5, 24, 102.5, 26, 3), (30, 38, 31.5, 39.5, 3),
              (97, 20, 100, 23, 3)],
    "wine": [(-1.5, 43.5, 7, 49, 6), (-9, 38, -3, 42, 4), (8, 43, 13, 46, 4), (19, 47.5, 22, 48.5, 3),
             (7.5, 49, 9, 50.5, 4), (18.5, -34.5, 20, -33, 3), (-72, -35, -70, -32, 3), (-69, -34, -68, -32.5, 3)],
    "furs": [(-125, 50, -60, 65, 6), (60, 56, 160, 68, 6), (-170, 58, -140, 70, 4)],
    "livestock": [(-65, -39, -53, -30, 6), (-101, 29, -96, 33, 4), (19, 46, 22, 48, 4), (98, 44, 120, 50, 4),
                  (60, 48, 85, 54, 4), (140, -37, 150, -28, 3), (-100, 36, -96, 42, 3), (-58, -34, -53, -30, 4)],
    "fish": [(-57, 46, -50, 52, 6), (3, 58, 12, 70, 5), (-80, -22, -72, -5, 5), (140, 35, 146, 45, 4),
             (-5, 54, 8, 62, 4), (-175, 50, -150, 62, 3), (12, -28, 16, -18, 3)],
}
# recurso padrão quando nenhuma região casa
FALLBACK_BY_TERRAIN = {
    "plains": [("grain", 7), ("livestock", 2), ("cotton", 1)],
    "hills": [("grain", 3), ("livestock", 3), ("iron", 2), ("wine", 1)],
    "mountains": [("iron", 4), ("coal", 2), ("gold", 1), ("salt", 1), ("timber", 2)],
    "forest": [("timber", 7), ("furs", 2), ("grain", 1)],
    "desert": [("salt", 3), ("livestock", 2), ("cotton", 1)],
    "tundra": [("furs", 5), ("fish", 3), ("timber", 1)],
    "jungle": [("timber", 4), ("spices", 1), ("sugar", 2), ("coffee", 1)],
}

TERRAIN_POP_FACTOR = {"plains": 1.0, "hills": 0.7, "mountains": 0.35, "forest": 0.5, "desert": 0.08,
                      "tundra": 0.04, "jungle": 0.4}


def unclaimed_density(lon, lat):
    """Habitantes por km² em terras sem dono (povos nativos)."""
    if lat > 60:
        return 0.05
    if -18 < lon < 52 and -35 < lat < 16:
        return 3.0
    if -60 < lon < 150 and 16 <= lat <= 35 and -18 < lon < 60:
        return 0.6
    return 0.4


def auto_colors(n, seed=7):
    out = []
    for i in range(n):
        h = (i * 0.61803398875 + seed * 0.13) % 1.0
        r, g, b = colorsys.hsv_to_rgb(h, 0.5, 0.78)
        out.append("#%02x%02x%02x" % (int(r * 255), int(g * 255), int(b * 255)))
    return out

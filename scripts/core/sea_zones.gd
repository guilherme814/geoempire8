class_name SeaZones
extends RefCounted
## Zonas marítimas (aproximadas por longitude/latitude) e as passagens que as ligam.
## Dado puro e estático; o controlador de cada passagem é decidido em Game (dono da província-âncora).

const ATL := 0
const MED := 1
const BLACK := 2
const BALTIC := 3
const IND := 4
const PAC := 5
const COUNT := 6

## [zona A, zona B, id da passagem ("" = livre)]
const EDGES := [
	[BALTIC, ATL, "oresund"],
	[ATL, MED, "gibraltar"],
	[MED, BLACK, "straits"],
	[ATL, IND, "cape"],
	[IND, PAC, "malacca"],
	[ATL, PAC, ""],
]


static func zone_of(lon: float, lat: float) -> int:
	if lon >= 12.6 and lon <= 31.0 and lat >= 53.5 and lat <= 66.0 and not (lat > 57.3 and lon < 14.5):
		return BALTIC
	if (lon >= 26.5 and lat >= 42.0 and lon <= 42.0 and lat <= 47.5) or (lon >= 28.0 and lat >= 41.3 and lon <= 42.0 and lat <= 47.5):
		return BLACK
	if lon >= -6.0 and lon <= 36.0 and lat >= 30.0 and lat <= 46.0:
		return MED
	if lon >= 25.0 and lon <= 32.0 and lat < -25.0:
		return IND
	if lon >= 32.0 and lon <= 103.6 and lat >= -35.0 and lat <= 30.0:
		return IND
	if lon > 103.6 and lon <= 129.0 and lat < -10.0:
		return IND
	if lon > 103.6 or lon <= -100.0:
		return PAC
	if lon <= -70.0 and lat <= 0.0:
		return PAC
	return ATL

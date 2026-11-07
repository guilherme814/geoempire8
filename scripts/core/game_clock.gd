class_name GameClock
extends RefCounted
## Calendário do jogo. 1 tick de simulação = 1 dia.

const MONTHS := ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

var year: int = 1836
var month: int = 1
var day: int = 1


static func is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0


static func days_in_month(y: int, m: int) -> int:
	if m == 2:
		return 29 if is_leap(y) else 28
	if m == 4 or m == 6 or m == 9 or m == 11:
		return 30
	return 31


## Avança um dia. Retorna true se o mês virou.
func advance_day() -> bool:
	day += 1
	if day > days_in_month(year, month):
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
		return true
	return false


func format() -> String:
	return "%d %s %d" % [day, MONTHS[month - 1], year]


func to_dict() -> Dictionary:
	return {"year": year, "month": month, "day": day}


func from_dict(d: Dictionary) -> void:
	year = int(d.get("year", 1836))
	month = int(d.get("month", 1))
	day = int(d.get("day", 1))

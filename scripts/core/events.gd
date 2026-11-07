extends Node
## Barramento global de eventos (autoload "Events").
## A simulação emite; a UI e o mapa escutam. Nunca o contrário.

signal world_loaded
signal state_loaded

signal tick_advanced(tick: int)
signal day_changed(date: Dictionary)
signal month_changed(date: Dictionary)
signal speed_changed(speed: int)

signal province_selected(province_id: int)
signal province_changed(province_id: int)
signal treasury_changed(country_id: int)
signal player_country_changed(country_id: int)
signal map_mode_changed(mode: int)

signal command_applied(cmd: Dictionary)

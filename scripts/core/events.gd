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
signal province_changed(province_id: int)    # troca de dono (refaz fronteiras e cores)
signal province_updated(province_id: int)    # economia/militar mudou (não mexe no mapa estático)
signal treasury_changed(country_id: int)
signal player_country_changed(country_id: int)
signal map_mode_changed(mode: int)

signal army_changed(army_id: int)
signal army_removed(army_id: int)
signal army_selected(army_id: int)           # -1 = nenhum

signal game_event_changed                    # a lista de eventos pendentes mudou

signal command_applied(cmd: Dictionary)

## Guerras declaradas ou encerradas.
signal war_changed

## Aviso curto para o jogador local (ex.: paz recusada).
signal notice(text: String)

## Frotas (navios no mapa).
signal fleet_changed(fleet_id: int)
signal fleet_removed(fleet_id: int)
signal fleet_selected(fleet_id: int)          # -1 = nenhuma

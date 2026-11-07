extends Node
## Cena principal: monta mapa, câmera e HUD e liga os sinais entre eles.
## Os nós são criados por código para que o .tscn seja mínimo e fácil de versionar.

var map_view: MapView
var camera: MapCamera
var hud: HUD


func _ready() -> void:
	if not Game.loaded:
		push_error("GeoEmpire: mundo não carregado; verifique data/world.json")
		return

	map_view = MapView.new()
	map_view.name = "MapView"
	add_child(map_view)

	camera = MapCamera.new()
	camera.name = "MapCamera"
	camera.map_size = Game.map_size
	add_child(camera)

	hud = HUD.new()
	hud.name = "HUD"
	hud.map_view = map_view
	add_child(hud)

	camera.ui_blocker = hud.is_over_ui
	camera.tapped.connect(_on_map_tapped)
	camera.zoom_changed.connect(map_view.set_zoom_level)
	Events.player_country_changed.connect(_on_player_changed)

	# Começa enquadrando o país do jogador.
	_on_player_changed(Game.player_country)


func _on_map_tapped(world_pos: Vector2) -> void:
	# Toque no mar retorna -1 e limpa a seleção.
	Events.province_selected.emit(map_view.province_at(world_pos))


func _on_player_changed(country_id: int) -> void:
	camera.focus_rect(Game.countries[country_id].bounds)

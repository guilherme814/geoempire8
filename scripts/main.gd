extends Node
## Cena principal: monta mapa, câmera e HUD e liga os sinais entre eles.
## Os nós são criados por código para que o .tscn seja mínimo e fácil de versionar.
##
## Toque no mapa:
##  - sobre um marcador de exército  -> seleciona o exército;
##  - com um exército SEU selecionado, sobre uma província -> ordem de marcha;
##  - caso contrário -> seleciona a província (mar limpa a seleção).

var map_view: MapView
var overlay: MapOverlay
var camera: MapCamera
var hud: HUD


func _ready() -> void:
	if not Game.loaded:
		push_error("GeoEmpire: mundo não carregado; verifique data/world.json")
		return

	map_view = MapView.new()
	map_view.name = "MapView"
	add_child(map_view)

	overlay = MapOverlay.new()
	overlay.name = "MapOverlay"
	map_view.add_child(overlay)   # filho: desenhado por cima do mapa estático

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
	camera.zoom_changed.connect(_on_zoom_changed)
	Events.player_country_changed.connect(_on_player_changed)

	# Começa enquadrando a capital do país do jogador.
	_on_player_changed(Game.player_country)


func _on_zoom_changed(z: float) -> void:
	map_view.set_zoom_level(z)
	overlay.set_zoom_level(z)


func _on_map_tapped(world_pos: Vector2) -> void:
	var aid := overlay.army_at(world_pos)
	if aid >= 0:
		var a: Army = Game.armies[aid]
		Events.army_selected.emit(aid)
		Events.province_selected.emit(a.province_id)
		return

	var pid := map_view.province_at(world_pos)
	var sel: Army = Game.armies.get(overlay.selected_army)
	if sel != null and pid >= 0 and sel.owner_id == Game.player_country:
		if pid == sel.province_id and not sel.is_moving():
			Events.army_selected.emit(-1)      # tocar na própria província desmarca
			Events.province_selected.emit(pid)
			return
		Game.submit_command(Cmd.move_army(sel.id, pid))
		Events.province_selected.emit(pid)
		return

	# Sem seleção: tocar numa província com exército SEU seleciona o exército (alvo grande no celular).
	if pid >= 0:
		for a in Game.armies.values():
			var army: Army = a
			if army.owner_id == Game.player_country and army.province_id == pid:
				Events.army_selected.emit(army.id)
				Events.province_selected.emit(pid)
				return

	Events.army_selected.emit(-1)
	Events.province_selected.emit(pid)


func _on_player_changed(country_id: int) -> void:
	var cap := Game.provinces[Game.countries[country_id].capital]
	var half := Vector2(260.0, 160.0)
	camera.focus_rect(Rect2(cap.center - half, half * 2.0), 1.0)

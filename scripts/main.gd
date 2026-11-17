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
var select: CountrySelect
var menu: MainMenu
var _splash: SplashScreen


func _ready() -> void:
	if not Game.loaded:
		push_error("GeoEmpire: mundo não carregado; verifique data/world.json")
		return
	var splash: SplashScreen = null
	if not Net.is_online():
		splash = SplashScreen.new()
		_splash = splash
		add_child(splash)
		await get_tree().process_frame
		await get_tree().process_frame
	_boot(splash)


func _step(splash: SplashScreen, p: float, text: String) -> void:
	Events.trace.emit("boot", "%s (%.0f%%, %d ms desde o início)" % [text, p * 100.0, Time.get_ticks_msec()])
	if splash != null and is_instance_valid(splash):
		splash.set_progress(p, text)


func _boot(splash: SplashScreen) -> void:
	_step(splash, 0.1, "Preparando o som…")
	var audio := AudioManager.new()
	audio.name = "Audio"
	add_child(audio)
	await get_tree().process_frame

	_step(splash, 0.3, "Desenhando o mapa-múndi…")
	map_view = MapView.new()
	map_view.name = "MapView"
	add_child(map_view)

	overlay = MapOverlay.new()
	overlay.name = "MapOverlay"
	map_view.add_child(overlay)   # filho: desenhado por cima do mapa estático
	await get_tree().process_frame

	_step(splash, 0.6, "Posicionando a câmera…")
	camera = MapCamera.new()
	camera.name = "MapCamera"
	camera.map_size = Game.map_size
	add_child(camera)
	await get_tree().process_frame

	_step(splash, 0.8, "Montando a interface…")
	hud = HUD.new()
	hud.name = "HUD"
	hud.map_view = map_view
	add_child(hud)
	await get_tree().process_frame

	camera.ui_blocker = _is_over_ui
	camera.tapped.connect(_on_map_tapped)
	camera.zoom_changed.connect(_on_zoom_changed)
	Events.player_country_changed.connect(_on_player_changed)
	Events.focus_province.connect(_on_focus_province)
	hud.country_select_requested.connect(_open_country_select)
	hud.main_menu_requested.connect(_open_main_menu)

	if Net.is_online():
		# Online o país vem do lobby: enquadra a capital direto.
		_on_player_changed(Game.player_country)
	elif splash != null and is_instance_valid(splash):
		hud.set_ui_visible(false)
		camera.focus_rect(Rect2(Vector2.ZERO, Game.map_size), 1.0)
		splash.set_progress(1.0, "Pronto")
		splash.set_loaded()
		await splash.finished
		_open_main_menu()
	else:
		_open_main_menu()


func _is_over_ui(pos: Vector2) -> bool:
	if _splash != null and is_instance_valid(_splash):
		return true
	if hud.is_over_ui(pos):
		return true
	if menu != null and is_instance_valid(menu) and menu.is_over_ui(pos):
		return true
	return select != null and is_instance_valid(select) and select.is_over_ui(pos)


func _open_main_menu() -> void:
	Events.trace.emit("tela", "Menu principal")
	if menu != null and is_instance_valid(menu) and menu.active:
		return
	if select != null and is_instance_valid(select):
		select.queue_free()
		select = null
	hud.set_ui_visible(false)
	Game.speed = 0
	Events.speed_changed.emit(0)
	menu = MainMenu.new()
	menu.camera = camera
	menu.new_game_pressed.connect(_on_menu_new_game)
	menu.continue_pressed.connect(_on_menu_continue)
	add_child(menu)
	camera.focus_rect(Rect2(Vector2.ZERO, Game.map_size), 1.0)


func _on_menu_new_game() -> void:
	Events.trace.emit("tela", "Novo jogo")
	if menu != null and is_instance_valid(menu):
		menu.close()
	_open_country_select()


func _on_menu_continue() -> void:
	Events.trace.emit("tela", "Continuar jogo salvo")
	if menu != null and is_instance_valid(menu):
		menu.close()
	hud.set_ui_visible(true)
	_on_player_changed(Game.player_country)


func _open_country_select() -> void:
	if select != null and is_instance_valid(select):
		return
	select = CountrySelect.new()
	select.hud = hud
	select.finished.connect(_on_select_finished)
	select.back_requested.connect(_open_main_menu)
	add_child(select)
	camera.focus_rect(Rect2(Vector2.ZERO, Game.map_size), 1.0)


func _on_select_finished() -> void:
	Events.trace.emit("tela", "País escolhido: %s" % Game.countries[Game.player_country].tag)
	select = null
	if not Onboarding.tutorial_done():
		get_tree().create_timer(1.2).timeout.connect(func():
			if is_inside_tree():
				Onboarding.show_tutorial(self))


func _on_focus_province(pid: int) -> void:
	if pid < 0 or pid >= Game.provinces.size():
		return
	camera.focus_rect(Game.provinces[pid].bounds.grow(80.0), 1.0)


func _on_zoom_changed(z: float) -> void:
	map_view.set_zoom_level(z)
	overlay.set_zoom_level(z)


func _on_map_tapped(world_pos: Vector2) -> void:
	var tpid: int = map_view.province_at(world_pos)
	if tpid >= 0 and tpid < Game.provinces.size():
		var tp: Province = Game.provinces[tpid]
		Events.trace.emit("mapa", "Toque na província %d (%s, dono %s)" % [tpid, tp.name, Game.countries[tp.owner_id].tag if tp.owner_id >= 0 else "-"])
	else:
		Events.trace.emit("mapa", "Toque no mar/vazio")
	# Na tela de escolha de nação, tocar no mapa escolhe o país dono da província.
	if select != null and is_instance_valid(select) and select.active:
		select.pick_province(map_view.province_at(world_pos))
		return
	# Frotas: tocar numa frota SUA seleciona; tocar nela de novo para e desmarca;
	# com frota selecionada, tocar no mar ou num porto manda navegar.
	var fid := overlay.fleet_at(world_pos)
	var fsel: Fleet = Game.fleets.get(overlay.selected_fleet)
	if fid >= 0:
		var tapped: Fleet = Game.fleets[fid]
		if fsel != null and fid == fsel.id:
			if fsel.is_moving():
				Game.submit_command(Cmd.stop_fleet(fsel.id))
			Events.fleet_selected.emit(-1)
			return
		if tapped.owner_id == Game.player_country:
			Events.army_selected.emit(-1)
			Events.fleet_selected.emit(fid)
			Events.notice.emit("Frota de %d navio(s). Toque no mar ou num porto para navegar; toque nela de novo para parar." % tapped.ships)
			return
	if fsel != null and fsel.owner_id == Game.player_country:
		var target := -1
		var tp := map_view.province_at(world_pos)
		if tp >= 0:
			target = Game.provinces[tp].port
			if target < 0:
				Events.notice.emit("Esta província não tem porto.")
				return
		else:
			target = Game.cell_at(world_pos)
		if not Game.is_sea_cell(target):
			Events.notice.emit("Navios só navegam no mar.")
			return
		Game.submit_command(Cmd.move_fleet(fsel.id, target))
		return

	var aid := overlay.army_at(world_pos)
	if aid >= 0:
		var a: Army = Game.armies[aid]
		Events.fleet_selected.emit(-1)
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

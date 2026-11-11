class_name CountrySelect
extends CanvasLayer
## Tela inicial de escolha de nação (estilo Age of History / Victoria 3): lista de países à
## esquerda, ficha do país escolhido à direita e o mapa no meio. Tocar num país no mapa
## também o escolhe. Só offline; online o país vem do lobby.

signal finished

var hud: HUD
var active: bool = true

var _root: Control
var _blockers: Array[Control] = []
var _search: LineEdit
var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Dictionary = {}          # id do país -> botão
var _rank: Dictionary = {}          # id do país -> posição por população
var _sort_by_pop: bool = true
var _selected: int = -1

var _card_flag: FlagRect
var _card_name: Label
var _card_sub: Label
var _card_stats: VBoxContainer
var _btn_play: Button
var _btn_load: Button
var _msg: Label


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.theme = UIKit.make_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_compute_ranks()
	_build_title()
	_build_list_panel()
	_build_card()
	_resort()
	if hud != null:
		hud.set_ui_visible(false)
	Game.speed = 0
	Events.speed_changed.emit(0)
	_update_card()


func is_over_ui(pos: Vector2) -> bool:
	for c in _blockers:
		if c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
			return true
	return false


## Chamado pela cena principal quando o jogador toca numa província do mapa.
func pick_province(pid: int) -> void:
	if pid < 0 or pid >= Game.provinces.size():
		return
	var owner_id: int = Game.provinces[pid].owner_id
	if owner_id >= 0:
		_select(owner_id)


func _compute_ranks() -> void:
	var ids: Array = _alive_ids()
	ids.sort_custom(func(a, b): return _pop(a) > _pop(b) or (_pop(a) == _pop(b) and a < b))
	for i in ids.size():
		_rank[int(ids[i])] = i + 1


func _alive_ids() -> Array:
	var out: Array = []
	for c in Game.countries:
		if c.is_alive():
			out.append(c.id)
	return out


func _pop(cid: int) -> int:
	return Game.population_of(Game.countries[cid])


# ---------------------------------------------------------------------------
# Construção
# ---------------------------------------------------------------------------
func _build_title() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "BannerPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 10
	_root.add_child(panel)
	_blockers.append(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var t := UIKit.serif_label("GEOEMPIRE", 38, UIKit.GOLD_BRIGHT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var s := UIKit.label("Escolha sua nação  ·  1836", 18, UIKit.TEXT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)


func _build_list_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_left = 10
	panel.offset_right = 360
	panel.offset_top = 10
	panel.offset_bottom = -10
	_root.add_child(panel)
	_blockers.append(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	col.add_child(UIKit.serif_label("Nações do mundo", 24, UIKit.GOLD_BRIGHT))
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar país…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 42)
	_search.text_changed.connect(_on_search_changed)
	col.add_child(_search)

	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 6)
	col.add_child(sort_row)
	var group := ButtonGroup.new()
	var b_pop := UIKit.button("Por população", Vector2(0, 38))
	b_pop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_pop.toggle_mode = true
	b_pop.button_group = group
	b_pop.button_pressed = true
	b_pop.pressed.connect(_on_sort_pressed.bind(true))
	sort_row.add_child(b_pop)
	var b_az := UIKit.button("A-Z", Vector2(0, 38))
	b_az.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_az.toggle_mode = true
	b_az.button_group = group
	b_az.pressed.connect(_on_sort_pressed.bind(false))
	sort_row.add_child(b_az)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)

	var group_rows := ButtonGroup.new()
	for cid in _alive_ids():
		var c: Country = Game.countries[int(cid)]
		var b := UIKit.button("", Vector2(0, 54), "FlatButton")
		b.toggle_mode = true
		b.button_group = group_rows
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 6
		row.offset_right = -6
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var fl := FlagRect.new()
		fl.custom_minimum_size = Vector2(52, 34)
		fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fl.set_country(c.tag, c.color)
		row.add_child(fl)
		var names := VBoxContainer.new()
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		names.add_theme_constant_override("separation", -2)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(names)
		var nl := UIKit.label(c.name, 19, UIKit.TEXT)
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		names.add_child(nl)
		var sl := UIKit.label("%s hab.  ·  %d prov." % [HUD._fmt_pop(_pop(c.id)), c.province_ids.size()], 14, UIKit.TEXT_DIM)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		names.add_child(sl)
		var rk := UIKit.label("#%d" % int(_rank.get(c.id, 0)), 15, UIKit.GOLD_DIM)
		rk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(rk)
		b.pressed.connect(_select.bind(c.id))
		_list.add_child(b)
		_rows[c.id] = b


func _build_card() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -370
	panel.offset_right = -10
	panel.offset_top = 10
	panel.offset_bottom = -10
	_root.add_child(panel)
	_blockers.append(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var frame := PanelContainer.new()
	frame.theme_type_variation = "FlagFrame"
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(frame)
	_card_flag = FlagRect.new()
	_card_flag.custom_minimum_size = Vector2(220, 140)
	frame.add_child(_card_flag)

	_card_name = UIKit.serif_label("Selecione uma nação", 30, UIKit.GOLD_BRIGHT)
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_card_name)
	_card_sub = UIKit.label("", 17, UIKit.TEXT_DIM)
	_card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_card_sub)
	col.add_child(HSeparator.new())

	_card_stats = VBoxContainer.new()
	_card_stats.add_theme_constant_override("separation", 6)
	_card_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_card_stats)

	_msg = UIKit.label("", 15, UIKit.WARN)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_msg)

	_btn_play = UIKit.button("JOGAR", Vector2(0, 62), "PrimaryButton")
	_btn_play.add_theme_font_size_override("font_size", 26)
	_btn_play.pressed.connect(_on_play_pressed)
	col.add_child(_btn_play)
	_btn_load = UIKit.button("Carregar jogo salvo", Vector2(0, 46))
	_btn_load.pressed.connect(_on_load_pressed)
	col.add_child(_btn_load)


# ---------------------------------------------------------------------------
# Lógica
# ---------------------------------------------------------------------------
func _resort() -> void:
	var ids: Array = _alive_ids()
	if _sort_by_pop:
		ids.sort_custom(func(a, b): return int(_rank[a]) < int(_rank[b]))
	else:
		ids.sort_custom(func(a, b): return Game.countries[a].name.naturalnocasecmp_to(Game.countries[b].name) < 0)
	for i in ids.size():
		_list.move_child(_rows[ids[i]], i)


func _on_sort_pressed(by_pop: bool) -> void:
	_sort_by_pop = by_pop
	_resort()


func _on_search_changed(q: String) -> void:
	var needle := q.strip_edges().to_lower()
	for cid in _rows.keys():
		var c: Country = Game.countries[int(cid)]
		var ok := needle == "" or c.name.to_lower().contains(needle) or c.tag.to_lower().contains(needle)
		(_rows[cid] as Button).visible = ok


func _select(cid: int) -> void:
	if cid < 0 or cid >= Game.countries.size():
		return
	_selected = cid
	_msg.text = ""
	Game.set_player_country(cid)      # a câmera enquadra a capital (ver Main)
	var b: Button = _rows.get(cid)
	if b != null:
		b.set_pressed_no_signal(true)
		_scroll.ensure_control_visible(b)
	_update_card()


func _difficulty(rank: int) -> String:
	if rank <= 6:
		return "Grande potência  ·  fácil"
	if rank <= 20:
		return "Potência regional  ·  média"
	if rank <= 45:
		return "Estado menor  ·  difícil"
	return "Estado frágil  ·  muito difícil"


func _stat(icon_kind: String, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UiIcon.make(icon_kind, 26))
	var k := UIKit.label(key, 18, UIKit.TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	row.add_child(UIKit.label(value, 19, UIKit.TEXT))
	_card_stats.add_child(row)


func _update_card() -> void:
	UIKit.clear(_card_stats)
	_btn_play.disabled = _selected < 0
	if _selected < 0:
		_card_flag.set_country("", Color(0.3, 0.3, 0.3))
		_card_name.text = "Selecione uma nação"
		_card_sub.text = "Toque num país da lista ou no mapa"
		return
	var c: Country = Game.countries[_selected]
	var e := Game.estimate_monthly(c)
	_card_flag.set_country(c.tag, c.color)
	_card_name.text = c.name
	_card_sub.text = _difficulty(int(_rank.get(c.id, 99)))
	var cap := Game.provinces[c.capital]
	_stat("flag", "Capital", cap.city if cap.city != "" else cap.name)
	_stat("people", "População", HUD._fmt_pop(Game.population_of(c)))
	_stat("globe", "Províncias", str(c.province_ids.size()))
	_stat("book", "Alfabetização", "%d,%d%%" % [c.literacy / 10, c.literacy % 10])
	_stat("bulb", "Tecnologia", "nível %d" % c.tech_level())
	_stat("shield", "Estabilidade", "%d%%" % c.stability)
	_stat("sword", "Exército", "%d regimentos" % int(e["regiments"]))
	_stat("coin", "Tesouro", str(c.treasury))
	_stat("coin", "Saldo mensal", "%+d" % (int(e["income"]) - int(e["expense"])))


func _on_play_pressed() -> void:
	if _selected < 0:
		return
	Game.set_player_country(_selected)
	_close()
	Game.submit_command(Cmd.set_speed(1))
	Events.notice.emit("Você governa %s. Boa sorte!" % Game.countries[_selected].name)


func _on_load_pressed() -> void:
	if Game.load_game():
		_close()
	else:
		_msg.text = "Nenhum jogo salvo encontrado."


func _close() -> void:
	active = false
	if hud != null:
		hud.set_ui_visible(true)
	finished.emit()
	queue_free()

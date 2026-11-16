class_name MainMenu
extends CanvasLayer
## Tela inicial (estilo Victoria 3 / Age of History): o mapa do mundo à deriva ao fundo, título e
## menu à esquerda, painéis de opções e créditos. Só apresentação: não toca na simulação.

signal new_game_pressed
signal continue_pressed

const VERSION := "v0.12 · Alpha"
const DRIFT_SECS := 16.0

var camera: MapCamera
var active: bool = true

var _root: Control
var _theme: Theme
var _menu_col: VBoxContainer
var _btn_continue: Button
var _panel: PanelContainer
var _panel_body: VBoxContainer
var _drift: Tween
var _stops: Array[Rect2] = []
var _stop_i: int = 0
var _msg: Label


## Fundo: escurece o mapa da esquerda (onde fica o menu) para a direita e nas bordas.
class Backdrop extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var dark := Color(0.025, 0.04, 0.055, 0.94)
		var clear := Color(0.025, 0.04, 0.055, 0.12)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.62, 0), Vector2(w * 0.62, h), Vector2(0, h)]),
			PackedColorArray([dark, clear, clear, dark]))
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.16), Vector2(0, h * 0.16)]),
			PackedColorArray([Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.7), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.84), Vector2(w, h * 0.84), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.8), Color(0, 0, 0, 0.8)]))
		# filete dourado vertical separando o menu
		draw_line(Vector2(560, h * 0.12), Vector2(560, h * 0.88), Color(UIKit.GOLD_DIM, 0.55), 1.5)


func _ready() -> void:
	layer = 30
	_theme = UIKit.make_theme()
	_theme.set_type_variation("MenuBtn", "Button")
	UIKit._button_styles(_theme, "MenuBtn", Color(0.05, 0.08, 0.10, 0.82), Color(0.13, 0.30, 0.31, 0.95),
		Color(0.06, 0.15, 0.16), Color(UIKit.GOLD_DIM, 0.6), 4, 1, 14)
	_theme.set_constant("h_separation", "MenuBtn", 12)
	_root = Control.new()
	_root.theme = _theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bd := Backdrop.new()
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bd)
	_build_menu()
	_build_footer()
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.9)
	_start_drift()


func is_over_ui(_pos: Vector2) -> bool:
	return active   # a tela cheia bloqueia o mapa


func _exit_tree() -> void:
	if _drift != null and _drift.is_valid():
		_drift.kill()


# ---------------------------------------------------------------------------
func _build_menu() -> void:
	var col := VBoxContainer.new()
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 56
	col.offset_right = 520
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	_root.add_child(col)
	_menu_col = col

	var crest := UiIcon.make("crown", 54.0, UIKit.GOLD_BRIGHT)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(crest)
	var t := UIKit.serif_label("GEOEMPIRE", 72, UIKit.GOLD_BRIGHT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	t.add_theme_constant_override("shadow_offset_y", 4)
	col.add_child(t)
	var rule := CountrySelect.TitleRule.new()
	rule.custom_minimum_size = Vector2(0, 18)
	col.add_child(rule)
	var s := UIKit.label("GRANDE ESTRATÉGIA  ·  1836 — 2012", 18, UIKit.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 26)
	col.add_child(sp)

	var b_new := _menu_button("Novo jogo", true)
	b_new.pressed.connect(func(): new_game_pressed.emit())
	col.add_child(b_new)
	_btn_continue = _menu_button("Continuar")
	_btn_continue.disabled = not FileAccess.file_exists(Game.SAVE_PATH)
	_btn_continue.pressed.connect(_on_continue)
	col.add_child(_btn_continue)
	var b_mp := _menu_button("Multijogador  (em breve)")
	b_mp.disabled = true
	col.add_child(b_mp)
	var b_opt := _menu_button("Opções")
	b_opt.pressed.connect(_show_options)
	col.add_child(b_opt)
	var b_cred := _menu_button("Créditos")
	b_cred.pressed.connect(_show_credits)
	col.add_child(b_cred)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		var b_quit := _menu_button("Sair")
		b_quit.pressed.connect(func(): get_tree().quit())
		col.add_child(b_quit)
	_msg = UIKit.label("", 16, UIKit.WARN)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_msg)


func _menu_button(text: String, primary: bool = false) -> Button:
	var b := UIKit.button(text, Vector2(0, 64), "PrimaryButton" if primary else "MenuBtn")
	b.add_theme_font_size_override("font_size", 26 if primary else 23)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


func _build_footer() -> void:
	var v := UIKit.label("GeoEmpire  %s" % VERSION, 15, UIKit.TEXT_DIM)
	v.anchor_top = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 56
	v.offset_top = -40
	v.offset_bottom = -12
	_root.add_child(v)
	var q := UIKit.serif_label("“Do vapor à era digital: conduza uma nação por 176 anos.”", 20, Color(UIKit.TEXT, 0.85))
	q.anchor_left = 1.0
	q.anchor_right = 1.0
	q.anchor_top = 1.0
	q.anchor_bottom = 1.0
	q.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	q.offset_right = -40
	q.offset_top = -56
	q.offset_bottom = -16
	q.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	q.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(q)


# ---------------------------------------------------------------------------
# Painéis (opções / créditos)
# ---------------------------------------------------------------------------
func _open_panel(title: String) -> VBoxContainer:
	_close_panel()
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.custom_minimum_size = Vector2(620, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = 280
	_panel.offset_right = 280
	_root.add_child(_panel)
	_panel_body = VBoxContainer.new()
	_panel_body.add_theme_constant_override("separation", 10)
	_panel.add_child(_panel_body)
	_panel_body.add_child(UIKit.serif_label(title, 32, UIKit.GOLD_BRIGHT))
	_panel_body.add_child(HSeparator.new())
	return _panel_body


func _close_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null


func _add_close() -> void:
	var b := UIKit.button("Fechar", Vector2(0, 54))
	b.pressed.connect(_close_panel)
	_panel_body.add_child(b)


func _show_options() -> void:
	var body := _open_panel("Opções")
	var b_music := UIKit.button("", Vector2(0, 56))
	b_music.text = "Música: ligada" if AudioManager.music_on else "Música: desligada"
	b_music.pressed.connect(func():
		AudioManager.set_music(not AudioManager.music_on)
		b_music.text = "Música: ligada" if AudioManager.music_on else "Música: desligada")
	body.add_child(b_music)
	var b_sfx := UIKit.button("", Vector2(0, 56))
	b_sfx.text = "Efeitos sonoros: ligados" if AudioManager.sfx_on else "Efeitos sonoros: desligados"
	b_sfx.pressed.connect(func():
		AudioManager.set_sfx(not AudioManager.sfx_on)
		b_sfx.text = "Efeitos sonoros: ligados" if AudioManager.sfx_on else "Efeitos sonoros: desligados")
	body.add_child(b_sfx)
	_add_close()


func _show_credits() -> void:
	var body := _open_panel("Créditos")
	var lines := [
		["Design e direção", "Luis"],
		["Programação", "GDScript · Godot 4.3"],
		["Inspirações", "Victoria 3 · Age of History"],
		["Música e efeitos", "Trilha própria + síntese em código"],
	]
	for ln in lines:
		var r := HBoxContainer.new()
		var k := UIKit.label(str(ln[0]), 18, UIKit.TEXT_DIM)
		k.custom_minimum_size = Vector2(210, 0)
		r.add_child(k)
		var vv := UIKit.label(str(ln[1]), 19, UIKit.TEXT)
		vv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(vv)
		body.add_child(r)
	_add_close()


func _on_continue() -> void:
	if Game.load_game():
		continue_pressed.emit()
	else:
		_msg.text = "Não foi possível carregar o save."


# ---------------------------------------------------------------------------
# Câmera à deriva sobre as grandes capitais
# ---------------------------------------------------------------------------
func _start_drift() -> void:
	if camera == null:
		return
	for tag in ["GBR", "RUS", "QNG", "USA", "OTT", "BRZ", "FRA", "JAP"]:
		for c in Game.countries:
			if c.tag == tag and c.capital >= 0:
				var cp: Vector2 = Game.provinces[c.capital].center
				_stops.append(Rect2(cp - Vector2(330, 200), Vector2(660, 400)))
	if _stops.is_empty():
		return
	_stop_i = randi() % _stops.size()
	_drift_to(true)


func _drift_to(first: bool) -> void:
	if not active or camera == null or _stops.is_empty():
		return
	var r: Rect2 = _stops[_stop_i]
	var vs := camera.get_viewport_rect().size
	var z := clampf(minf(vs.x / (r.size.x * 1.1), vs.y / (r.size.y * 1.1)), camera.zoom_min, 3.0)
	# o centro do mapa visível fica à direita do menu: desloca o alvo para a esquerda
	var shift := Vector2(vs.x * 0.18 / z, 0.0)
	var target := r.get_center() - shift
	if first:
		camera.position = target + Vector2(120, 40)
		camera.zoom = Vector2.ONE * z
	_drift = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_drift.tween_property(camera, "position", target + Vector2(-120, -40), DRIFT_SECS)
	_drift.tween_property(camera, "zoom", Vector2.ONE * z * 1.12, DRIFT_SECS)
	_drift.chain().tween_interval(0.1)
	_drift.finished.connect(func():
		_stop_i = (_stop_i + 1) % _stops.size()
		_drift_to(true))


func close() -> void:
	active = false
	if _drift != null and _drift.is_valid():
		_drift.kill()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.35)
	tw.finished.connect(queue_free)

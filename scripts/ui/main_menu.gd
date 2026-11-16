class_name MainMenu
extends CanvasLayer
## Tela inicial (estilo Victoria 3 / Age of History): o mapa do mundo à deriva ao fundo, título e
## menu à esquerda, painéis de opções e créditos. Só apresentação: não toca na simulação.

signal new_game_pressed
signal continue_pressed

const VERSION := "v0.12.0 · Alpha"
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
var _logo_box: VBoxContainer
var _news: PanelContainer
var _cards: Array = []


## Fundo: céu de fim de tarde sobre o mapa, mais escuro à esquerda (onde fica o menu).
class Backdrop extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var dark := Color(0.02, 0.035, 0.07, 0.93)
		var clear := Color(0.03, 0.05, 0.10, 0.28)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.7, 0), Vector2(w * 0.7, h), Vector2(0, h)]),
			PackedColorArray([dark, clear, clear, dark]))
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.5), Vector2(0, h * 0.5)]),
			PackedColorArray([Color(0.05, 0.08, 0.2, 0.55), Color(0.05, 0.08, 0.2, 0.55), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.62), Vector2(w, h * 0.62), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(0.35, 0.18, 0.08, 0), Color(0.35, 0.18, 0.08, 0), Color(0.02, 0.02, 0.04, 0.85), Color(0.02, 0.02, 0.04, 0.85)]))


## Cenário animado desenhado em código: nuvens à deriva, globo girando com luzes de cidades,
## bandeiras ao vento e faíscas douradas. Só apresentação.
class Scenery extends Control:
	var t: float = 0.0
	var _lights: Array[Vector2] = []   # (longitude rad, latitude rad)
	var _clouds: Array[Vector4] = []   # x, y (0..1), escala, velocidade
	var _embers: Array[Vector4] = []   # x, y, velocidade, fase
	var _flag_cols: Array[Color] = [Color(0.72, 0.12, 0.14), Color(0.12, 0.25, 0.6), Color(0.9, 0.85, 0.75), Color(0.15, 0.4, 0.22), Color(0.75, 0.55, 0.12)]

	func _init() -> void:
		var r := RandomNumberGenerator.new()
		r.seed = 1836
		for i in 150:
			_lights.append(Vector2(r.randf_range(-PI, PI), asin(r.randf_range(-0.8, 0.9))))
		for i in 9:
			_clouds.append(Vector4(r.randf(), r.randf_range(0.04, 0.5), r.randf_range(0.6, 1.5), r.randf_range(0.004, 0.011)))
		for i in 40:
			_embers.append(Vector4(r.randf(), r.randf(), r.randf_range(0.02, 0.06), r.randf() * TAU))

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		_draw_clouds(w, h)
		_draw_flags(w, h)
		_draw_globe(w, h)
		_draw_embers(w, h)

	func _draw_clouds(w: float, h: float) -> void:
		for c in _clouds:
			var x: float = fposmod(c.x + t * c.w, 1.2) * w * 1.2 - w * 0.15
			var y: float = c.y * h
			var sc: float = c.z
			for k in 5:
				var off := Vector2(float(k) * 46.0 - 90.0, sin(float(k) * 1.7) * 14.0) * sc
				draw_circle(Vector2(x, y) + off, (38.0 + float(k % 3) * 12.0) * sc, Color(1.0, 0.86, 0.75, 0.05))

	func _draw_flags(w: float, h: float) -> void:
		for i in 5:
			var base := Vector2(w * (0.52 + 0.075 * float(i)), h * (0.02 + 0.03 * float(i % 2)))
			var fh := 120.0 + float(i % 3) * 22.0
			var fw := 70.0
			draw_line(base, base + Vector2(0, fh * 1.7), Color(0.12, 0.1, 0.08, 0.8), 3.0)
			var top := PackedVector2Array()
			var bot := PackedVector2Array()
			var cols := PackedColorArray()
			var n := 8
			for j in n + 1:
				var u := float(j) / float(n)
				var wave := sin(t * 2.2 + u * 4.2 + float(i)) * 9.0 * u
				top.append(base + Vector2(u * fw, wave))
				bot.append(base + Vector2(u * fw, fh * 0.55 + wave))
			var col: Color = _flag_cols[i % _flag_cols.size()]
			for j in n:
				var shade := 0.8 + 0.25 * sin(t * 2.2 + float(j) * 0.52 + float(i))
				var q := PackedVector2Array([top[j], top[j + 1], bot[j + 1], bot[j]])
				draw_colored_polygon(q, Color(col.r * shade, col.g * shade, col.b * shade, 0.62))

	func _draw_globe(w: float, h: float) -> void:
		var r: float = h * 0.52
		var c := Vector2(w * 0.7, h * 1.02 + r * 0.18)
		draw_circle(c, r * 1.07, Color(0.35, 0.55, 1.0, 0.08))
		draw_circle(c, r * 1.03, Color(0.45, 0.65, 1.0, 0.12))
		draw_circle(c, r, Color(0.04, 0.09, 0.2, 0.96))
		draw_circle(c + Vector2(-r * 0.12, -r * 0.1), r * 0.8, Color(0.07, 0.15, 0.3, 0.55))
		var rot: float = t * 0.07
		# meridianos e paralelos
		for i in 12:
			var lon: float = rot + TAU * float(i) / 12.0
			var k: float = sin(lon)
			var vis: float = cos(lon)
			if vis < -0.02:
				continue
			_ellipse(c, absf(k) * r, r, Color(0.55, 0.7, 1.0, 0.1 + 0.1 * vis))
		for j in range(-2, 3):
			var lat: float = float(j) * 0.4
			var y: float = sin(lat) * r
			var rr: float = cos(lat) * r
			draw_line(c + Vector2(-rr, -y), c + Vector2(rr, -y), Color(0.55, 0.7, 1.0, 0.1), 1.0)
		# luzes de cidades
		for L in _lights:
			var lon: float = L.x + rot * 1.0
			var lat: float = L.y
			var x3: float = cos(lat) * sin(lon)
			var z3: float = cos(lat) * cos(lon)
			if z3 <= 0.02:
				continue
			var p := c + Vector2(x3 * r, -sin(lat) * r)
			var tw: float = 0.55 + 0.45 * sin(t * 2.0 + L.x * 5.0)
			draw_circle(p, 2.2, Color(1.0, 0.82, 0.45, 0.55 * tw * z3))
			draw_circle(p, 5.0, Color(1.0, 0.75, 0.3, 0.1 * tw * z3))
		# arco de luz na borda superior
		draw_arc(c, r, PI * 1.12, PI * 1.88, 64, Color(0.8, 0.9, 1.0, 0.55), 3.0, true)
		draw_arc(c, r * 1.01, PI * 1.2, PI * 1.8, 64, Color(1.0, 0.9, 0.7, 0.35), 6.0, true)

	func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for i in 49:
			var a: float = TAU * float(i) / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(pts, col, 1.0, true)

	func _draw_embers(w: float, h: float) -> void:
		for e in _embers:
			var y: float = 1.0 - fposmod(e.y + t * e.z, 1.0)
			var x: float = e.x + sin(t * 0.6 + e.w) * 0.015
			var a: float = sin(y * PI) * 0.7
			draw_circle(Vector2(x * w, y * h), 1.6, Color(1.0, 0.82, 0.4, a))


class ShineRule extends Control:
	var t: float = 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var half: float = minf(size.x * 0.5, 230.0)
		draw_line(c + Vector2(-half, 0), c + Vector2(half, 0), Color(UIKit.GOLD_DIM, 0.8), 1.5)
		var sx: float = fposmod(t * 0.35, 1.4) - 0.2
		var cx: float = c.x - half + sx * half * 2.0
		for k in range(-20, 21):
			var px: float = cx + float(k) * 2.0
			if px < c.x - half or px > c.x + half:
				continue
			draw_line(Vector2(px, c.y), Vector2(px + 2.0, c.y), Color(1.0, 0.95, 0.75, (1.0 - absf(float(k)) / 20.0) * 0.9), 2.5)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(8, 0), c + Vector2(0, 6), c + Vector2(-8, 0)]), UIKit.GOLD)


func _ready() -> void:
	layer = 30
	_theme = UIKit.make_theme()
	_theme.set_type_variation("MenuBtn", "Button")
	UIKit._button_styles(_theme, "MenuBtn", Color(0.05, 0.08, 0.13, 0.86), Color(0.16, 0.26, 0.38, 0.95),
		Color(0.09, 0.15, 0.22), Color(UIKit.GOLD_DIM, 0.7), 8, 1, 10)
	_theme.set_type_variation("MenuBtnMain", "Button")
	UIKit._button_styles(_theme, "MenuBtnMain", Color(0.30, 0.22, 0.08, 0.92), Color(0.45, 0.33, 0.12, 0.98),
		Color(0.36, 0.26, 0.09), Color(UIKit.GOLD_BRIGHT, 0.9), 8, 2, 10)
	_root = Control.new()
	_root.theme = _theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bd := Backdrop.new()
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bd)
	var sc := Scenery.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(sc)
	_build_menu()
	_build_news()
	_build_top_right()
	_build_footer()
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.9)
	_animate_in()
	_start_drift()


func is_over_ui(_pos: Vector2) -> bool:
	return active   # a tela cheia bloqueia o mapa


func _exit_tree() -> void:
	if _drift != null and _drift.is_valid():
		_drift.kill()


# ---------------------------------------------------------------------------
func _save_subtitle() -> String:
	if not FileAccess.file_exists(Game.SAVE_PATH):
		return "Nenhuma campanha salva"
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.READ)
	if f == null:
		return "Retome sua campanha"
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var d: Dictionary = parsed
		var dt: Dictionary = d.get("date", {})
		var pid: int = int(d.get("player", -1))
		if pid >= 0 and pid < Game.countries.size() and dt.has("year"):
			return "%s • %d" % [Game.countries[pid].name, int(dt["year"])]
	return "Retome sua campanha"


func _build_menu() -> void:
	var col := VBoxContainer.new()
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 40
	col.offset_right = 470
	col.offset_top = 22
	col.offset_bottom = -64
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 7)
	_root.add_child(col)
	_menu_col = col

	_logo_box = VBoxContainer.new()
	_logo_box.add_theme_constant_override("separation", 2)
	col.add_child(_logo_box)
	var crest := UiIcon.make("crown", 40.0, UIKit.GOLD_BRIGHT)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_logo_box.add_child(crest)
	var tl := HBoxContainer.new()
	tl.alignment = BoxContainer.ALIGNMENT_CENTER
	tl.add_theme_constant_override("separation", 6)
	_logo_box.add_child(tl)
	var t := UIKit.serif_label("GEOEMPIRE", 58, UIKit.GOLD_BRIGHT)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	t.add_theme_constant_override("shadow_offset_y", 4)
	tl.add_child(t)
	var eight := UIKit.serif_label("8", 76, Color(1.0, 0.93, 0.7))
	eight.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	eight.add_theme_constant_override("shadow_offset_y", 4)
	tl.add_child(eight)
	var rule := ShineRule.new()
	rule.custom_minimum_size = Vector2(0, 16)
	_logo_box.add_child(rule)
	var s := UIKit.serif_label("CONQUISTE  ·  GOVERNE  ·  EXPANDA", 17, Color(UIKit.TEXT, 0.9))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo_box.add_child(s)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	col.add_child(sp)

	var has_save: bool = FileAccess.file_exists(Game.SAVE_PATH)
	_btn_continue = _menu_card("play", "Continuar Jogo", _save_subtitle(), has_save)
	_btn_continue.disabled = not has_save
	_btn_continue.pressed.connect(_on_continue)
	col.add_child(_btn_continue)
	var b_new := _menu_card("globe", "Novo Jogo", "Comece uma nova campanha")
	b_new.pressed.connect(func(): new_game_pressed.emit())
	col.add_child(b_new)
	var b_mp := _menu_card("people", "Multijogador", "Em breve")
	b_mp.disabled = true
	col.add_child(b_mp)
	var b_opt := _menu_card("gear", "Configurações", "Personalize sua experiência")
	b_opt.pressed.connect(_show_options)
	col.add_child(b_opt)
	var b_ach := _menu_card("star", "Conquistas", "Em breve")
	b_ach.disabled = true
	col.add_child(b_ach)
	var b_cred := _menu_card("book", "Créditos", "Conheça a equipe")
	b_cred.pressed.connect(_show_credits)
	col.add_child(b_cred)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		var b_quit := _menu_card("close", "Sair do Jogo", "Até a próxima!")
		b_quit.pressed.connect(func(): get_tree().quit())
		col.add_child(b_quit)
	_msg = UIKit.label("", 16, UIKit.WARN)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_msg)
	_cards = []
	for ch in col.get_children():
		if ch is Button:
			_cards.append(ch)


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in n.get_children():
		_ignore_mouse(ch)


## Cartão de menu: ícone, título, subtítulo e seta. O brilho dourado vem do tema (hover/toque).
func _menu_card(icon: String, title: String, sub: String, main: bool = false) -> Button:
	var b := UIKit.button("", Vector2(0, 62), "MenuBtnMain" if main else "MenuBtn")
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.add_theme_constant_override("separation", 14)
	b.add_child(row)
	var ic := UiIcon.make(icon, 34.0, UIKit.GOLD_BRIGHT if main else UIKit.GOLD)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var tx := VBoxContainer.new()
	tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tx.alignment = BoxContainer.ALIGNMENT_CENTER
	tx.add_theme_constant_override("separation", 0)
	row.add_child(tx)
	tx.add_child(UIKit.label(title, 22, UIKit.TEXT))
	tx.add_child(UIKit.label(sub, 14, UIKit.TEXT_DIM))
	var ar := UIKit.label("›", 34, UIKit.GOLD)
	ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ar)
	_ignore_mouse(row)
	b.button_down.connect(func(): _sfx_tap())
	return b


func _sfx_tap() -> void:
	pass


## Entrada em cascata: logo desce suavemente e os cartões surgem um a um.
func _animate_in() -> void:
	_logo_box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_logo_box, "modulate:a", 1.0, 1.0).set_delay(0.2)
	var i := 0
	for c in _cards:
		c.modulate.a = 0.0
		var tc := create_tween()
		tc.tween_interval(0.5 + 0.09 * float(i))
		tc.tween_property(c, "modulate:a", 1.0, 0.45)
		i += 1
	if _news != null:
		_news.modulate.a = 0.0
		create_tween().tween_property(_news, "modulate:a", 1.0, 0.8).set_delay(1.1)


func _build_news() -> void:
	_news = PanelContainer.new()
	_news.anchor_left = 1.0
	_news.anchor_right = 1.0
	_news.anchor_top = 1.0
	_news.anchor_bottom = 1.0
	_news.offset_left = -330
	_news.offset_right = -22
	_news.offset_top = -300
	_news.offset_bottom = -76
	_root.add_child(_news)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_news.add_child(v)
	v.add_child(UIKit.serif_label("Novidades", 22, UIKit.GOLD_BRIGHT))
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("Grande Atualização v0.12", 19, UIKit.TEXT))
	var d := UIKit.label("Árvore tecnológica, construções por era, migração, logística de exércitos e governantes históricos.", 15, UIKit.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var more := UIKit.button("Saiba mais  →", Vector2(0, 42))
	more.pressed.connect(_show_news)
	v.add_child(more)


func _show_news() -> void:
	var body := _open_panel("Novidades da v0.12")
	for ln in [
		"Árvore tecnológica com 36 tecnologias em 6 eras",
		"11 construções liberadas por tecnologia",
		"Migração e imigração entre províncias e países",
		"Logística: depósitos de suprimentos e desgaste de tropas",
		"Governantes históricos com retratos e sucessores",
		"Briefing histórico de cada país em 1836",
	]:
		var l := UIKit.label("•  " + ln, 18, UIKit.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)
	_add_close()


func _build_top_right() -> void:
	var chip := PanelContainer.new()
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.offset_left = -250
	chip.offset_right = -22
	chip.offset_top = 16
	chip.offset_bottom = 62
	_root.add_child(chip)
	var l := UIKit.label("Português (Brasil)", 18, UIKit.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)


func _build_footer() -> void:
	var bar := ColorRect.new()
	bar.color = Color(0.02, 0.03, 0.05, 0.88)
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_top = -52
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar)
	var line := ColorRect.new()
	line.color = Color(UIKit.GOLD_DIM, 0.7)
	line.anchor_right = 1.0
	line.offset_bottom = 1.5
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(line)
	var cr := UiIcon.make("crown", 26.0, UIKit.GOLD)
	cr.position = Vector2(34, 13)
	bar.add_child(cr)
	var q := UIKit.serif_label("Um simulador de estratégia global sem limites", 17, Color(UIKit.TEXT, 0.85))
	q.position = Vector2(72, 12)
	bar.add_child(q)
	var v := UIKit.label(VERSION, 15, UIKit.TEXT_DIM)
	v.anchor_left = 1.0
	v.anchor_right = 1.0
	v.offset_left = -170
	v.offset_right = -22
	v.offset_top = 14
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(v)
	var gh := UIKit.button("GitHub", Vector2(100, 38))
	gh.anchor_left = 1.0
	gh.anchor_right = 1.0
	gh.offset_left = -290
	gh.offset_right = -180
	gh.offset_top = 7
	gh.offset_bottom = 45
	gh.pressed.connect(func(): OS.shell_open("https://github.com/guilherme814/geoempire8"))
	bar.add_child(gh)


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
	if camera != null:
		create_tween().tween_property(camera, "zoom", camera.zoom * 1.18, 0.6).set_trans(Tween.TRANS_SINE)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.5)
	tw.finished.connect(queue_free)

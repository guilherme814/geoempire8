class_name SplashScreen
extends CanvasLayer
## Tela de abertura: brasão e título sobre uma rosa dos ventos, barra de carregamento com dicas
## históricas e "Toque para começar". Só apresentação; não toca na simulação.

signal finished

const MIN_SECS := 2.6
const TIPS := [
	"Em 1836 a Grã-Bretanha é a oficina do mundo; a Revolução Industrial mal começou.",
	"Pesquise tecnologias para liberar novas construções e reformas.",
	"Exércitos longe da capital precisam de depósitos de suprimentos.",
	"Estabilidade baixa traz revoltas: equilibre impostos, leis e gastos.",
	"A imigração leva gente para onde há emprego, comida e liberdade.",
	"O jogo termina em 2012: construa o seu legado ao longo de 176 anos.",
	"Alianças e vassalagem mudam o equilíbrio de poder entre as nações.",
]

var _root: Control
var _bar_fill: ColorRect
var _bar_back: ColorRect
var _status: Label
var _tip: Label
var _prompt: Label
var _rose: Control
var _progress: float = 0.0
var _shown: float = 0.0
var _t: float = 0.0
var _ready_to_go: bool = false
var _closing: bool = false


## Rosa dos ventos girando devagar atrás do título.
class Rose extends Control:
	var angle: float = 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.46
		var col := Color(UIKit.GOLD_DIM, 0.35)
		draw_arc(c, r, 0.0, TAU, 96, col, 1.5, true)
		draw_arc(c, r * 0.78, 0.0, TAU, 96, Color(UIKit.GOLD_DIM, 0.22), 1.0, true)
		draw_arc(c, r * 1.08, 0.0, TAU, 96, Color(UIKit.GOLD_DIM, 0.15), 1.0, true)
		for i in 32:
			var a: float = angle + TAU * float(i) / 32.0
			var len_: float = r * (1.0 if i % 8 == 0 else (0.88 if i % 4 == 0 else 0.8))
			draw_line(c + Vector2(cos(a), sin(a)) * r * 0.78, c + Vector2(cos(a), sin(a)) * len_, col, 1.0)
		for i in 4:
			var a2: float = angle + TAU * float(i) / 4.0
			var tip := c + Vector2(cos(a2), sin(a2)) * r * 0.74
			var l := c + Vector2(cos(a2 + 0.22), sin(a2 + 0.22)) * r * 0.16
			var rr := c + Vector2(cos(a2 - 0.22), sin(a2 - 0.22)) * r * 0.16
			draw_colored_polygon(PackedVector2Array([tip, l, rr]), Color(UIKit.GOLD_DIM, 0.28))


class Veil extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.045))
		# vinheta: bordas mais escuras
		var w := size.x
		var h := size.y
		var edge := Color(0, 0, 0, 0.75)
		var none := Color(0, 0, 0, 0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.3), Vector2(0, h * 0.3)]), PackedColorArray([edge, edge, none, none]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.7), Vector2(w, h * 0.7), Vector2(w, h), Vector2(0, h)]), PackedColorArray([none, none, edge, edge]))


func _ready() -> void:
	layer = 60
	var theme := UIKit.make_theme()
	_root = Control.new()
	_root.theme = theme
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var veil := Veil.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(veil)

	_rose = Rose.new()
	_rose.set_anchors_preset(Control.PRESET_CENTER)
	_rose.custom_minimum_size = Vector2(760, 760)
	_rose.size = Vector2(760, 760)
	_rose.position = -_rose.size * 0.5
	_rose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rose)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.custom_minimum_size = Vector2(760, 0)
	col.position = Vector2(-380, -190)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	var crest := UiIcon.make("crown", 64.0, UIKit.GOLD_BRIGHT)
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(crest)
	var t := UIKit.serif_label("GEOEMPIRE", 84, UIKit.GOLD_BRIGHT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	t.add_theme_constant_override("shadow_offset_y", 5)
	col.add_child(t)
	var rule := CountrySelect.TitleRule.new()
	rule.custom_minimum_size = Vector2(0, 20)
	col.add_child(rule)
	var s := UIKit.label("GRANDE ESTRATÉGIA  ·  1836 — 2012", 20, UIKit.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)

	# rodapé: dica, barra e estado
	var foot := VBoxContainer.new()
	foot.anchor_left = 0.0
	foot.anchor_right = 1.0
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 80
	foot.offset_right = -80
	foot.offset_top = -190
	foot.offset_bottom = -34
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(foot)
	_tip = UIKit.serif_label(TIPS[randi() % TIPS.size()], 21, Color(UIKit.TEXT, 0.85))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.add_child(_tip)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(UIKit.GOLD_DIM, 0.35)
	_bar_back.custom_minimum_size = Vector2(0, 4)
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(_bar_back)
	_bar_fill = ColorRect.new()
	_bar_fill.color = UIKit.GOLD_BRIGHT
	_bar_fill.size = Vector2(0, 4)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar_fill)
	_status = UIKit.label("Iniciando…", 16, UIKit.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(_status)
	_prompt = UIKit.label("Toque para começar", 24, UIKit.GOLD_BRIGHT)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.modulate.a = 0.0
	foot.add_child(_prompt)

	var ver := UIKit.label("v0.12 · Alpha", 14, UIKit.TEXT_DIM)
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = -160
	ver.offset_top = -30
	ver.offset_right = -16
	ver.offset_bottom = -6
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(ver)

	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.7)


## Progresso real do carregamento (0..1) e texto de estado.
func set_progress(p: float, text: String) -> void:
	_progress = clampf(p, 0.0, 1.0)
	if _status != null:
		_status.text = text


## Chamado quando o carregamento termina: habilita o toque (após o tempo mínimo de exibição).
func set_loaded() -> void:
	_progress = 1.0
	_ready_to_go = true
	_status.text = "Pronto"


func _process(delta: float) -> void:
	_t += delta
	if _rose != null:
		(_rose as Rose).angle += delta * 0.05
		_rose.queue_redraw()
	_shown = move_toward(_shown, _progress, delta * 0.9)
	if _bar_fill != null:
		_bar_fill.size = Vector2(_bar_back.size.x * _shown, 4.0)
	if _ready_to_go and _t >= MIN_SECS and _shown >= 0.999:
		_prompt.modulate.a = 0.55 + 0.45 * sin(_t * 3.0)
	if int(_t / 3.5) != int((_t - delta) / 3.5) and not _ready_to_go:
		_tip.text = TIPS[randi() % TIPS.size()]


func _input(event: InputEvent) -> void:
	if _closing or not _ready_to_go or _t < MIN_SECS or _shown < 0.999:
		return
	var go := false
	if event is InputEventScreenTouch and event.pressed:
		go = true
	elif event is InputEventMouseButton and event.pressed:
		go = true
	elif event is InputEventKey and event.pressed:
		go = true
	if go:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	_closing = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func():
		finished.emit()
		queue_free())

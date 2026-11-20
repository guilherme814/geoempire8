class_name FlagRect
extends Control
## Controle que desenha a bandeira de um país (ver Flag).
## Com `waving = true` a bandeira ondula: ela é desenhada uma vez numa textura pequena e depois
## fatiada em colunas que sobem e descem com uma onda senoidal e variação de brilho (efeito de pano).
## Leve: ~28 colunas, redesenho a 30 quadros por segundo, só enquanto está visível.

const SLICES := 28
const TEX_SIZE := Vector2i(224, 144)
const WAVE_SPEED := 2.4
const WAVE_LENGTH := 5.2
const FRAME_STEP := 1.0 / 30.0

var tag: String = ""
var fallback: Color = Color.GRAY
var waving: bool = false

var _vp: SubViewport
var _src: _FlagSource
var _t: float = 0.0
var _acc: float = 0.0


## Fonte da textura: desenha a bandeira reta dentro da SubViewport.
class _FlagSource extends Control:
	var tag: String = ""
	var fallback: Color = Color.GRAY

	func _draw() -> void:
		Flag.draw(self, Rect2(Vector2.ZERO, size), tag, fallback)


func set_country(t: String, c: Color) -> void:
	tag = t
	fallback = c
	if waving:
		_ensure_source()
		_src.tag = t
		_src.fallback = c
		_src.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		set_process(true)
	queue_redraw()


func _ensure_source() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.size = TEX_SIZE
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_src = _FlagSource.new()
	_src.size = Vector2(TEX_SIZE)
	_vp.add_child(_src)


func _process(delta: float) -> void:
	if not waving or not is_visible_in_tree():
		return
	_t += delta
	_acc += delta
	if _acc >= FRAME_STEP:
		_acc = 0.0
		queue_redraw()


func _draw() -> void:
	if not waving or _vp == null:
		Flag.draw(self, Rect2(Vector2.ZERO, size), tag, fallback)
		return
	var tex: Texture2D = _vp.get_texture()
	var amp: float = size.y * 0.075
	var pole: float = maxf(3.0, size.x * 0.035)
	var r := Rect2(pole, amp, size.x - pole, size.y - 2.0 * amp)
	for i in SLICES:
		var u0: float = float(i) / SLICES
		var phase: float = _t * WAVE_SPEED - u0 * WAVE_LENGTH
		var grow: float = 0.18 + 0.82 * u0                 # preso ao mastro, solto na ponta
		var dy: float = sin(phase) * amp * grow
		var shade: float = clampf(1.0 + 0.17 * cos(phase) * grow, 0.8, 1.14)
		var x0: float = r.position.x + u0 * r.size.x
		var w: float = r.size.x / SLICES + 0.8
		var src := Rect2(u0 * TEX_SIZE.x, 0.0, float(TEX_SIZE.x) / SLICES + 1.0, TEX_SIZE.y)
		draw_texture_rect_region(tex, Rect2(x0, r.position.y + dy, w, r.size.y), src, Color(shade, shade, shade, 1.0))
	draw_rect(Rect2(0, 0, pole, size.y), Color(0.96, 0.85, 0.55))        # mastro dourado
	draw_circle(Vector2(pole * 0.5, 1.5), pole * 0.9, Color(1.0, 0.92, 0.62))

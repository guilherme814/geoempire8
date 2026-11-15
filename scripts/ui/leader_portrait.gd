class_name LeaderPortrait
extends Control
## Retrato de governante desenhado em código (arte vetorial original, sem fotos): moldura dourada,
## ombros com a indumentária do país, rosto, cabelo, barba e chapéu/coroa conforme os dados.

const SKIN := {
	"light": Color(0.94, 0.78, 0.66), "tan": Color(0.83, 0.63, 0.46), "brown": Color(0.66, 0.46, 0.31),
	"dark": Color(0.43, 0.29, 0.21), "east": Color(0.91, 0.75, 0.52),
}
const HAIR := {
	"b": Color(0.33, 0.20, 0.12), "k": Color(0.08, 0.07, 0.07), "g": Color(0.62, 0.62, 0.64),
	"w": Color(0.93, 0.93, 0.95), "r": Color(0.60, 0.25, 0.10), "y": Color(0.86, 0.71, 0.36),
}
const GOLD := Color(0.86, 0.70, 0.30)
const ASPECT := 1.25

var _tint: Color = Color(0.3, 0.3, 0.4)
var _skin_key: String = "light"
var _garb: String = "uniform"
var _e: Dictionary = {}
var _empty: bool = true

var _s: float = 1.0


static func make(width: float, country_color: Color, country_info: Dictionary, entry: Dictionary) -> LeaderPortrait:
	var p := LeaderPortrait.new()
	p.custom_minimum_size = Vector2(width, width * ASPECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.setup(country_color, country_info, entry)
	return p


func setup(country_color: Color, country_info: Dictionary, entry: Dictionary) -> void:
	_tint = country_color
	_skin_key = str(country_info.get("skin", "light"))
	_garb = str(entry.get("garb", country_info.get("garb", "uniform")))
	_e = entry
	_empty = entry.is_empty()
	queue_redraw()


func _p(x: float, y: float) -> Vector2:
	return Vector2(x, y) * _s


func _poly(pts: Array, col: Color) -> void:
	var v := PackedVector2Array()
	for q in pts:
		var pt: Vector2 = q
		v.append(pt * _s)
	if v.size() < 3:
		return
	if Geometry2D.triangulate_polygon(v).is_empty():
		# polígono degenerado: usa o casco convexo em vez de perder a peça
		v = Geometry2D.convex_hull(v)
		if v.size() > 1 and v[0] == v[v.size() - 1]:
			v.remove_at(v.size() - 1)
		if v.size() < 3:
			return
	draw_colored_polygon(v, col)


func _ell(c: Vector2, rx: float, ry: float, col: Color, from_a: float = 0.0, to_a: float = TAU) -> void:
	var pts: Array = []
	var n: int = 28
	for i in n + 1:
		var a: float = from_a + (to_a - from_a) * float(i) / float(n)
		pts.append(Vector2(c.x + cos(a) * rx, c.y + sin(a) * ry))
	_poly(pts, col)


func _ln(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(a * _s, b * _s, col, maxf(1.0, w * _s), true)


func _draw() -> void:
	_s = size.x
	if _s <= 0.0:
		return
	var h: float = ASPECT
	# fundo: tom do país escurecido com um halo
	draw_rect(Rect2(Vector2.ZERO, Vector2(_s, h * _s)), _tint.darkened(0.62))
	_ell(Vector2(0.5, 0.52), 0.52, 0.56, Color(_tint.lightened(0.15), 0.35))
	_ell(Vector2(0.5, 0.52), 0.36, 0.40, Color(_tint.lightened(0.35), 0.22))
	if _empty:
		draw_rect(Rect2(Vector2.ZERO, Vector2(_s, h * _s)), GOLD, false, maxf(2.0, 0.025 * _s))
		return
	var skin: Color = SKIN.get(_skin_key, SKIN["light"])
	var hair: Color = HAIR.get(str(_e.get("hair", "b")), HAIR["b"])
	var beard: String = str(_e.get("beard", "none"))
	var hat: String = str(_e.get("hat", "none"))
	var female: bool = beard == "f"

	if female:   # cabelo comprido atrás dos ombros
		_poly([Vector2(0.30, 0.45), Vector2(0.26, 0.75), Vector2(0.24, 1.02), Vector2(0.40, 0.95), Vector2(0.60, 0.95),
			Vector2(0.76, 1.02), Vector2(0.74, 0.75), Vector2(0.70, 0.45)], hair)
	_draw_garb(skin)
	# pescoço
	_poly([Vector2(0.43, 0.76), Vector2(0.57, 0.76), Vector2(0.58, 0.92), Vector2(0.42, 0.92)], skin.darkened(0.15))
	if _garb == "uniform" or _garb == "robe":
		_poly([Vector2(0.40, 0.88), Vector2(0.60, 0.88), Vector2(0.62, 0.95), Vector2(0.38, 0.95)], Color(0.95, 0.94, 0.9))
	# orelhas e cabeça
	_ell(Vector2(0.325, 0.57), 0.032, 0.05, skin.darkened(0.08))
	_ell(Vector2(0.675, 0.57), 0.032, 0.05, skin.darkened(0.08))
	_ell(Vector2(0.5, 0.55), 0.175, 0.225, skin)
	# sombra suave sob o queixo
	_ell(Vector2(0.5, 0.74), 0.12, 0.03, Color(skin.darkened(0.25), 0.5))
	_draw_hair(hair, female)
	_draw_face(skin, hair, beard, female)
	_draw_hat(hat, hair)
	draw_rect(Rect2(Vector2.ZERO, Vector2(_s, h * _s)), GOLD, false, maxf(2.0, 0.028 * _s))
	draw_rect(Rect2(Vector2(0.03, 0.03) * _s, Vector2(0.94, h - 0.06) * _s), Color(GOLD, 0.35), false, maxf(1.0, 0.008 * _s))


func _draw_garb(skin: Color) -> void:
	var sh: Array = [Vector2(0.04, 1.25), Vector2(0.08, 1.04), Vector2(0.24, 0.94), Vector2(0.40, 0.89),
		Vector2(0.60, 0.89), Vector2(0.76, 0.94), Vector2(0.92, 1.04), Vector2(0.96, 1.25)]
	match _garb:
		"suit":
			_poly(sh, Color(0.09, 0.09, 0.12))
			_poly([Vector2(0.42, 0.9), Vector2(0.58, 0.9), Vector2(0.5, 1.12)], Color(0.95, 0.95, 0.93))
			_poly([Vector2(0.46, 0.96), Vector2(0.54, 0.96), Vector2(0.53, 1.14), Vector2(0.5, 1.18), Vector2(0.47, 1.14)], Color(0.55, 0.1, 0.12))
			_poly([Vector2(0.40, 0.89), Vector2(0.46, 0.93), Vector2(0.44, 1.16), Vector2(0.34, 1.25), Vector2(0.28, 1.0)], Color(0.14, 0.14, 0.18))
			_poly([Vector2(0.60, 0.89), Vector2(0.54, 0.93), Vector2(0.56, 1.16), Vector2(0.66, 1.25), Vector2(0.72, 1.0)], Color(0.14, 0.14, 0.18))
		"qing":
			_poly(sh, Color(0.12, 0.26, 0.42))
			_ell(Vector2(0.5, 1.07), 0.075, 0.075, GOLD)
			_ell(Vector2(0.5, 1.07), 0.045, 0.045, Color(0.7, 0.15, 0.12))
			_ell(Vector2(0.5, 0.9), 0.12, 0.05, Color(0.75, 0.2, 0.15))
			_ell(Vector2(0.5, 0.9), 0.085, 0.034, skin.darkened(0.15))
		"kimono":
			_poly(sh, Color(0.12, 0.12, 0.2))
			_poly([Vector2(0.40, 0.89), Vector2(0.60, 0.89), Vector2(0.5, 1.15)], Color(0.94, 0.93, 0.88))
			_poly([Vector2(0.40, 0.89), Vector2(0.44, 0.89), Vector2(0.58, 1.2), Vector2(0.54, 1.2)], Color(0.7, 0.18, 0.16))
			_ell(Vector2(0.24, 1.12), 0.04, 0.04, GOLD)
			_ell(Vector2(0.76, 1.12), 0.04, 0.04, GOLD)
		"arab":
			_poly(sh, Color(0.93, 0.91, 0.85))
			_poly([Vector2(0.04, 1.25), Vector2(0.08, 1.04), Vector2(0.24, 0.96), Vector2(0.34, 1.25)], Color(0.32, 0.22, 0.14))
			_poly([Vector2(0.96, 1.25), Vector2(0.92, 1.04), Vector2(0.76, 0.96), Vector2(0.66, 1.25)], Color(0.32, 0.22, 0.14))
			_poly([Vector2(0.40, 0.89), Vector2(0.60, 0.89), Vector2(0.5, 1.08)], Color(0.82, 0.78, 0.7))
		"african":
			_poly(sh, skin.darkened(0.05))
			_poly([Vector2(0.04, 1.25), Vector2(0.08, 1.04), Vector2(0.30, 0.98), Vector2(0.45, 1.25)], Color(0.7, 0.14, 0.12))
			for i in 9:
				var a: float = PI * (0.1 + 0.8 * float(i) / 8.0)
				_ell(Vector2(0.5 + cos(a) * 0.17, 0.89 + sin(a) * 0.1), 0.017, 0.017, Color(0.92, 0.82, 0.5) if i % 2 == 0 else Color(0.8, 0.2, 0.15))
		"robe":
			var c: Color = _tint.lightened(0.05)
			_poly(sh, c)
			_poly([Vector2(0.40, 0.89), Vector2(0.36, 1.25), Vector2(0.43, 1.25), Vector2(0.45, 0.93)], GOLD)
			_poly([Vector2(0.60, 0.89), Vector2(0.64, 1.25), Vector2(0.57, 1.25), Vector2(0.55, 0.93)], GOLD)
			_poly([Vector2(0.08, 1.04), Vector2(0.24, 0.94), Vector2(0.30, 0.97), Vector2(0.12, 1.1)], Color(GOLD, 0.8))
			_poly([Vector2(0.92, 1.04), Vector2(0.76, 0.94), Vector2(0.70, 0.97), Vector2(0.88, 1.1)], Color(GOLD, 0.8))
		_:   # uniform
			var c2: Color = _tint.darkened(0.32)
			_poly(sh, c2)
			_poly([Vector2(0.40, 0.89), Vector2(0.60, 0.89), Vector2(0.5, 1.2)], c2.lightened(0.12))
			_poly([Vector2(0.36, 0.9), Vector2(0.64, 0.9), Vector2(0.62, 0.96), Vector2(0.38, 0.96)], GOLD)
			# faixa em diagonal e condecorações
			_poly([Vector2(0.18, 1.0), Vector2(0.26, 0.97), Vector2(0.82, 1.25), Vector2(0.66, 1.25)], Color(0.82, 0.76, 0.6, 0.85))
			_poly([Vector2(0.14, 0.99), Vector2(0.30, 0.93), Vector2(0.36, 0.99), Vector2(0.20, 1.07)], GOLD)   # dragona
			_poly([Vector2(0.86, 0.99), Vector2(0.70, 0.93), Vector2(0.64, 0.99), Vector2(0.80, 1.07)], GOLD)
			_ell(Vector2(0.62, 1.12), 0.028, 0.028, GOLD)
			_ell(Vector2(0.70, 1.17), 0.022, 0.022, Color(0.8, 0.2, 0.2))
			for i in 3:
				_ell(Vector2(0.5, 1.02 + 0.07 * float(i)), 0.014, 0.014, GOLD)


func _draw_hair(hair: Color, female: bool) -> void:
	var bald: bool = str(_e.get("hair", "b")) == "n"
	if bald:
		_ell(Vector2(0.345, 0.50), 0.03, 0.05, hair)
		_ell(Vector2(0.655, 0.50), 0.03, 0.05, hair)
		return
	var pts: Array = []
	for i in 21:   # arco superior da cabeça
		var a: float = PI + PI * float(i) / 20.0
		pts.append(Vector2(0.5 + cos(a) * 0.19, 0.50 + sin(a) * 0.255))
	pts.append(Vector2(0.69, 0.55))
	pts.append(Vector2(0.64, 0.42))
	pts.append(Vector2(0.58, 0.385))
	pts.append(Vector2(0.50, 0.40))
	pts.append(Vector2(0.42, 0.385))
	pts.append(Vector2(0.36, 0.42))
	pts.append(Vector2(0.31, 0.55))
	_poly(pts, hair)
	if female:
		_poly([Vector2(0.31, 0.5), Vector2(0.30, 0.72), Vector2(0.35, 0.60)], hair)
		_poly([Vector2(0.69, 0.5), Vector2(0.70, 0.72), Vector2(0.65, 0.60)], hair)
	_ln(Vector2(0.45, 0.35), Vector2(0.5, 0.40), 0.008, Color(hair.lightened(0.2), 0.6))


func _draw_face(skin: Color, hair: Color, beard: String, female: bool) -> void:
	var east: bool = _skin_key == "east"
	var ink := Color(0.12, 0.08, 0.07)
	# barba (atrás de boca/nariz)
	match beard:
		"chops":
			_poly([Vector2(0.325, 0.50), Vector2(0.36, 0.52), Vector2(0.37, 0.66), Vector2(0.42, 0.74), Vector2(0.36, 0.72), Vector2(0.325, 0.62)], hair)
			_poly([Vector2(0.675, 0.50), Vector2(0.64, 0.52), Vector2(0.63, 0.66), Vector2(0.58, 0.74), Vector2(0.64, 0.72), Vector2(0.675, 0.62)], hair)
		"full", "long":
			var bot: float = 0.93 if beard == "long" else 0.80
			_poly([Vector2(0.325, 0.52), Vector2(0.37, 0.60), Vector2(0.40, 0.64), Vector2(0.5, 0.63), Vector2(0.60, 0.64), Vector2(0.63, 0.60),
				Vector2(0.675, 0.52), Vector2(0.68, 0.66), Vector2(0.62, bot - 0.05), Vector2(0.5, bot), Vector2(0.38, bot - 0.05), Vector2(0.32, 0.66)], hair)
			_ell(Vector2(0.5, 0.675), 0.055, 0.022, skin.darkened(0.3))   # abertura da boca
		"goatee":
			_poly([Vector2(0.45, 0.72), Vector2(0.55, 0.72), Vector2(0.53, 0.82), Vector2(0.5, 0.85), Vector2(0.47, 0.82)], hair)
	# olhos
	var ey: float = 0.545
	var eh: float = 0.014 if east else 0.022
	for sx in [0.425, 0.575]:
		_ell(Vector2(sx, ey), 0.032, eh + 0.006, Color(0.97, 0.97, 0.95))
		_ell(Vector2(sx, ey), 0.014, eh, ink)
		_ln(Vector2(sx - 0.04, ey - 0.038), Vector2(sx + 0.04, ey - 0.046 + (0.012 if sx < 0.5 else -0.0)), 0.012, hair.darkened(0.2) if str(_e.get("hair", "b")) != "n" else skin.darkened(0.35))
	# nariz
	_ln(Vector2(0.5, 0.56), Vector2(0.485, 0.64), 0.008, skin.darkened(0.3))
	_ln(Vector2(0.485, 0.64), Vector2(0.515, 0.645), 0.008, skin.darkened(0.3))
	# bigode e boca
	if beard == "stache" or beard == "goatee" or beard == "full" or beard == "long":
		_poly([Vector2(0.43, 0.655), Vector2(0.5, 0.645), Vector2(0.57, 0.655), Vector2(0.60, 0.69), Vector2(0.5, 0.675), Vector2(0.40, 0.69)], hair)
	if female:
		_ln(Vector2(0.45, 0.69), Vector2(0.55, 0.69), 0.016, Color(0.72, 0.2, 0.25))
	else:
		_ln(Vector2(0.455, 0.70), Vector2(0.545, 0.70), 0.009, skin.darkened(0.5))
	# rugas leves em quem tem cabelo branco/grisalho
	var hc: String = str(_e.get("hair", "b"))
	if hc == "w" or hc == "g":
		_ln(Vector2(0.41, 0.44), Vector2(0.59, 0.44), 0.005, Color(skin.darkened(0.25), 0.6))
		_ln(Vector2(0.43, 0.47), Vector2(0.57, 0.47), 0.004, Color(skin.darkened(0.25), 0.4))


func _draw_hat(hat: String, hair: Color) -> void:
	match hat:
		"crown":
			_poly([Vector2(0.34, 0.37), Vector2(0.33, 0.20), Vector2(0.41, 0.28), Vector2(0.5, 0.14), Vector2(0.59, 0.28), Vector2(0.67, 0.20), Vector2(0.66, 0.37)], GOLD)
			_poly([Vector2(0.34, 0.37), Vector2(0.66, 0.37), Vector2(0.66, 0.325), Vector2(0.34, 0.325)], Color(0.72, 0.14, 0.18))
			_ell(Vector2(0.5, 0.28), 0.018, 0.018, Color(0.3, 0.7, 0.9))
			_ell(Vector2(0.33, 0.19), 0.014, 0.014, Color(0.95, 0.95, 0.95))
			_ell(Vector2(0.67, 0.19), 0.014, 0.014, Color(0.95, 0.95, 0.95))
			_ell(Vector2(0.5, 0.13), 0.016, 0.016, Color(0.95, 0.95, 0.95))
		"tiara":
			_poly([Vector2(0.38, 0.39), Vector2(0.41, 0.30), Vector2(0.45, 0.34), Vector2(0.5, 0.25), Vector2(0.55, 0.34), Vector2(0.59, 0.30), Vector2(0.62, 0.39), Vector2(0.58, 0.385), Vector2(0.5, 0.35), Vector2(0.42, 0.385)], GOLD)
			_ell(Vector2(0.5, 0.29), 0.015, 0.015, Color(0.35, 0.75, 0.95))
		"bicorne":
			_poly([Vector2(0.14, 0.42), Vector2(0.28, 0.27), Vector2(0.5, 0.20), Vector2(0.72, 0.27), Vector2(0.86, 0.42), Vector2(0.72, 0.35), Vector2(0.5, 0.31), Vector2(0.28, 0.35)], Color(0.08, 0.08, 0.1))
			_poly([Vector2(0.14, 0.42), Vector2(0.17, 0.40), Vector2(0.30, 0.30), Vector2(0.28, 0.27)], GOLD)
			_poly([Vector2(0.86, 0.42), Vector2(0.83, 0.40), Vector2(0.70, 0.30), Vector2(0.72, 0.27)], GOLD)
			_ell(Vector2(0.5, 0.30), 0.02, 0.02, Color(0.8, 0.15, 0.15))
		"tophat":
			_poly([Vector2(0.37, 0.36), Vector2(0.38, 0.10), Vector2(0.62, 0.10), Vector2(0.63, 0.36)], Color(0.07, 0.07, 0.09))
			_poly([Vector2(0.27, 0.38), Vector2(0.73, 0.38), Vector2(0.70, 0.33), Vector2(0.30, 0.33)], Color(0.07, 0.07, 0.09))
			_poly([Vector2(0.375, 0.33), Vector2(0.625, 0.33), Vector2(0.626, 0.29), Vector2(0.374, 0.29)], Color(0.55, 0.1, 0.12))
		"turban":
			_ell(Vector2(0.5, 0.32), 0.235, 0.14, Color(0.94, 0.91, 0.84))
			_ell(Vector2(0.5, 0.25), 0.15, 0.09, Color(0.88, 0.84, 0.76))
			_ln(Vector2(0.30, 0.34), Vector2(0.62, 0.20), 0.014, Color(0.78, 0.74, 0.66))
			_ln(Vector2(0.28, 0.30), Vector2(0.56, 0.18), 0.012, Color(0.78, 0.74, 0.66))
			_ln(Vector2(0.38, 0.40), Vector2(0.72, 0.28), 0.014, Color(0.78, 0.74, 0.66))
			_ell(Vector2(0.5, 0.31), 0.022, 0.022, Color(0.75, 0.15, 0.2))
			_ell(Vector2(0.5, 0.31), 0.012, 0.012, GOLD)
		"fez":
			_poly([Vector2(0.37, 0.37), Vector2(0.41, 0.17), Vector2(0.59, 0.17), Vector2(0.63, 0.37)], Color(0.72, 0.12, 0.12))
			_ell(Vector2(0.5, 0.17), 0.09, 0.02, Color(0.6, 0.08, 0.08))
			_ln(Vector2(0.5, 0.17), Vector2(0.66, 0.30), 0.012, Color(0.1, 0.1, 0.1))
			_ell(Vector2(0.66, 0.31), 0.016, 0.02, Color(0.1, 0.1, 0.1))
		"qing":
			_poly([Vector2(0.28, 0.38), Vector2(0.36, 0.21), Vector2(0.5, 0.14), Vector2(0.64, 0.21), Vector2(0.72, 0.38), Vector2(0.5, 0.33)], Color(0.1, 0.1, 0.13))
			_poly([Vector2(0.28, 0.38), Vector2(0.72, 0.38), Vector2(0.69, 0.345), Vector2(0.31, 0.345)], Color(0.7, 0.12, 0.12))
			_ell(Vector2(0.5, 0.14), 0.022, 0.022, Color(0.75, 0.15, 0.15))
			_ell(Vector2(0.5, 0.14), 0.01, 0.01, GOLD)
			for i in 7:
				_ln(Vector2(0.5, 0.15), Vector2(0.36 + 0.047 * float(i), 0.33), 0.006, Color(0.75, 0.15, 0.15, 0.9))
		"eboshi":
			_poly([Vector2(0.37, 0.38), Vector2(0.39, 0.20), Vector2(0.46, 0.11), Vector2(0.58, 0.13), Vector2(0.62, 0.22), Vector2(0.63, 0.38)], Color(0.07, 0.07, 0.09))
			_ln(Vector2(0.41, 0.34), Vector2(0.59, 0.34), 0.012, Color(0.55, 0.1, 0.12))
		"gat":
			_ell(Vector2(0.5, 0.35), 0.255, 0.05, Color(0.1, 0.1, 0.12))
			_poly([Vector2(0.40, 0.35), Vector2(0.41, 0.14), Vector2(0.59, 0.14), Vector2(0.60, 0.35)], Color(0.12, 0.12, 0.14))
			_ell(Vector2(0.5, 0.14), 0.095, 0.022, Color(0.2, 0.2, 0.24))
		"mitre":
			_poly([Vector2(0.34, 0.38), Vector2(0.38, 0.12), Vector2(0.5, 0.2), Vector2(0.62, 0.12), Vector2(0.66, 0.38)], Color(0.95, 0.93, 0.88))
			_poly([Vector2(0.34, 0.38), Vector2(0.66, 0.38), Vector2(0.655, 0.34), Vector2(0.345, 0.34)], GOLD)
			_ln(Vector2(0.5, 0.2), Vector2(0.5, 0.35), 0.016, GOLD)
			_ln(Vector2(0.45, 0.27), Vector2(0.55, 0.27), 0.012, GOLD)
		"ghutra":
			_poly([Vector2(0.26, 0.74), Vector2(0.27, 0.40), Vector2(0.34, 0.26), Vector2(0.5, 0.20), Vector2(0.66, 0.26), Vector2(0.73, 0.40), Vector2(0.74, 0.74), Vector2(0.66, 0.78), Vector2(0.69, 0.45), Vector2(0.62, 0.36), Vector2(0.5, 0.34), Vector2(0.38, 0.36), Vector2(0.31, 0.45), Vector2(0.34, 0.78)], Color(0.95, 0.94, 0.9))
			_ell(Vector2(0.5, 0.33), 0.16, 0.035, Color(0.1, 0.1, 0.1), PI, TAU)
			_ln(Vector2(0.34, 0.34), Vector2(0.66, 0.34), 0.016, Color(0.1, 0.1, 0.1))
		"helmet":
			_ell(Vector2(0.5, 0.36), 0.19, 0.19, Color(0.18, 0.18, 0.22), PI, TAU)
			_poly([Vector2(0.30, 0.37), Vector2(0.70, 0.37), Vector2(0.73, 0.40), Vector2(0.27, 0.40)], Color(0.1, 0.1, 0.12))
			_poly([Vector2(0.48, 0.19), Vector2(0.52, 0.19), Vector2(0.515, 0.08), Vector2(0.485, 0.08)], GOLD)
			_ell(Vector2(0.5, 0.29), 0.025, 0.025, GOLD)
		"kepi":
			_poly([Vector2(0.33, 0.39), Vector2(0.35, 0.24), Vector2(0.62, 0.22), Vector2(0.67, 0.39)], _tint.darkened(0.2))
			_poly([Vector2(0.30, 0.40), Vector2(0.70, 0.40), Vector2(0.72, 0.43), Vector2(0.28, 0.43)], Color(0.07, 0.07, 0.09))
			_poly([Vector2(0.34, 0.375), Vector2(0.66, 0.375), Vector2(0.66, 0.34), Vector2(0.34, 0.34)], GOLD)
		"papakha":
			_ell(Vector2(0.5, 0.31), 0.22, 0.13, Color(0.25, 0.17, 0.11))
			_ell(Vector2(0.5, 0.26), 0.17, 0.08, Color(0.33, 0.23, 0.15))
			_ell(Vector2(0.5, 0.40), 0.18, 0.02, Color(0.2, 0.14, 0.09))
		"laurel":
			for i in 7:
				var t: float = float(i) / 6.0
				_ell(Vector2(0.33 + 0.07 * t, 0.46 - 0.12 * t), 0.02, 0.012, Color(0.3, 0.55, 0.25))
				_ell(Vector2(0.67 - 0.07 * t, 0.46 - 0.12 * t), 0.02, 0.012, Color(0.3, 0.55, 0.25))
		_:
			pass

class_name AppSettings
extends RefCounted
## Preferências leves do aparelho (user://settings.cfg): marcadores de onboarding etc.
## Nunca entra no save da campanha nem na simulação.

const PATH := "user://settings.cfg"


static func get_flag(section: String, key: String, default_value: bool = false) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return default_value
	return bool(cfg.get_value(section, key, default_value))


static func get_int(section: String, key: String, default_value: int = 0) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return default_value
	return int(cfg.get_value(section, key, default_value))


static func set_int(section: String, key: String, value: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(section, key, value)
	cfg.save(PATH)


## Qualidade gráfica do mapa: 0 baixa, 1 média (padrão), 2 alta. Fica em cache: é lida a cada desenho.
const GFX_NAMES := ["Baixa", "Média", "Alta"]
static var _gfx_cache := -1


static func gfx_quality() -> int:
	if _gfx_cache < 0:
		_gfx_cache = clampi(get_int("graficos", "qualidade", 1), 0, 2)
	return _gfx_cache


static func set_gfx_quality(q: int) -> void:
	_gfx_cache = clampi(q, 0, 2)
	set_int("graficos", "qualidade", _gfx_cache)


static func set_flag(section: String, key: String, value: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # se não existir, começa vazio
	cfg.set_value(section, key, value)
	cfg.save(PATH)

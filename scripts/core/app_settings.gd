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


static func set_flag(section: String, key: String, value: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # se não existir, começa vazio
	cfg.set_value(section, key, value)
	cfg.save(PATH)

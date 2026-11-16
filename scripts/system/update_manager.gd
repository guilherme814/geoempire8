extends Node
## Autoload UpdateManager: versão instalada, changelog offline (data/changelog_fallback.json),
## cache da última release do GitHub e consulta assíncrona e opcional. Nunca bloqueia o boot e
## nunca instala nada: só informa e abre a página oficial quando o jogador pede.

signal update_check_completed(has_new_remote_version: bool, release_info: Dictionary)
signal app_just_updated(new_version: String, changelog_text: String)

const API_URL := "https://api.github.com/repos/guilherme814/geoempire8/releases/latest"
const STATE_PATH := "user://version_state.cfg"
const CACHE_PATH := "user://cached_release.json"
const FALLBACK_PATH := "res://data/changelog_fallback.json"
const CHECK_INTERVAL_SECS := 6 * 3600

var current_version: String = "0.0.0"
var latest_release: Dictionary = {}    # o que o modal mostra: cache/embutido
var history: Array = []                # versões embutidas (mais novas primeiro)
var has_remote_update: bool = false
var just_updated: bool = false
var _http: HTTPRequest


func _ready() -> void:
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_load_fallback()
	_load_cache()
	_check_if_app_was_updated()
	if DisplayServer.get_name() == "headless":
		return   # CI/testes: sem rede
	call_deferred("check_github_releases")


func _load_fallback() -> void:
	latest_release = {"version": current_version, "title": "GeoEmpire 8 — v" + current_version, "body": "Melhorias gerais de estabilidade e desempenho."}
	if not FileAccess.file_exists(FALLBACK_PATH):
		return
	var f := FileAccess.open(FALLBACK_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var d: Dictionary = parsed
		var clean := UpdateRules.clean_payload(d)
		if not clean.is_empty():
			latest_release = clean
		var h: Variant = d.get("history", [])
		if h is Array:
			for e in h:
				if e is Dictionary:
					var ce := UpdateRules.clean_payload(e)
					if not ce.is_empty():
						history.append(ce)


## Se há cache do GitHub mais novo que a build, ele passa a ser o destaque do modal.
func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var f := FileAccess.open(CACHE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		var clean := UpdateRules.clean_payload(parsed)
		if not clean.is_empty() and UpdateRules.is_newer(str(clean["version"]), current_version):
			latest_release = clean
			has_remote_update = true


func _check_if_app_was_updated() -> void:
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	var last: String = str(cfg.get_value("version", "last_installed", ""))
	if last != current_version:
		cfg.set_value("version", "last_installed", current_version)
		cfg.save(STATE_PATH)
		if last != "":   # primeira instalação não é "atualização": quem recebe é o onboarding
			just_updated = true
			var notes := str(history[0]["body"]) if not history.is_empty() else str(latest_release.get("body", ""))
			app_just_updated.emit(current_version, notes)


## O menu chama isto ao abrir: devolve true uma vez se o jogo acabou de ser atualizado.
func consume_just_updated() -> bool:
	var v := just_updated
	just_updated = false
	return v


func current_notes() -> Dictionary:
	if not history.is_empty():
		return history[0]
	return {"version": current_version, "title": "GeoEmpire 8 — v" + current_version, "body": str(latest_release.get("body", ""))}


func check_github_releases() -> void:
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	var now: int = int(Time.get_unix_time_from_system())
	if now - int(cfg.get_value("version", "last_check", 0)) < CHECK_INTERVAL_SECS and FileAccess.file_exists(CACHE_PATH):
		update_check_completed.emit(has_remote_update, latest_release)
		return
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	_http.body_size_limit = 262144
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	if _http.request(API_URL, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: GeoEmpire8-Client"])) != OK:
		update_check_completed.emit(has_remote_update, latest_release)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _http != null:
		_http.queue_free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		update_check_completed.emit(has_remote_update, latest_release)   # 403/404/timeout: segue offline
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("tag_name"):
		update_check_completed.emit(has_remote_update, latest_release)
		return
	var d: Dictionary = parsed
	var payload := UpdateRules.clean_payload({
		"version": str(d["tag_name"]), "title": str(d.get("name", "")), "body": str(d.get("body", "")),
		"published_at": str(d.get("published_at", "")), "html_url": str(d.get("html_url", "")),
	})
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	cfg.set_value("version", "last_check", int(Time.get_unix_time_from_system()))
	cfg.save(STATE_PATH)
	if payload.is_empty():
		update_check_completed.emit(has_remote_update, latest_release)
		return
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))
	has_remote_update = UpdateRules.is_newer(str(payload["version"]), current_version)
	if has_remote_update:
		latest_release = payload
	update_check_completed.emit(has_remote_update, payload)


func open_release_page() -> void:
	var url := str(latest_release.get("html_url", ""))
	if url == "" or not UpdateRules.url_allowed(url):
		url = "https://github.com/%s/%s/releases" % [UpdateRules.ALLOWED_OWNER, UpdateRules.ALLOWED_REPO]
	OS.shell_open(url)

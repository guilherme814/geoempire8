class_name LogUploader
extends Node
## Envia o relatório de sessão para um repositório do GitHub (API de conteúdo), para que os logs
## cheguem sem o jogador precisar anexá-los. Só funciona em builds que trazem `data/log_sink.json`
## ({"repo": "dono/nome", "token": "...", "branch": "main"}), gerado pelo workflow a partir de
## segredos do GitHub; sem o arquivo, fica desligado. Nunca entra no save nem na simulação.
## Um arquivo por sessão (logs/AAAAMMDD/<sessão>_v<versão>.txt), atualizado a cada envio.

const SINK_PATH := "res://data/log_sink.json"
const SETTINGS_SECTION := "logs"
const SETTINGS_KEY := "upload_github"
const MAX_CHARS := 600000
const MIN_GAP_MS := 120000

var repo := ""
var token := ""
var branch := "main"
var configured := false
var status := "Envio pela internet: não configurado nesta versão."
var _sha := ""
var _path := ""
var _busy := false
var _pending := ""
var _last_ms := -MIN_GAP_MS
var _http: HTTPRequest


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	if FileAccess.file_exists(SINK_PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SINK_PATH))
		if d is Dictionary:
			repo = str(d.get("repo", ""))
			token = str(d.get("token", ""))
			branch = str(d.get("branch", "main"))
			configured = repo != "" and token != ""
	if configured:
		status = "Envio pela internet: pronto."


static func enabled() -> bool:
	return AppSettings.get_flag(SETTINGS_SECTION, SETTINGS_KEY, true)


static func set_enabled(on: bool) -> void:
	AppSettings.set_flag(SETTINGS_SECTION, SETTINGS_KEY, on)


## Envia o relatório. `force` ignora o intervalo mínimo (pausa, saída, botão manual).
func send(text: String, stamp: String, version: String, force: bool) -> void:
	if not configured or not enabled():
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_ms < MIN_GAP_MS:
		return
	_last_ms = now
	if _path == "":
		_path = "logs/%s/%s_v%s.txt" % [stamp.substr(0, 8), stamp, version]
	_pending = text
	if not _busy:
		_run()


func _run() -> void:
	_busy = true
	while _pending != "":
		var txt := _pending
		_pending = ""
		await _put(txt, true)
	_busy = false


func _headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer " + token, "Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28", "User-Agent: GeoEmpire8-Log", "Content-Type: application/json"])


func _url() -> String:
	return "https://api.github.com/repos/%s/contents/%s" % [repo, _path]


func _put(txt: String, retry: bool) -> void:
	var tail := txt
	if tail.length() > MAX_CHARS:
		tail = "[... início cortado ...]\n" + tail.substr(tail.length() - MAX_CHARS)
	var body := {"message": "log %s" % _path.get_file(), "content": Marshalls.utf8_to_base64(tail), "branch": branch}
	if _sha != "":
		body["sha"] = _sha
	var err := _http.request(_url(), _headers(), HTTPClient.METHOD_PUT, JSON.stringify(body))
	if err != OK:
		status = "Envio pela internet falhou (erro %d)." % err
		return
	var res: Array = await _http.request_completed
	var code := int(res[1])
	if code == 200 or code == 201:
		var j: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		if j is Dictionary and (j as Dictionary).get("content") is Dictionary:
			_sha = str((j["content"] as Dictionary).get("sha", ""))
		status = "Log enviado ao GitHub às %s." % Time.get_time_string_from_system()
		return
	if retry and (code == 409 or code == 422):
		await _fetch_sha()
		await _put(txt, false)
		return
	status = "Envio pela internet falhou (HTTP %d)." % code


func _fetch_sha() -> void:
	var err := _http.request(_url() + "?ref=" + branch, _headers(), HTTPClient.METHOD_GET)
	if err != OK:
		return
	var res: Array = await _http.request_completed
	if int(res[1]) == 200:
		var j: Variant = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		if j is Dictionary:
			_sha = str((j as Dictionary).get("sha", ""))

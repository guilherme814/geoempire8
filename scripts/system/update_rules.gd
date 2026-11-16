class_name UpdateRules
extends RefCounted
## Regras puras de validação de atualização/changelog (sem rede, sem autoload; testáveis).
## Implementa as correções do Plano Mestre: host validado por parsing (não por begins_with),
## SemVer com prerelease, limite de tamanho e BBCode do texto remoto neutralizado.

const ALLOWED_HOST := "github.com"
const ALLOWED_OWNER := "guilherme814"
const ALLOWED_REPO := "geoempire8"
const MAX_BODY := 4000
const MAX_TITLE := 120
const MAX_VERSION := 32


## "1.2.3" ou "v1.2.3-beta.1": três números e prerelease opcional.
static func is_valid_tag(tag: String) -> bool:
	var re := RegEx.new()
	re.compile("^v?[0-9]{1,5}\\.[0-9]{1,5}\\.[0-9]{1,5}(-[0-9A-Za-z.\\-]{1,16})?$")
	return re.search(tag) != null


static func normalize(tag: String) -> String:
	return tag.trim_prefix("v").trim_prefix("V")


static func _core(v: String) -> Array:
	var parts: PackedStringArray = normalize(v).split("-")[0].split(".")
	var out: Array = []
	for i in 3:
		out.append(int(parts[i]) if i < parts.size() else 0)
	return out


static func _pre(v: String) -> String:
	var n := normalize(v)
	var i := n.find("-")
	return "" if i < 0 else n.substr(i + 1)


## `remote` é mais novo que `local`? Versão final > prerelease da mesma base.
static func is_newer(remote: String, local: String) -> bool:
	var r: Array = _core(remote)
	var l: Array = _core(local)
	for i in 3:
		if int(r[i]) != int(l[i]):
			return int(r[i]) > int(l[i])
	var rp := _pre(remote)
	var lp := _pre(local)
	if rp == lp:
		return false
	if rp == "":
		return true
	if lp == "":
		return false
	return rp > lp


## URL https do repositório oficial: host exatamente github.com e caminho /dono/repo[/...].
static func url_allowed(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var rest := url.substr(8)
	var slash := rest.find("/")
	if slash < 0:
		return false
	var host := rest.substr(0, slash)
	if host != ALLOWED_HOST:
		return false
	var path := rest.substr(slash + 1)
	for sep in ["?", "#"]:
		var k := path.find(sep)
		if k >= 0:
			path = path.substr(0, k)
	var segs: PackedStringArray = path.split("/")
	return segs.size() >= 2 and segs[0] == ALLOWED_OWNER and segs[1] == ALLOWED_REPO


## Texto remoto -> BBCode seguro: escapa colchetes (sem injeção de tags), limita o tamanho e
## converte só o Markdown simples (## título, **negrito**, "- item").
static func to_bbcode(md: String) -> String:
	var t := md.substr(0, MAX_BODY).replace("\r", "")
	t = t.replace("[", "[lb]")
	var re_b := RegEx.new()
	re_b.compile("\\*\\*(.+?)\\*\\*")
	t = re_b.sub(t, "[b]$1[/b]", true)
	var re_h := RegEx.new()
	re_h.compile("(?m)^#{1,3}\\s+(.+)$")
	t = re_h.sub(t, "[color=#e6c36a][b]$1[/b][/color]", true)
	var re_li := RegEx.new()
	re_li.compile("(?m)^[-*]\\s+")
	t = re_li.sub(t, "•  ", true)
	return t


## Normaliza e valida o payload de uma release; devolve {} se inválido.
static func clean_payload(p: Dictionary) -> Dictionary:
	if not p.has("version") or not p.has("body"):
		return {}
	var ver := str(p["version"])
	if ver.length() > MAX_VERSION or not is_valid_tag(ver):
		return {}
	var url := str(p.get("html_url", ""))
	if url != "" and not url_allowed(url):
		return {}
	return {
		"version": normalize(ver),
		"title": str(p.get("title", "Versão " + ver)).substr(0, MAX_TITLE),
		"body": str(p["body"]).substr(0, MAX_BODY),
		"published_at": str(p.get("published_at", "")).substr(0, 40),
		"html_url": url,
	}

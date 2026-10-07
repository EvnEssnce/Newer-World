extends Node
## Autoload "Tuning": every gameplay number lives in res://data/*.cfg, not in code.
##
## Read a value with Tuning.get_value("movement", "player", "move_speed"), where the
## first argument is the file name without ".cfg". Files are INI-style ConfigFiles,
## so the developer can edit them by hand (comments start with ";").
##
## A launch option can override a value for one run (tests use this), e.g.
## --tune=combat/health/max=300. Pass the same overrides to the server and every
## client, or prediction will disagree with the server.

const DATA_DIR := "res://data/"

var _files: Dictionary[String, ConfigFile] = {}


func _init() -> void:
	reload()


func reload() -> void:
	_files.clear()
	for file_name in DirAccess.get_files_at(DATA_DIR):
		if file_name.get_extension() != "cfg":
			continue
		var cfg := ConfigFile.new()
		var err := cfg.load(DATA_DIR + file_name)
		if err != OK:
			push_error("Tuning: could not load %s (%s)" % [file_name, error_string(err)])
			continue
		_files[file_name.get_basename()] = cfg
	for override in LaunchArgs.get_values("tune"):
		_apply_override(override)


## "file/section/key=value". The value keeps the type of the value it replaces.
func _apply_override(override: String) -> void:
	var path := override.get_slice("=", 0).split("/")
	var raw := override.substr(override.find("=") + 1)
	if path.size() != 3 or not override.contains("="):
		push_error("Tuning: bad --tune=%s (expected file/section/key=value)" % override)
		return
	var current: Variant = get_value(path[0], path[1], path[2])
	if current == null:
		return
	var value: Variant = type_convert(str_to_var(raw), typeof(current))
	_files[path[0]].set_value(path[1], path[2], value)
	print("Tuning: %s/%s/%s = %s (launch override)" % [path[0], path[1], path[2], value])


func get_value(file: String, section: String, key: String) -> Variant:
	var cfg: ConfigFile = _files.get(file)
	if cfg == null:
		push_error("Tuning: no data file %s%s.cfg" % [DATA_DIR, file])
		return null
	if not cfg.has_section_key(section, key):
		push_error("Tuning: %s.cfg is missing [%s] %s" % [file, section, key])
		return null
	return cfg.get_value(section, key)

extends Node
## Autoload "Tuning": every gameplay number lives in res://data/*.cfg, not in code.
##
## Read a value with Tuning.get_value("movement", "player", "move_speed"), where the
## first argument is the file name without ".cfg". Files are INI-style ConfigFiles,
## so the developer can edit them by hand (comments start with ";").

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


func get_value(file: String, section: String, key: String) -> Variant:
	var cfg: ConfigFile = _files.get(file)
	if cfg == null:
		push_error("Tuning: no data file %s%s.cfg" % [DATA_DIR, file])
		return null
	if not cfg.has_section_key(section, key):
		push_error("Tuning: %s.cfg is missing [%s] %s" % [file, section, key])
		return null
	return cfg.get_value(section, key)

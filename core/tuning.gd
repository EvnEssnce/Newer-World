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
##
## Online, the server's tuning wins: it sends every file (with its overrides) to
## each client as it connects (send_to_peer), and the client replaces its own
## before the World is made (server_tuning_applied), so a client with older or
## edited data/*.cfg files still predicts exactly what the server simulates.

## Client: the server's tuning arrived and replaced this client's.
signal server_tuning_applied

const DATA_DIR := "res://data/"

## Bumped whenever the values change (reload, the server's tuning). Classes that
## cache what they read (PlayerParams, ItemDatabase, ...) rebuild when it moves.
var version := 0

var _files: Dictionary[String, ConfigFile] = {}


func _init() -> void:
	reload()


## Server: sends this process's tuning (overrides included) to a peer that just
## connected.
func send_to_peer(peer_id: int) -> void:
	var packed := pack()
	_receive_server_tuning.rpc_id(peer_id, packed.size(),
			packed.compress(FileAccess.COMPRESSION_ZSTD))


@rpc("authority", "call_remote", "reliable")
func _receive_server_tuning(size: int, compressed: PackedByteArray) -> void:
	# Bounded, so a broken packet can't ask for a huge buffer.
	if size <= 0 or size > 16 * 1024 * 1024:
		push_error("Tuning: the server's tuning has a bad size (%d)" % size)
		return
	var packed := compressed.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if not apply_packed(packed):
		push_error("Tuning: couldn't read the server's tuning (%d bytes)" % compressed.size())
		return
	if not LaunchArgs.get_values("tune").is_empty():
		print("Tuning: the server's tuning replaces this client's --tune overrides")
	print("Tuning: using the server's tuning (%d files, %d bytes compressed)" % [
			_files.size(), compressed.size()])
	server_tuning_applied.emit()


## Every file's values as bytes: {file: {section: {key: value}}} through
## var_to_bytes, so every value comes back with the same type and bits.
func pack() -> PackedByteArray:
	var all := {}
	for file: String in _files:
		var cfg := _files[file]
		var sections := {}
		for section in cfg.get_sections():
			var keys := {}
			for key in cfg.get_section_keys(section):
				keys[key] = cfg.get_value(section, key)
			sections[section] = keys
		all[file] = sections
	return var_to_bytes(all)


## Replaces every file with what pack() made (section and key order kept).
## False, changing nothing, if the bytes aren't a pack.
func apply_packed(packed: PackedByteArray) -> bool:
	var all: Variant = bytes_to_var(packed) if not packed.is_empty() else null
	if not all is Dictionary:
		return false
	var files: Dictionary[String, ConfigFile] = {}
	for file: Variant in all:
		var sections: Variant = all[file]
		if not (file is String and sections is Dictionary):
			return false
		var cfg := ConfigFile.new()
		for section: Variant in sections:
			var keys: Variant = sections[section]
			if not (section is String and keys is Dictionary):
				return false
			for key: Variant in keys:
				if not key is String:
					return false
				cfg.set_value(section, key, keys[key])
		files[file] = cfg
	_files = files
	version += 1
	return true


func reload() -> void:
	version += 1
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
	# Strings are taken as written (no quotes needed on the command line).
	var parsed: Variant = raw if current is String else str_to_var(raw)
	if parsed == null:
		# A shell that ate the quotes in a dictionary or array value: without this
		# it would quietly become empty.
		push_error("Tuning: can't parse --tune=%s (quotes lost on the command line?)" % override)
		return
	var value: Variant = type_convert(parsed, typeof(current))
	_files[path[0]].set_value(path[1], path[2], value)
	print("Tuning: %s/%s/%s = %s (launch override)" % [path[0], path[1], path[2], value])


func has_value(file: String, section: String, key: String) -> bool:
	var cfg: ConfigFile = _files.get(file)
	return cfg != null and cfg.has_section_key(section, key)


## A value that may be left out of its section, with the structural default to
## use then (e.g. an ability's dash fields only exist on dashing abilities).
func get_optional(file: String, section: String, key: String, default: Variant) -> Variant:
	var cfg: ConfigFile = _files.get(file)
	if cfg == null or not cfg.has_section_key(section, key):
		return default
	return cfg.get_value(section, key)


func has_file(file: String) -> bool:
	return _files.has(file)


## Data file names (without ".cfg") that start with prefix, sorted.
func files_with_prefix(prefix: String) -> PackedStringArray:
	var names := PackedStringArray()
	for file_name: String in _files:
		if file_name.begins_with(prefix):
			names.append(file_name)
	names.sort()
	return names


## A file's section names in file order (for files that list things, like items),
## or none if the file doesn't exist.
func get_sections(file: String) -> PackedStringArray:
	var cfg: ConfigFile = _files.get(file)
	return cfg.get_sections() if cfg else PackedStringArray()


func get_value(file: String, section: String, key: String) -> Variant:
	var cfg: ConfigFile = _files.get(file)
	if cfg == null:
		push_error("Tuning: no data file %s%s.cfg" % [DATA_DIR, file])
		return null
	if not cfg.has_section_key(section, key):
		push_error("Tuning: %s.cfg is missing [%s] %s" % [file, section, key])
		return null
	return cfg.get_value(section, key)

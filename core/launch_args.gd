class_name LaunchArgs
## Command-line options for this game, passed after Godot's own arguments and "--":
##
##   godot --headless -- --server --port=24565
##   godot -- --connect --address=192.168.1.20:24565
##
## Flags: --server, --connect, --bot, --bot-party, --verbose, --hitboxes. Values: --port=,
## --address=, --quit-after=, --screenshot-dir=, --tune= (repeatable; see Tuning).


static func has_flag(flag_name: String) -> bool:
	return ("--" + flag_name) in _all_args()


static func get_value(key: String, default: String = "") -> String:
	var prefix := "--" + key + "="
	for arg in _all_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return default


## Every value given for a key that can repeat, e.g. --tune=a --tune=b.
static func get_values(key: String) -> PackedStringArray:
	var prefix := "--" + key + "="
	var values := PackedStringArray()
	for arg in _all_args():
		if arg.begins_with(prefix):
			values.append(arg.substr(prefix.length()))
	return values


static func _all_args() -> PackedStringArray:
	return OS.get_cmdline_user_args() + OS.get_cmdline_args()

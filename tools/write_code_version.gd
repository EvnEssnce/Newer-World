extends SceneTree
## Writes CodeVersion.from_source() to res://code_version.txt, which an export
## packs in so the exported game knows which code it was built from (see
## CodeVersion). Run by tools/export_client.ps1 just before exporting:
##   godot --headless --script res://tools/write_code_version.gd


func _init() -> void:
	var version := CodeVersion.from_source()
	var file := FileAccess.open(CodeVersion.STAMP_PATH, FileAccess.WRITE)
	if file == null:
		printerr("Couldn't write %s: %s" % [CodeVersion.STAMP_PATH,
				error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(version + "\n")
	file.close()
	print("Code version %s written to %s" % [version, CodeVersion.STAMP_PATH])
	quit(0)

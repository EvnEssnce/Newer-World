class_name CodeVersion
## Which build of the game's code this process runs, as a short hash, so a
## server can refuse a client on other code (VersionCheck) with a message
## instead of odd failures (RPCs and snapshots that no longer line up).
##
## Run from the project folder, it's the SHA-256 of every file that counts
## (counts(): scripts, scenes, resources, shaders and project.godot; not
## data/*.cfg, which the server sends anyway, nor tests, tools or docs), read
## with "\r" removed so a Windows and a Linux checkout of one commit agree.
## An exported game can't read its sources (scripts are packed as tokens), so
## tools/export_client.ps1 first writes the hash of the sources it exports to
## STAMP_PATH (tools/write_code_version.gd) and the export packs that file in.
##
## --fake-version=X (tests only) makes this process claim version X.

const STAMP_PATH := "res://code_version.txt"
## Hex characters kept: plenty to tell builds apart, short enough to read out.
const LENGTH := 12
const EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "gdshader"]
## Folders (top level) whose files never count.
const SKIPPED_DIRS: Array[String] = [".godot", ".git", ".claude", "build", "data",
		"tests", "tools", "design", "assets", "addons"]

static var _current := ""


## This process's version (cached).
static func current() -> String:
	if _current.is_empty():
		_current = LaunchArgs.get_value("fake-version")
		if _current.is_empty() and OS.has_feature("template"):
			_current = _read_stamp()
		if _current.is_empty():
			_current = from_source()
	return _current


## The hash of `files` ({res:// path: contents}): the same for the same paths
## and contents in any order, line endings ignored.
static func compute(files: Dictionary) -> String:
	var paths: Array = files.keys()
	paths.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for path: String in paths:
		var contents: PackedByteArray = files[path]
		# Each entry is its path, a 0 byte, its length and its bytes, so moving
		# text from one file to the next changes the hash.
		var text := contents.get_string_from_utf8().replace("\r", "").to_utf8_buffer()
		ctx.update(path.to_utf8_buffer())
		ctx.update(PackedByteArray([0]))
		ctx.update(str(text.size()).to_utf8_buffer())
		ctx.update(PackedByteArray([0]))
		if not text.is_empty():  # update() refuses an empty array
			ctx.update(text)
	return ctx.finish().hex_encode().substr(0, LENGTH)


## Whether the file at `path` (res://...) is part of the version.
static func counts(path: String) -> bool:
	if path == "res://project.godot":
		return true
	var relative := path.trim_prefix("res://")
	if relative.get_slice("/", 0) in SKIPPED_DIRS:
		return false
	return relative.get_extension() in EXTENSIONS


## The hash of the project's own files (run from the project folder).
static func from_source() -> String:
	var files := {}
	_collect("res://", files)
	return compute(files)


## The hash written by tools/write_code_version.gd before an export, or "".
static func _read_stamp() -> String:
	if not FileAccess.file_exists(STAMP_PATH):
		push_warning("CodeVersion: %s is missing from this build" % STAMP_PATH)
		return ""
	return FileAccess.get_file_as_string(STAMP_PATH).strip_edges()


static func _collect(dir_path: String, files: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file in dir.get_files():
		var path := dir_path.path_join(file)
		if counts(path):
			files[path] = FileAccess.get_file_as_bytes(path)
	for sub in dir.get_directories():
		var path := dir_path.path_join(sub)
		if dir_path != "res://" or sub not in SKIPPED_DIRS:
			_collect(path, files)

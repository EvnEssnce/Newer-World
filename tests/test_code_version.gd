extends TestCase
## CodeVersion: the hash a server compares with each client's (VersionCheck).
## The same files give the same version in any order and with either line
## ending; any change to a file, its path or which files there are gives a new
## one; only code files count, not tuning, tests or tools.


func _files(entries: Dictionary) -> Dictionary:
	var files := {}
	for path: String in entries:
		files[path] = (entries[path] as String).to_utf8_buffer()
	return files


func test_same_files_same_version_in_any_order() -> void:
	var a := CodeVersion.compute(_files({"res://a.gd": "one", "res://b.gd": "two"}))
	var b := CodeVersion.compute(_files({"res://b.gd": "two", "res://a.gd": "one"}))
	assert_eq(a, b)
	assert_eq(a.length(), CodeVersion.LENGTH)


func test_line_endings_dont_count() -> void:
	assert_eq(CodeVersion.compute(_files({"res://a.gd": "x\r\ny\r\n"})),
			CodeVersion.compute(_files({"res://a.gd": "x\ny\n"})))


func test_any_change_gives_a_new_version() -> void:
	var base := CodeVersion.compute(_files({"res://a.gd": "one", "res://b.gd": "two"}))
	assert_true(base != CodeVersion.compute(_files({"res://a.gd": "one", "res://b.gd": "twO"})),
			"an edit changes it")
	assert_true(base != CodeVersion.compute(_files({"res://a.gd": "one", "res://c.gd": "two"})),
			"a rename changes it")
	assert_true(base != CodeVersion.compute(_files({"res://a.gd": "one"})),
			"a removed file changes it")
	assert_true(base != CodeVersion.compute(_files({"res://a.gd": "onetwo", "res://b.gd": ""})),
			"text moved between files changes it")


func test_only_code_files_count() -> void:
	for path: String in ["res://project.godot", "res://game/main.gd", "res://game/main.tscn",
			"res://game/enemy/enemy.tscn", "res://core/net.gd"]:
		assert_true(CodeVersion.counts(path), path)
	for path: String in ["res://data/combat.cfg", "res://tests/test_loot.gd",
			"res://tools/write_code_version.gd", "res://build/smoke/x.gd", "res://README.md",
			"res://game/main.gd.uid", "res://addons/godot-sqlite/gdsqlite.gdextension",
			"res://code_version.txt"]:
		assert_false(CodeVersion.counts(path), path)


func test_the_project_has_a_version() -> void:
	var version := CodeVersion.from_source()
	assert_eq(version.length(), CodeVersion.LENGTH)
	assert_eq(version, CodeVersion.from_source(), "the same on a second read")

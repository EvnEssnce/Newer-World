extends Node
## Runs every tests/test_*.gd and quits with exit code 0 if all pass, 1 if not.
## tools/run_tests.ps1 runs this scene headless and also fails on script errors,
## because a test that crashes stops early without recording a failure.

const TEST_DIR := "res://tests/"


func _ready() -> void:
	# Wait until the scene tree is set up, so tests can add nodes (e.g. physics bodies).
	await get_tree().process_frame
	var passed := 0
	var failed := 0
	for file_name in DirAccess.get_files_at(TEST_DIR):
		if not (file_name.begins_with("test_") and file_name.get_extension() == "gd"):
			continue
		var script: GDScript = load(TEST_DIR + file_name)
		for method in script.get_script_method_list():
			var test_name: String = method.name
			if not test_name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.before_each()
			test.call(test_name)
			if test.failures.is_empty():
				passed += 1
				continue
			failed += 1
			for failure in test.failures:
				print("FAIL %s.%s: %s" % [file_name.get_basename(), test_name, failure])
	print("%d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

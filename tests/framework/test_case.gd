class_name TestCase
extends RefCounted
## Base class for tests. Put tests in tests/test_*.gd, extend TestCase, and name
## each test method test_*. before_each() runs before every test on a fresh
## instance. Run them all with tools/run_tests.ps1.

var failures: PackedStringArray = []


func before_each() -> void:
	pass


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("expected true", message)


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("expected false", message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_fail("expected %s, got %s" % [expected, actual], message)


func assert_almost(actual: float, expected: float, tolerance: float = 0.001,
		message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("expected %s (+/- %s), got %s" % [expected, tolerance, actual], message)


func _fail(what: String, message: String) -> void:
	failures.append(what if message.is_empty() else "%s: %s" % [message, what])

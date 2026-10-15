class_name AccountRules
extends RefCounted
## Name and password rules for accounts and characters (data/accounts.cfg).
## Each check returns "" when the value is fine, else why not (shown to the
## player). The server checks everything; clients check first only to explain
## sooner. Pure: tests build one by hand (tests/test_accounts.gd).

var account_name_min := 3
var account_name_max := 20
var account_name_chars := ""
var max_characters := 8
var character_name_min := 3
var character_name_max := 16
var character_name_chars := ""
var password_min := 6
var password_max := 64
## PBKDF2 iterations for new hashes (PasswordHash.make).
var hash_iterations := 310000


## The rules in data/accounts.cfg. Not cached: it's read once per request.
static func from_tuning() -> AccountRules:
	var r := AccountRules.new()
	r.account_name_min = Tuning.get_value("accounts", "account", "name_min")
	r.account_name_max = Tuning.get_value("accounts", "account", "name_max")
	r.account_name_chars = Tuning.get_value("accounts", "account", "name_chars")
	r.max_characters = Tuning.get_value("accounts", "account", "max_characters")
	r.character_name_min = Tuning.get_value("accounts", "character", "name_min")
	r.character_name_max = Tuning.get_value("accounts", "character", "name_max")
	r.character_name_chars = Tuning.get_value("accounts", "character", "name_chars")
	r.password_min = Tuning.get_value("accounts", "password", "min_length")
	r.password_max = Tuning.get_value("accounts", "password", "max_length")
	r.hash_iterations = Tuning.get_value("accounts", "password", "iterations")
	return r


func account_name_error(account_name: String) -> String:
	return _name_error("Account name", account_name, account_name_min, account_name_max,
			account_name_chars)


func character_name_error(character_name: String) -> String:
	var error := _name_error("Character name", character_name, character_name_min,
			character_name_max, character_name_chars)
	if error.is_empty() and not _is_letter(character_name[0]):
		return "Character name must start with a letter."
	return error


func password_error(password: String) -> String:
	if password.length() < password_min:
		return "Password needs at least %d characters." % password_min
	if password.length() > password_max:
		return "Password can have at most %d characters." % password_max
	return ""


## "" if an account with `count` characters may make another.
func character_count_error(count: int) -> String:
	if count >= max_characters:
		return "An account can have at most %d characters." % max_characters
	return ""


func _name_error(what: String, value: String, min_length: int, max_length: int,
		allowed: String) -> String:
	if value.length() < min_length:
		return "%s needs at least %d characters." % [what, min_length]
	if value.length() > max_length:
		return "%s can have at most %d characters." % [what, max_length]
	for c in value:
		if not allowed.contains(c):
			return "%s can't contain \"%s\"." % [what, c]
	return ""


static func _is_letter(c: String) -> bool:
	return c.to_lower() != c.to_upper()

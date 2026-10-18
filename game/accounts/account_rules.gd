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
## Name filter (data/name_filter.cfg, see blocked_name): words refused anywhere
## in a name, words refused as the whole name, and ordinary words cut out first.
var blocked_contains := PackedStringArray()
var blocked_whole := PackedStringArray()
var allowed_words := PackedStringArray()

## Look-alike characters read as letters before the filter checks a name.
const LOOK_ALIKES := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
		"9": "g", "@": "a", "$": "s", "!": "i"}
const BLOCKED_NAME := "That name isn't allowed."


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
	r.blocked_contains = PackedStringArray(Tuning.get_optional("name_filter", "filter", "contains", []))
	r.blocked_whole = PackedStringArray(Tuning.get_optional("name_filter", "filter", "whole", []))
	r.allowed_words = PackedStringArray(Tuning.get_optional("name_filter", "filter", "allowed", []))
	return r


func account_name_error(account_name: String) -> String:
	var error := _name_error("Account name", account_name, account_name_min, account_name_max,
			account_name_chars)
	return BLOCKED_NAME if error.is_empty() and blocked_name(account_name) else error


func character_name_error(character_name: String) -> String:
	var error := _name_error("Character name", character_name, character_name_min,
			character_name_max, character_name_chars)
	if error.is_empty() and not _is_letter(character_name[0]):
		return "Character name must start with a letter."
	if error.is_empty() and blocked_name(character_name):
		return BLOCKED_NAME
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


## True if the name holds a blocked word (data/name_filter.cfg): lower-cased,
## look-alikes read as letters, everything else dropped, allowed words cut out;
## then any `contains` word in it (or in it with repeated letters squeezed, for
## words of 4+ letters once squeezed: "fuuuck"), or the whole of it a `whole` word.
func blocked_name(value: String) -> bool:
	var letters := _without_allowed(letters_of(value))
	var squeezed := _without_allowed(squeeze(letters))
	for word in blocked_contains:
		if letters.contains(word):
			return true
		var short := squeeze(word)
		if short.length() >= 4 and squeezed.contains(short):
			return true
	return letters in blocked_whole or squeezed in blocked_whole


## Lower case, look-alikes as letters, nothing but a-z left.
static func letters_of(value: String) -> String:
	var result := ""
	for c in value.to_lower():
		var letter: String = LOOK_ALIKES.get(c, c)
		if letter >= "a" and letter <= "z":
			result += letter
	return result


## Runs of one letter as one ("fuuuck" -> "fuck").
static func squeeze(value: String) -> String:
	var result := ""
	for c in value:
		if not result.ends_with(c):
			result += c
	return result


func _without_allowed(value: String) -> String:
	for word in allowed_words:
		value = value.replace(word, "")
	return value


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

extends TestCase
## Accounts: PBKDF2 password hashes (RFC test vectors, the stored format,
## verifying), the name and password rules, bot names, and a hash stored and
## checked through Persistence (an in-memory database). Rules are built by
## hand, not read from data/.

var rules: AccountRules


func before_each() -> void:
	rules = AccountRules.new()
	rules.account_name_min = 3
	rules.account_name_max = 10
	rules.account_name_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	rules.character_name_min = 3
	rules.character_name_max = 8
	rules.character_name_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	rules.password_min = 6
	rules.password_max = 12
	rules.max_characters = 2


# --- PasswordHash ---

func test_pbkdf2_matches_the_published_test_vectors() -> void:
	var password := "password".to_utf8_buffer()
	var salt := "salt".to_utf8_buffer()
	assert_eq(PasswordHash.pbkdf2_sha256(password, salt, 1, 32).hex_encode(),
			"120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
	assert_eq(PasswordHash.pbkdf2_sha256(password, salt, 2, 32).hex_encode(),
			"ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43")
	assert_eq(PasswordHash.pbkdf2_sha256(password, salt, 4096, 32).hex_encode(),
			"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")


func test_pbkdf2_empty_password_matches_the_standard() -> void:
	# PBKDF2-HMAC-SHA256("", "salt", 1) = HMAC(empty key, "salt" + INT(1)), from .NET's HMACSHA256.
	assert_eq(PasswordHash.pbkdf2_sha256(PackedByteArray(), "salt".to_utf8_buffer(), 1, 32).hex_encode(),
			"f135c27993baf98773c5cdb40a5706ce6a345cde61b000a67858650cd6a324d7")


func test_pbkdf2_longer_keys_use_more_blocks() -> void:
	var key := PasswordHash.pbkdf2_sha256("pw".to_utf8_buffer(), "salt".to_utf8_buffer(), 3, 40)
	assert_eq(key.size(), 40)
	assert_eq(key.slice(0, 32), PasswordHash.pbkdf2_sha256("pw".to_utf8_buffer(),
			"salt".to_utf8_buffer(), 3, 32), "the first block is the 32-byte key")


func test_stored_hash_holds_scheme_iterations_and_salt() -> void:
	var stored := PasswordHash.make("hunter22", 50, "0123456789abcdef".to_utf8_buffer())
	var parts := stored.split("$")
	assert_eq(parts.size(), 4)
	assert_eq(parts[0], "pbkdf2_sha256")
	assert_eq(parts[1], "50")
	assert_eq(Marshalls.base64_to_raw(parts[2]).get_string_from_utf8(), "0123456789abcdef")
	assert_eq(Marshalls.base64_to_raw(parts[3]).size(), PasswordHash.KEY_BYTES)
	assert_eq(PasswordHash.iterations_of(stored), 50)


func test_verify_accepts_the_password_and_nothing_else() -> void:
	var stored := PasswordHash.make("Correct horse", 20)
	assert_true(PasswordHash.verify("Correct horse", stored))
	assert_false(PasswordHash.verify("correct horse", stored), "case matters")
	assert_false(PasswordHash.verify("Correct horse ", stored))
	assert_false(PasswordHash.verify("", stored))


func test_each_hash_gets_its_own_salt() -> void:
	var a := PasswordHash.make("same password", 10)
	var b := PasswordHash.make("same password", 10)
	assert_true(a != b, "random salts")
	assert_true(PasswordHash.verify("same password", a))
	assert_true(PasswordHash.verify("same password", b))


func test_verify_uses_the_stored_iteration_count() -> void:
	# A hash made with an older count still checks after the setting changes.
	var stored := PasswordHash.make("pass word", 7)
	assert_true(PasswordHash.verify("pass word", stored))
	var other := stored.replace("$7$", "$8$")
	assert_false(PasswordHash.verify("pass word", other))


func test_malformed_hashes_never_verify() -> void:
	for stored in ["", "plain", "pbkdf2_sha256$10$abc", "md5$10$c2FsdA==$a2V5",
			"pbkdf2_sha256$x$c2FsdA==$a2V5", "pbkdf2_sha256$0$c2FsdA==$a2V5",
			"pbkdf2_sha256$99999999999$c2FsdA==$a2V5", "pbkdf2_sha256$10$$a2V5"]:
		assert_false(PasswordHash.verify("password", stored), stored)
	assert_eq(PasswordHash.iterations_of("plain"), 0)


func test_unicode_passwords_round_trip() -> void:
	var stored := PasswordHash.make("pässwörd🔥", 5)
	assert_true(PasswordHash.verify("pässwörd🔥", stored))
	assert_false(PasswordHash.verify("passwörd🔥", stored))


func test_constant_time_compare() -> void:
	assert_true(PasswordHash.equal_constant_time(PackedByteArray([1, 2, 3]), PackedByteArray([1, 2, 3])))
	assert_false(PasswordHash.equal_constant_time(PackedByteArray([1, 2, 3]), PackedByteArray([1, 2, 4])))
	assert_false(PasswordHash.equal_constant_time(PackedByteArray([1, 2]), PackedByteArray([1, 2, 3])))


# --- AccountRules ---

func test_account_names() -> void:
	assert_eq(rules.account_name_error("ash_99"), "")
	assert_eq(rules.account_name_error("abc"), "", "the minimum length is allowed")
	assert_eq(rules.account_name_error("abcdefghij"), "", "the maximum length is allowed")
	assert_true(rules.account_name_error("ab").contains("at least 3"))
	assert_true(rules.account_name_error("abcdefghijk").contains("at most 10"))
	assert_true(rules.account_name_error("ash 99").contains("\" \""))
	assert_true(rules.account_name_error("ash-99").contains("\"-\""))
	assert_true(rules.account_name_error("äsh99").contains("\"ä\""))


func test_character_names() -> void:
	assert_eq(rules.character_name_error("Ashwyn"), "")
	assert_true(rules.character_name_error("As").contains("at least 3"))
	assert_true(rules.character_name_error("Ashwynnnn").contains("at most 8"))
	assert_true(rules.character_name_error("Ash9").contains("\"9\""), "letters only here")
	rules.character_name_chars += "_"
	assert_true(rules.character_name_error("_Ash").contains("start with a letter"))
	assert_eq(rules.character_name_error("Ash_"), "")


func test_passwords() -> void:
	assert_eq(rules.password_error("abcdef"), "")
	assert_eq(rules.password_error("any chars ok"), "", "spaces and anything else are allowed")
	assert_true(rules.password_error("abcde").contains("at least 6"))
	assert_true(rules.password_error("abcdefghijklm").contains("at most 12"))


func test_character_count() -> void:
	assert_eq(rules.character_count_error(0), "")
	assert_eq(rules.character_count_error(1), "")
	assert_true(rules.character_count_error(2).contains("at most 2"))


func test_bot_character_names_pass_the_rules() -> void:
	assert_eq(AccountService.bot_character_name(1234567890), "Botbcdefghija")
	rules.character_name_max = 16
	assert_eq(rules.character_name_error(AccountService.bot_character_name(2147483647)), "")
	assert_true(AccountService.bot_character_name(11) != AccountService.bot_character_name(12))


# --- Through Persistence ---

func test_hash_stored_in_an_account_verifies_after_lookup() -> void:
	if not Persistence.available():
		return
	var p := Persistence.new()
	assert_true(p.open(":memory:"), p.last_error)
	var stored := PasswordHash.make("open sesame", 10)
	var id := p.create_account("Ashwyn", stored)
	assert_true(id > 0, p.last_error)
	var account := p.find_account("ASHWYN")
	assert_eq(account.get("id"), id, "names are found ignoring case")
	assert_true(PasswordHash.verify("open sesame", account["password_hash"]))
	assert_false(PasswordHash.verify("open sesame!", account["password_hash"]))
	assert_eq(p.create_account("ashwyn", stored), 0, "taken ignoring case")
	p.close()

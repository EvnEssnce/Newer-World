class_name PasswordHash
extends RefCounted
## Salted, slow password hashes: PBKDF2-HMAC-SHA256 (RFC 8018) over Godot's
## native HMAC. A stored hash is one string holding everything needed to check
## it later, so raising `[password] iterations` (data/accounts.cfg) only
## affects new hashes:
##
##   pbkdf2_sha256$<iterations>$<salt, base64>$<key, base64>
##
## Pure (no Tuning, no database): unit tested in tests/test_accounts.gd.

const SCHEME := "pbkdf2_sha256"
const SALT_BYTES := 16
const KEY_BYTES := 32
## Refuse stored hashes claiming more than this many iterations (a corrupt or
## hostile row shouldn't stall the server).
const MAX_ITERATIONS := 10_000_000


## A new stored hash of `password`. `salt` is for tests; empty = 16 random bytes.
static func make(password: String, iterations: int,
		salt: PackedByteArray = PackedByteArray()) -> String:
	iterations = clampi(iterations, 1, MAX_ITERATIONS)
	if salt.is_empty():
		salt = Crypto.new().generate_random_bytes(SALT_BYTES)
	var key := pbkdf2_sha256(password.to_utf8_buffer(), salt, iterations, KEY_BYTES)
	return "%s$%d$%s$%s" % [SCHEME, iterations, Marshalls.raw_to_base64(salt),
			Marshalls.raw_to_base64(key)]


## Whether `password` matches a stored hash from make(). False for anything
## malformed.
static func verify(password: String, stored: String) -> bool:
	var parts := stored.split("$")
	if parts.size() != 4 or parts[0] != SCHEME or not parts[1].is_valid_int():
		return false
	var iterations := parts[1].to_int()
	if iterations < 1 or iterations > MAX_ITERATIONS:
		return false
	var salt := Marshalls.base64_to_raw(parts[2])
	var expected := Marshalls.base64_to_raw(parts[3])
	if salt.is_empty() or expected.is_empty():
		return false
	var key := pbkdf2_sha256(password.to_utf8_buffer(), salt, iterations, expected.size())
	return equal_constant_time(key, expected)


## The iteration count a stored hash was made with (0 if malformed).
static func iterations_of(stored: String) -> int:
	var parts := stored.split("$")
	return parts[1].to_int() if parts.size() == 4 and parts[1].is_valid_int() else 0


## PBKDF2 with HMAC-SHA256: `length` bytes of key from a password and salt.
static func pbkdf2_sha256(password: PackedByteArray, salt: PackedByteArray,
		iterations: int, length: int) -> PackedByteArray:
	var crypto := Crypto.new()
	# Godot refuses an empty HMAC key. HMAC pads keys with zero bytes, so one
	# zero byte is the same key as none.
	if password.is_empty():
		password = PackedByteArray([0])
	var result := PackedByteArray()
	var block := 1
	while result.size() < length:
		var index := PackedByteArray([(block >> 24) & 0xff, (block >> 16) & 0xff,
				(block >> 8) & 0xff, block & 0xff])
		var u := crypto.hmac_digest(HashingContext.HASH_SHA256, password, salt + index)
		# XOR 8 bytes at a time: 4 ints per iteration instead of 32 bytes.
		var t := u.to_int64_array()
		for _i in iterations - 1:
			u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
			var words := u.to_int64_array()
			t[0] ^= words[0]
			t[1] ^= words[1]
			t[2] ^= words[2]
			t[3] ^= words[3]
		result.append_array(t.to_byte_array())
		block += 1
	return result.slice(0, length)


## Byte arrays equal, in a time that doesn't depend on where they differ.
static func equal_constant_time(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0

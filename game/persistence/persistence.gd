class_name Persistence
extends RefCounted
## The one module that touches the database (CLAUDE.md rule). Server only.
## SQLite through the godot-sqlite GDExtension (addons/godot-sqlite) in
## development; Postgres later behind the same methods, so nothing outside this
## file writes SQL. Unit tested against a temporary database
## (tests/test_persistence.gd).
##
## Schema: `accounts` (login name, password hash) and `characters` (one row per
## character: name, class, and its CharacterSave parts as JSON text columns,
## which map to Postgres jsonb). Names are unique ignoring case.
##
## Migrations: MIGRATIONS[i] takes the schema from version i to i + 1, kept in
## SQLite's `PRAGMA user_version`. open() runs the missing ones, each in a
## transaction. Never edit a shipped migration: append a new one.

const MIGRATIONS := [
	# 1: accounts and characters.
	[
		"""CREATE TABLE accounts (
			id INTEGER PRIMARY KEY,
			name TEXT NOT NULL UNIQUE COLLATE NOCASE,
			password_hash TEXT NOT NULL,
			created_at INTEGER NOT NULL
		);""",
		"""CREATE TABLE characters (
			id INTEGER PRIMARY KEY,
			account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			name TEXT NOT NULL UNIQUE COLLATE NOCASE,
			class_id TEXT NOT NULL,
			build TEXT NOT NULL DEFAULT '{}',
			inventory TEXT NOT NULL DEFAULT '{}',
			equipment TEXT NOT NULL DEFAULT '{}',
			tradeskills TEXT NOT NULL DEFAULT '{}',
			created_at INTEGER NOT NULL,
			saved_at INTEGER NOT NULL
		);""",
		"CREATE INDEX characters_by_account ON characters(account_id);",
	],
]

## Why the last call failed ("" after a success).
var last_error := ""

## The godot-sqlite `SQLite` object. Made through ClassDB so this script still
## parses where the extension has no binary (available() says false there).
var _db: Object


## Whether the SQLite extension is loaded on this machine.
static func available() -> bool:
	return ClassDB.class_exists("SQLite")


## Opens (or creates) the database file at `path` (user:// or absolute) and
## brings its schema up to date. False with last_error on failure.
func open(path: String) -> bool:
	close()
	if not available():
		return _failed("The SQLite extension isn't loaded (addons/godot-sqlite).")
	_db = ClassDB.instantiate("SQLite")
	_db.path = path
	_db.default_extension = ""  # use the path exactly as given
	_db.foreign_keys = true
	_db.verbosity_level = 0
	if not _db.open_db():
		var error := "Couldn't open %s: %s" % [path, _db.error_message]
		_db = null
		return _failed(error)
	if not _migrate():
		close()
		return false
	return _ok()


func is_open() -> bool:
	return _db != null


func close() -> void:
	if _db:
		_db.close_db()
	_db = null


## The schema version the open database is at (MIGRATIONS.size() once open).
func schema_version() -> int:
	var rows := _select("PRAGMA user_version;", [])
	return int(_plain(rows[0]).get("user_version", 0)) if rows.size() == 1 else 0


# --- Accounts ---

## A new account. Returns its id, or 0 with last_error (name taken). The hash
## is made by the caller (accounts are build order item 3.2).
func create_account(account_name: String, password_hash: String) -> int:
	if not _check_open():
		return 0
	if not find_account(account_name).is_empty():
		return _failed_id("The account name %s is taken." % account_name)
	if not _run("INSERT INTO accounts (name, password_hash, created_at) VALUES (?, ?, ?);",
			[account_name, password_hash, _now()]):
		return 0
	return _ok_id(_db.last_insert_rowid)


## {id, name, password_hash} of the account with this name (any case), or {}.
func find_account(account_name: String) -> Dictionary:
	var rows := _select("SELECT id, name, password_hash FROM accounts WHERE name = ?;",
			[account_name])
	return _plain(rows[0]) if rows.size() == 1 else {}


# --- Characters ---

## Stores a new character for an account. Sets save.id and save.account_id
## and returns the id, or 0 with last_error (no such account, name taken).
func create_character(account_id: int, save: CharacterSave) -> int:
	if not _check_open():
		return 0
	if _select("SELECT id FROM accounts WHERE id = ?;", [account_id]).is_empty():
		return _failed_id("No account %d." % account_id)
	if not _select("SELECT id FROM characters WHERE name = ?;", [save.name]).is_empty():
		return _failed_id("The name %s is taken." % save.name)
	var now := _now()
	if not _run("""INSERT INTO characters (account_id, name, class_id, build, inventory,
			equipment, tradeskills, created_at, saved_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);""",
			[account_id, save.name, save.class_id, encode(save.build), encode(save.inventory),
			encode(save.equipment), encode(save.tradeskills), now, now]):
		return 0
	save.id = _db.last_insert_rowid
	save.account_id = account_id
	return _ok_id(save.id)


## An account's characters, oldest first: [{id, name, class_id}].
func list_characters(account_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in _select("SELECT id, name, class_id FROM characters WHERE account_id = ? ORDER BY id;",
			[account_id]):
		result.append(_plain(row))
	return result


## The character with this id, or null (last_error says why).
func load_character(character_id: int) -> CharacterSave:
	var rows := _select("""SELECT id, account_id, name, class_id, build, inventory, equipment,
			tradeskills FROM characters WHERE id = ?;""", [character_id])
	if rows.size() != 1:
		if last_error.is_empty():
			_failed("No character %d." % character_id)
		return null
	var row := _plain(rows[0])
	var save := CharacterSave.new()
	save.id = row["id"]
	save.account_id = row["account_id"]
	save.name = row["name"]
	save.class_id = row["class_id"]
	save.build = _decode_dict(row["build"])
	save.inventory = _decode_dict(row["inventory"])
	save.equipment = _decode_dict(row["equipment"])
	save.tradeskills = _decode_dict(row["tradeskills"])
	return save


## Writes a stored character's current state (its name and class stay as
## created). False with last_error if it isn't stored.
func save_character(save: CharacterSave) -> bool:
	if not _check_open():
		return false
	if _select("SELECT id FROM characters WHERE id = ?;", [save.id]).is_empty():
		return _failed("No character %d." % save.id)
	if not _run("""UPDATE characters SET build = ?, inventory = ?, equipment = ?,
			tradeskills = ?, saved_at = ? WHERE id = ?;""",
			[encode(save.build), encode(save.inventory), encode(save.equipment),
			encode(save.tradeskills), _now(), save.id]):
		return false
	return _ok()


## Saves several characters in one transaction (all or none): the periodic
## save of everyone online.
func save_characters(saves: Array[CharacterSave]) -> bool:
	if not _check_open() or not _run("BEGIN;", []):
		return false
	for save in saves:
		if not save_character(save):
			var error := last_error
			_run("ROLLBACK;", [])
			return _failed(error)
	if not _run("COMMIT;", []):
		_run("ROLLBACK;", [])
		return false
	return _ok()


func delete_character(character_id: int) -> bool:
	if not _check_open():
		return false
	if _select("SELECT id FROM characters WHERE id = ?;", [character_id]).is_empty():
		return _failed("No character %d." % character_id)
	return _run("DELETE FROM characters WHERE id = ?;", [character_id]) and _ok()


# --- JSON columns ---

## A save part as JSON text, floats at full precision (exact round trip).
static func encode(value: Variant) -> String:
	return JSON.stringify(value, "", false, true)


## The reverse of encode. JSON numbers come back as floats, so whole ones
## become ints again (uids, counts, gear scores, levels); a float field that
## happens to be whole (120.0) reads back fine as an int. Null if it isn't JSON.
static func decode(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return _ints_back(json.data)


static func _ints_back(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	if value is Array:
		var result := []
		for entry: Variant in value:
			result.append(_ints_back(entry))
		return result
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _ints_back(value[key])
		return result
	return value


func _decode_dict(text: Variant) -> Dictionary:
	var value: Variant = decode(str(text))
	if value is Dictionary:
		return value
	push_warning("Persistence: a saved column isn't a JSON object; using {}.")
	return {}


# --- SQLite plumbing ---

func _check_open() -> bool:
	return true if _db else _failed("The database isn't open.")


## Runs a statement with ? bindings. False with last_error on an SQL error.
func _run(sql: String, bindings: Array) -> bool:
	if not _db:
		return _failed("The database isn't open.")
	if not _db.query_with_bindings(sql, bindings):
		return _failed("SQL error: %s" % _db.error_message)
	last_error = ""
	return true


## The rows of a query ([] on an error, with last_error set).
func _select(sql: String, bindings: Array) -> Array:
	if not _run(sql, bindings):
		return []
	return _db.query_result


func _migrate() -> bool:
	var version := schema_version()
	if version > MIGRATIONS.size():
		return _failed("The database is at schema %d; this build knows %d." % [version, MIGRATIONS.size()])
	while version < MIGRATIONS.size():
		if not _run("BEGIN;", []):
			return false
		for sql in MIGRATIONS[version]:
			if not _run(sql, []):
				var error := last_error
				_run("ROLLBACK;", [])
				return _failed("Migration %d: %s" % [version + 1, error])
		if not _run("PRAGMA user_version = %d;" % (version + 1), []) or not _run("COMMIT;", []):
			var error := last_error
			_run("ROLLBACK;", [])
			return _failed("Migration %d: %s" % [version + 1, error])
		version += 1
	return true


## A row with String keys (godot-sqlite gives StringName keys).
static func _plain(row: Dictionary) -> Dictionary:
	var result := {}
	for key: Variant in row:
		result[str(key)] = row[key]
	return result


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _ok() -> bool:
	last_error = ""
	return true


func _ok_id(value: int) -> int:
	last_error = ""
	return value


func _failed(error: String) -> bool:
	last_error = error
	return false


func _failed_id(error: String) -> int:
	last_error = error
	return 0

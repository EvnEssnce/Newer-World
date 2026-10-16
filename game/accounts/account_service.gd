class_name AccountService
extends Node
## /root/Main/Accounts on the server and every client (RPCs match by path):
## logging in, the character list, making a character and choosing one to
## play. Exists before World, which is only made once a character is chosen.
##
## Server: owns the Persistence (the only code that touches the database) and
## one Session per connected peer. It checks every request (AccountRules, the
## account owning the character, one login per account) and hashes passwords
## (PasswordHash) on a worker thread, so a slow hash never holds up a tick;
## the database is only used from the main thread. World._client_ready asks
## character_of(peer) for the class to spawn with.
##
## Client → server, reliable: _request_login(account, password, create),
## _request_create_character(name, class_id), _request_play(character_id).
## Server → that client: _receive_login(error, account, characters),
## _receive_characters(error, characters), _receive_play(error). A character
## entry is {id, name, class_id}. Logging out = disconnecting.
##
## Names (both sides: `names`, a PlayerNames): once a peer chooses a character
## the server sends it _receive_names({peer: name}) for everyone playing
## (itself included) and every other playing peer _receive_name(peer, name);
## a playing peer leaving sends the rest _receive_name_removed(peer). Sent
## before _receive_play, so a client has them before its World exists. Not in
## snapshots. Nameplates and the party HUD draw player_name(node, peer).
##
## --bot clients log in without typing (start_bot): account --account= (default
## bot_<peer id>), password "botpassword", the account's character named
## --character= (default "Bot" + the peer id in letters), made with --class= if
## missing.

## Client: the login screen's result. characters: [{id, name, class_id}].
signal login_finished(error: String, account_name: String, characters: Array)
## Client: the character list after making one (or why it wasn't made).
signal characters_changed(error: String, characters: Array)
## Client: "" = the chosen character is ready, enter the world.
signal play_finished(error: String)
## Client: a player's name arrived, changed or was forgotten.
signal name_changed(peer: int)

const BOT_PASSWORD := "botpassword"
const LOGIN_FAILED := "Wrong account name or password."

## Server: one peer's progress through login.
class Session:
	var account_id := 0
	var account_name := ""
	## 0 until a character is chosen.
	var character_id := 0
	var character_name := ""
	var class_id := ""
	## A password hash is running for this peer (further requests are ignored).
	var busy := false

## Both sides: the character names of the peers playing (see the top).
var names := PlayerNames.new()

## Server: the database (opened by server_open).
var persistence: Persistence
var _sessions: Dictionary[int, Session] = {}
## Password hashes running on worker threads: {task, out, done}.
var _hash_jobs: Array[Dictionary] = []
var _logins := 0
var _accounts_created := 0
var _characters_created := 0
var _plays := 0
var _refused := 0

# Client --bot state.
var _bot := false
var _bot_tried_create := false
var _bot_account := ""
var _bot_character := ""


## Server: opens the database at `path` (user://, absolute, or ":memory:").
## False with the reason printed.
func server_open(path: String) -> bool:
	persistence = Persistence.new()
	if not persistence.open(path):
		printerr("[server] database: %s" % persistence.last_error)
		return false
	print("[server] database %s (schema %d)" % [path, persistence.schema_version()])
	Net.peer_left.connect(_on_peer_left)
	return true


## Server: the character a peer chose ({id, name, class_id}), or {} if it
## hasn't logged in and chosen one.
func character_of(peer: int) -> Dictionary:
	var session: Session = _sessions.get(peer)
	if session == null or session.character_id == 0:
		return {}
	return {"id": session.character_id, "name": session.character_name, "class_id": session.class_id}


func _on_peer_left(peer: int) -> void:
	_sessions.erase(peer)
	if names.forget(peer):
		for other in names.peers():
			if Net.is_peer_connected(other):
				_receive_name_removed.rpc_id(other, peer)


## The name to draw for a player: its character's, or "Player N" until the
## server has sent it. `from` is any node in the tree.
static func player_name(from: Node, peer: int) -> String:
	var accounts := from.get_node_or_null("/root/Main/Accounts") as AccountService
	return accounts.names.name_of(peer) if accounts else PlayerNames.fallback(peer)


func print_summary() -> void:
	print("SUMMARY accounts logins=%d accounts_created=%d characters_created=%d plays=%d refused=%d" % [
			_logins, _accounts_created, _characters_created, _plays, _refused])


# --- Server: requests ---

@rpc("any_peer", "call_remote", "reliable")
func _request_login(account_name: String, password: String, create: bool) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var session: Session = _sessions.get(peer)
	if session and (session.busy or session.account_id != 0):
		return
	if session == null:
		session = Session.new()
		_sessions[peer] = session
	var rules := AccountRules.from_tuning()
	account_name = account_name.strip_edges()
	var error := rules.account_name_error(account_name)
	if create:
		if error.is_empty():
			error = rules.password_error(password)
		if error.is_empty() and not persistence.find_account(account_name).is_empty():
			error = "The account name %s is taken." % account_name
		if not error.is_empty():
			_refuse_login(peer, error)
			return
		var iterations := rules.hash_iterations
		_start_hash(peer, func() -> Variant: return PasswordHash.make(password, iterations),
				func(password_hash: Variant) -> void: _finish_create(peer, account_name, password_hash))
		return
	# A bad name or an overlong password can't match: don't spend a hash on it.
	var account := persistence.find_account(account_name) if error.is_empty() else {}
	if account.is_empty() or password.length() > rules.password_max:
		_refuse_login(peer, LOGIN_FAILED)
		return
	var stored: String = account["password_hash"]
	_start_hash(peer, func() -> Variant: return PasswordHash.verify(password, stored),
			func(ok: Variant) -> void: _finish_login(peer, account, ok))


## Runs `work` (a password hash) on a worker thread; `done` gets its result on
## the main thread (_process), where the database is used.
func _start_hash(peer: int, work: Callable, done: Callable) -> void:
	_sessions[peer].busy = true
	var out := {}
	var task := WorkerThreadPool.add_task(func() -> void: out["value"] = work.call())
	_hash_jobs.append({"task": task, "out": out, "done": done})


func _process(_delta: float) -> void:
	for i in range(_hash_jobs.size() - 1, -1, -1):
		var job: Dictionary = _hash_jobs[i]
		if WorkerThreadPool.is_task_completed(job["task"]):
			WorkerThreadPool.wait_for_task_completion(job["task"])
			_hash_jobs.remove_at(i)
			job["done"].call(job["out"]["value"])


func _exit_tree() -> void:
	for job: Dictionary in _hash_jobs:
		WorkerThreadPool.wait_for_task_completion(job["task"])
	_hash_jobs.clear()


func _finish_create(peer: int, account_name: String, password_hash: String) -> void:
	var session := _waiting_session(peer)
	if session == null:
		return
	var account_id := persistence.create_account(account_name, password_hash)
	if account_id == 0:
		_refuse_login(peer, persistence.last_error)
		return
	_accounts_created += 1
	print("[server] peer %d created account %s" % [peer, account_name])
	_finish_login(peer, persistence.find_account(account_name), true)


func _finish_login(peer: int, account: Dictionary, ok: bool) -> void:
	var session := _waiting_session(peer)
	if session == null:
		return
	if not ok:
		_refuse_login(peer, LOGIN_FAILED)
		return
	for other: Session in _sessions.values():
		if other.account_id == account["id"]:
			_refuse_login(peer, "That account is already logged in.")
			return
	session.account_id = account["id"]
	session.account_name = account["name"]
	_logins += 1
	_receive_login.rpc_id(peer, "", session.account_name, _characters(session))


## The session of a peer whose hash just finished (null if it left meanwhile).
func _waiting_session(peer: int) -> Session:
	var session: Session = _sessions.get(peer)
	if session == null or peer not in multiplayer.get_peers():
		return null
	session.busy = false
	return session


func _refuse_login(peer: int, error: String) -> void:
	_refused += 1
	_receive_login.rpc_id(peer, error, "", [])


@rpc("any_peer", "call_remote", "reliable")
func _request_create_character(character_name: String, class_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var session: Session = _sessions.get(peer)
	if session == null or session.account_id == 0 or session.character_id != 0:
		return
	var rules := AccountRules.from_tuning()
	character_name = character_name.strip_edges()
	var class_def := ClassDef.for_id(class_id)
	var characters := _characters(session)
	var error := rules.character_name_error(character_name)
	if error.is_empty() and class_def == null:
		error = "There's no class %s." % class_id
	if error.is_empty():
		error = rules.character_count_error(characters.size())
	if error.is_empty():
		# A new character starts with its class's default build and nothing
		# else; World/Saves loads and saves it from then on.
		var save := CharacterSave.capture(character_name, CharacterBuild.create_default(class_def),
				null, null, null)
		if persistence.create_character(session.account_id, save) == 0:
			error = persistence.last_error
		else:
			_characters_created += 1
			characters = _characters(session)
			print("[server] account %s made %s (%s)" % [session.account_name, character_name, class_id])
	if not error.is_empty():
		_refused += 1
	_receive_characters.rpc_id(peer, error, characters)


@rpc("any_peer", "call_remote", "reliable")
func _request_play(character_id: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var session: Session = _sessions.get(peer)
	if session == null or session.account_id == 0 or session.character_id != 0:
		return
	for entry in _characters(session):
		if entry["id"] == character_id and ClassDef.for_id(entry["class_id"]) != null:
			session.character_id = character_id
			session.character_name = entry["name"]
			session.class_id = entry["class_id"]
			_plays += 1
			_send_names(peer, session.character_name)
			_receive_play.rpc_id(peer, "")
			return
	_refused += 1
	_receive_play.rpc_id(peer, "That character can't be played.")


## Server: the new player gets everyone's name, everyone else gets its.
func _send_names(peer: int, character_name: String) -> void:
	names.put(peer, character_name)
	for other in names.peers():
		if other != peer and Net.is_peer_connected(other):
			_receive_name.rpc_id(other, peer, character_name)
	_receive_names.rpc_id(peer, names.to_dict())


func _characters(session: Session) -> Array:
	var result := []
	for entry in persistence.list_characters(session.account_id):
		result.append({"id": entry["id"], "name": entry["name"], "class_id": entry["class_id"]})
	return result


# --- Client ---

func login(account_name: String, password: String, create: bool) -> void:
	_request_login.rpc_id(1, account_name, password, create)


func create_character(character_name: String, class_id: String) -> void:
	_request_create_character.rpc_id(1, character_name, class_id)


func play(character_id: int) -> void:
	_request_play.rpc_id(1, character_id)


@rpc("authority", "call_remote", "reliable")
func _receive_login(error: String, account_name: String, characters: Array) -> void:
	if _bot:
		_bot_after_login(error, characters)
	else:
		login_finished.emit(error, account_name, characters)


@rpc("authority", "call_remote", "reliable")
func _receive_characters(error: String, characters: Array) -> void:
	if _bot:
		if not error.is_empty():
			printerr("[client] bot couldn't make its character: %s" % error)
			return
		_bot_choose(characters)
	else:
		characters_changed.emit(error, characters)


@rpc("authority", "call_remote", "reliable")
func _receive_play(error: String) -> void:
	if _bot and not error.is_empty():
		printerr("[client] bot couldn't play: %s" % error)
	play_finished.emit(error)


@rpc("authority", "call_remote", "reliable")
func _receive_names(entries: Dictionary) -> void:
	for peer in names.put_all(entries):
		name_changed.emit(peer)


@rpc("authority", "call_remote", "reliable")
func _receive_name(peer: int, character_name: String) -> void:
	if names.put(peer, character_name):
		name_changed.emit(peer)


@rpc("authority", "call_remote", "reliable")
func _receive_name_removed(peer: int) -> void:
	if names.forget(peer):
		name_changed.emit(peer)


# --- Client: --bot ---

## Logs in (or makes the account), then plays its character (made if missing).
func start_bot() -> void:
	_bot = true
	_bot_tried_create = false
	var peer := multiplayer.get_unique_id()
	_bot_account = LaunchArgs.get_value("account", "bot_%d" % peer)
	_bot_character = LaunchArgs.get_value("character", bot_character_name(peer))
	login(_bot_account, BOT_PASSWORD, false)


func _bot_after_login(error: String, characters: Array) -> void:
	if error.is_empty():
		print("[client] bot logged in as %s" % _bot_account)
		_bot_choose(characters)
	elif not _bot_tried_create:
		_bot_tried_create = true
		login(_bot_account, BOT_PASSWORD, true)
	else:
		printerr("[client] bot couldn't log in: %s" % error)


func _bot_choose(characters: Array) -> void:
	for entry: Dictionary in characters:
		if str(entry["name"]).to_lower() == _bot_character.to_lower():
			print("[client] bot plays %s (%s)" % [entry["name"], entry["class_id"]])
			play(entry["id"])
			return
	var class_id := LaunchArgs.get_value("class", ClassDef.DEFAULT_CLASS)
	if ClassDef.for_id(class_id) == null:
		class_id = ClassDef.DEFAULT_CLASS
	create_character(_bot_character, class_id)


## A letters-only character name for a bot: "Bot" + the peer id's digits as
## letters (0 = a ... 9 = j), so it passes the character name rules.
static func bot_character_name(peer: int) -> String:
	var result := "Bot"
	for digit in str(absi(peer)):
		result += char("a".unicode_at(0) + digit.to_int())
	return result

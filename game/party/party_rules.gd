class_name PartyRules
extends RefCounted
## Parties and party invites. Pure logic with no scene, so it can be unit tested
## (tests/test_party_rules.gd). On the server, PartySystem owns the only instance
## and asks it everything; clients only ever see the views it produces.
##
## Players are peer ids (always positive). Time is in server ticks.
##
## Rules:
## - A player who isn't in a party, or a party's leader, can invite a player who
##   isn't in a party and has no other pending invite (one pending invite per
##   target). Pending invites count toward the size limit.
## - The party is created when the first invite is accepted; the inviter leads it.
## - An invite expires after invite_expiry_ticks. It's only good while its inviter
##   still leads (or is still alone in) the party it was sent from: if the inviter
##   leaves, is kicked, or joins someone else, their pending invites are dropped.
##   A target who joins another party loses its pending invite.
## - Only the leader kicks. When the leader leaves, the member who joined earliest
##   leads. A party left with one member dissolves.
## - A disconnected player leaves their party, and invites to and from them are dropped.
## - Allies: a player is its own ally, party members are allies, and enemies
##   (ids <= 0) are never anyone's ally.

## Results. Anything but DONE means nothing changed.
const DONE := 0
const IS_SELF := 1
const NOT_LEADER := 2
const TARGET_IN_PARTY := 3
const ALREADY_INVITED := 4
const TARGET_HAS_INVITE := 5
const PARTY_FULL := 6
const NO_INVITE := 7
const NOT_IN_PARTY := 8
const NOT_MEMBER := 9
## Short explanations of each result, shown to the player who asked.
const MESSAGES := {
	DONE: "Done.",
	IS_SELF: "You can't do that to yourself.",
	NOT_LEADER: "Only the party leader can do that.",
	TARGET_IN_PARTY: "That player is already in a party.",
	ALREADY_INVITED: "You already invited that player.",
	TARGET_HAS_INVITE: "That player already has an invite pending.",
	PARTY_FULL: "Your party is full.",
	NO_INVITE: "You have no party invite.",
	NOT_IN_PARTY: "You aren't in a party.",
	NOT_MEMBER: "That player isn't in your party.",
}

## Most players in one party, leader included.
var max_size := 5
var invite_expiry_ticks := 1800
## Parties created so far (for the smoke test).
var formed_count := 0

var _next_party_id := 1
## Party id -> member peer ids in join order. The first one leads.
var _members: Dictionary[int, Array] = {}
## Peer id -> party id, for players in a party.
var _party_of: Dictionary[int, int] = {}
## Target peer id -> {"from": inviter, "party": inviter's party id when sent
## (0 = none yet), "expires": tick}.
var _invites: Dictionary[int, Dictionary] = {}
## Peers whose view (view_for) may have changed since the last take_dirty().
var _dirty: Dictionary[int, bool] = {}


static func from_tuning() -> PartyRules:
	var rules := PartyRules.new()
	rules.max_size = Tuning.get_value("party", "party", "max_size")
	var expiry: float = Tuning.get_value("party", "party", "invite_expiry")
	rules.invite_expiry_ticks = roundi(expiry * Engine.physics_ticks_per_second)
	return rules


# --- Queries ---

## The peer's party id, or 0.
func party_of(peer: int) -> int:
	return _party_of.get(peer, 0)


func is_in_party(peer: int) -> bool:
	return _party_of.has(peer)


## Members of the peer's party in join order (leader first), or [] if none.
func members(peer: int) -> Array[int]:
	var result: Array[int] = []
	if is_in_party(peer):
		result.assign(_members[party_of(peer)])
	return result


## The leader of the peer's party, or 0 if the peer isn't in one.
func leader(peer: int) -> int:
	return _members[party_of(peer)][0] if is_in_party(peer) else 0


func party_count() -> int:
	return _members.size()


## Not in a party, or leading one.
func can_invite(peer: int) -> bool:
	return not is_in_party(peer) or leader(peer) == peer


## The invite waiting for this target, or {} if none.
func invite_for(target: int) -> Dictionary:
	return _invites.get(target, {})


## Targets this peer has invited and who haven't answered yet.
func outgoing_invites(peer: int) -> Array[int]:
	var result: Array[int] = []
	for target: int in _invites:
		if _invites[target]["from"] == peer:
			result.append(target)
	return result


## The single rule for "is b on a's side". Ids are peer ids; enemies are <= 0.
func are_allies(a: int, b: int) -> bool:
	return allied(a, b, members(a))


## are_allies, given the members of a's party ([] if none). Clients, which only
## know their own party, use this directly.
static func allied(a: int, b: int, party_of_a: Array) -> bool:
	if a <= 0 or b <= 0:
		return false
	return a == b or b in party_of_a


## What one player is told about their party: members (leader first), leader
## (0 = no party), the invite waiting for them (invite_from 0 = none), invites
## they sent that are still pending, and the size limit.
func view_for(peer: int, now: int) -> Dictionary:
	var invite := invite_for(peer)
	return {
		"members": members(peer),
		"leader": leader(peer),
		"invite_from": invite.get("from", 0),
		"invite_ticks_left": maxi(0, invite.get("expires", now) - now),
		"outgoing": outgoing_invites(peer),
		"max_size": max_size,
	}


## Peers whose view may have changed since the last call; clears the list.
func take_dirty() -> Array[int]:
	var result: Array[int] = []
	result.assign(_dirty.keys())
	_dirty.clear()
	return result


# --- Changes ---

func invite(from: int, target: int, now: int) -> int:
	if from == target:
		return IS_SELF
	if not can_invite(from):
		return NOT_LEADER
	if is_in_party(target):
		return TARGET_IN_PARTY
	if _invites.has(target):
		return ALREADY_INVITED if _invites[target]["from"] == from else TARGET_HAS_INVITE
	if maxi(1, members(from).size()) + outgoing_invites(from).size() >= max_size:
		return PARTY_FULL
	_invites[target] = {"from": from, "party": party_of(from), "expires": now + invite_expiry_ticks}
	_mark([from, target])
	return DONE


func accept(target: int, now: int) -> int:
	var invite := invite_for(target)
	if invite.is_empty():
		return NO_INVITE
	_remove_invite(target)
	if now >= invite["expires"]:
		return NO_INVITE
	var from: int = invite["from"]
	if maxi(1, members(from).size()) >= max_size:
		return PARTY_FULL
	var party_id := party_of(from)
	if party_id == 0:
		party_id = _create_party(from)
	_members[party_id].append(target)
	_party_of[target] = party_id
	_mark(_members[party_id])
	_prune_invites()
	return DONE


func decline(target: int) -> int:
	if not _invites.has(target):
		return NO_INVITE
	_remove_invite(target)
	return DONE


func leave(peer: int) -> int:
	if not is_in_party(peer):
		return NOT_IN_PARTY
	_remove_member(peer)
	_prune_invites()
	return DONE


func kick(by: int, target: int) -> int:
	if not is_in_party(by):
		return NOT_IN_PARTY
	if leader(by) != by:
		return NOT_LEADER
	if target == by:
		return IS_SELF
	if party_of(target) != party_of(by):
		return NOT_MEMBER
	_remove_member(target)
	_prune_invites()
	return DONE


## A player disconnected: leaves their party; invites to and from them are dropped.
func remove_peer(peer: int) -> void:
	if is_in_party(peer):
		_remove_member(peer)
	if _invites.has(peer):
		_remove_invite(peer)
	for target in outgoing_invites(peer):
		_remove_invite(target)
	_prune_invites()
	_dirty.erase(peer)


## Drops invites that have run out by tick `now`. Returns how many.
func expire_invites(now: int) -> int:
	var expired := 0
	for target: int in _invites.keys():
		if now >= _invites[target]["expires"]:
			_remove_invite(target)
			expired += 1
	return expired


# --- Internals ---

func _create_party(leader_peer: int) -> int:
	var party_id := _next_party_id
	_next_party_id += 1
	_members[party_id] = [leader_peer]
	_party_of[leader_peer] = party_id
	formed_count += 1
	# The leader's other invites, sent while alone, now invite into this party.
	for target in outgoing_invites(leader_peer):
		_invites[target]["party"] = party_id
	return party_id


func _remove_member(peer: int) -> void:
	var party_id := party_of(peer)
	var remaining: Array = _members[party_id]
	remaining.erase(peer)
	_party_of.erase(peer)
	_mark([peer])
	_mark(remaining)
	if remaining.size() <= 1:
		for member: int in remaining:
			_party_of.erase(member)
		_members.erase(party_id)


func _remove_invite(target: int) -> void:
	_mark([target, _invites[target]["from"]])
	_invites.erase(target)


## Keeps only invites whose target is still free and whose inviter still leads
## (or is still alone in) the party the invite was sent from.
func _prune_invites() -> void:
	for target: int in _invites.keys():
		var invite: Dictionary = _invites[target]
		var from: int = invite["from"]
		if is_in_party(target) or party_of(from) != invite["party"] or not can_invite(from):
			_remove_invite(target)


func _mark(peers: Array) -> void:
	for peer: int in peers:
		_dirty[peer] = true

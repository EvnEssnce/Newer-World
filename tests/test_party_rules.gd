extends TestCase
## PartyRules: invites, accept/decline, expiry, leave, kick, promotion,
## dissolving, disconnects, size limit, and the ally rule (plus World.are_allies).
## Fixed params, not data/party.cfg. Peers are 1..6; enemies are negative.

const A := 1
const B := 2
const C := 3
const D := 4
const EXPIRY := 100

var rules: PartyRules


func before_each() -> void:
	rules = PartyRules.new()
	rules.max_size = 3
	rules.invite_expiry_ticks = EXPIRY


## A invites and B accepts at tick 0: party [A, B], A leads.
func _pair() -> void:
	assert_eq(rules.invite(A, B, 0), PartyRules.DONE, "invite")
	assert_eq(rules.accept(B, 0), PartyRules.DONE, "accept")


## A leads [A, B, C].
func _trio() -> void:
	_pair()
	assert_eq(rules.invite(A, C, 0), PartyRules.DONE, "invite C")
	assert_eq(rules.accept(C, 0), PartyRules.DONE, "accept C")


# --- Invites ---

func test_invite_alone_creates_no_party_until_accepted() -> void:
	assert_eq(rules.invite(A, B, 0), PartyRules.DONE)
	assert_false(rules.is_in_party(A))
	assert_eq(rules.party_count(), 0)
	assert_eq(rules.invite_for(B)["from"], A)
	assert_eq(rules.outgoing_invites(A), [B] as Array[int])


func test_accept_creates_party_led_by_inviter() -> void:
	_pair()
	assert_eq(rules.party_count(), 1)
	assert_eq(rules.formed_count, 1)
	assert_eq(rules.members(A), [A, B] as Array[int])
	assert_eq(rules.members(B), [A, B] as Array[int])
	assert_eq(rules.leader(B), A)
	assert_true(rules.invite_for(B).is_empty(), "invite used up")


func test_cannot_invite_self() -> void:
	assert_eq(rules.invite(A, A, 0), PartyRules.IS_SELF)


func test_only_leader_invites() -> void:
	_pair()
	assert_eq(rules.invite(B, C, 0), PartyRules.NOT_LEADER)
	assert_true(rules.invite_for(C).is_empty())
	assert_eq(rules.invite(A, C, 0), PartyRules.DONE)


func test_cannot_invite_player_in_a_party() -> void:
	_pair()
	assert_eq(rules.invite(C, B, 0), PartyRules.TARGET_IN_PARTY)
	assert_eq(rules.invite(C, A, 0), PartyRules.TARGET_IN_PARTY)


func test_no_duplicate_pending_invites() -> void:
	assert_eq(rules.invite(A, B, 0), PartyRules.DONE)
	assert_eq(rules.invite(A, B, 5), PartyRules.ALREADY_INVITED)
	assert_eq(rules.invite_for(B)["expires"], EXPIRY, "first invite's expiry unchanged")


func test_one_pending_invite_per_target() -> void:
	assert_eq(rules.invite(A, B, 0), PartyRules.DONE)
	assert_eq(rules.invite(C, B, 0), PartyRules.TARGET_HAS_INVITE)
	assert_eq(rules.invite_for(B)["from"], A)


func test_decline_removes_invite() -> void:
	rules.invite(A, B, 0)
	assert_eq(rules.decline(B), PartyRules.DONE)
	assert_true(rules.invite_for(B).is_empty())
	assert_eq(rules.accept(B, 1), PartyRules.NO_INVITE)
	assert_eq(rules.party_count(), 0)
	assert_eq(rules.invite(A, B, 1), PartyRules.DONE, "can invite again")


func test_answer_without_invite() -> void:
	assert_eq(rules.accept(B, 0), PartyRules.NO_INVITE)
	assert_eq(rules.decline(B), PartyRules.NO_INVITE)


func test_invite_expires() -> void:
	rules.invite(A, B, 0)
	assert_eq(rules.expire_invites(EXPIRY - 1), 0, "still open a tick before")
	assert_false(rules.invite_for(B).is_empty())
	assert_eq(rules.expire_invites(EXPIRY), 1)
	assert_true(rules.invite_for(B).is_empty())
	assert_eq(rules.accept(B, EXPIRY), PartyRules.NO_INVITE)


func test_accept_after_expiry_fails_even_before_sweep() -> void:
	rules.invite(A, B, 0)
	assert_eq(rules.accept(B, EXPIRY), PartyRules.NO_INVITE)
	assert_eq(rules.party_count(), 0)
	assert_true(rules.invite_for(B).is_empty(), "stale invite removed")


func test_solo_inviters_other_invites_carry_into_new_party() -> void:
	rules.invite(A, B, 0)
	rules.invite(A, C, 0)
	assert_eq(rules.accept(B, 0), PartyRules.DONE)
	assert_eq(rules.invite_for(C)["from"], A, "C's invite survives")
	assert_eq(rules.accept(C, 0), PartyRules.DONE)
	assert_eq(rules.members(A), [A, B, C] as Array[int])
	assert_eq(rules.party_count(), 1)


func test_target_joining_another_party_loses_its_invite() -> void:
	rules.invite(A, B, 0)  # B has A's invite pending
	rules.invite(B, C, 0)  # and invites C
	assert_eq(rules.accept(C, 0), PartyRules.DONE)  # B now leads [B, C]
	assert_true(rules.invite_for(B).is_empty(), "A's invite to B dropped")
	assert_eq(rules.accept(B, 0), PartyRules.NO_INVITE)


func test_inviter_joining_another_party_loses_its_invites() -> void:
	rules.invite(A, C, 0)
	rules.invite(B, A, 0)
	assert_eq(rules.accept(A, 0), PartyRules.DONE)  # A joins B's party as a member
	assert_true(rules.invite_for(C).is_empty(), "A no longer leads, so its invite is void")


func test_leaders_invites_dropped_when_they_leave() -> void:
	_trio()
	rules.max_size = 4
	rules.invite(A, D, 0)
	rules.leave(A)
	assert_true(rules.invite_for(D).is_empty())
	assert_eq(rules.accept(D, 0), PartyRules.NO_INVITE)


# --- Size limit ---

func test_full_party_cannot_invite() -> void:
	_trio()
	assert_eq(rules.invite(A, D, 0), PartyRules.PARTY_FULL)


func test_pending_invites_count_toward_size() -> void:
	_pair()
	assert_eq(rules.invite(A, C, 0), PartyRules.DONE)
	assert_eq(rules.invite(A, D, 0), PartyRules.PARTY_FULL, "2 members + 1 pending = 3")
	rules.decline(C)
	assert_eq(rules.invite(A, D, 0), PartyRules.DONE, "room again after the decline")


func test_solo_invites_limited_by_size() -> void:
	assert_eq(rules.invite(A, B, 0), PartyRules.DONE)
	assert_eq(rules.invite(A, C, 0), PartyRules.DONE)
	assert_eq(rules.invite(A, D, 0), PartyRules.PARTY_FULL)


# --- Leave, kick, promotion, dissolve ---

func test_member_leaves() -> void:
	_trio()
	assert_eq(rules.leave(B), PartyRules.DONE)
	assert_false(rules.is_in_party(B))
	assert_eq(rules.members(A), [A, C] as Array[int])
	assert_eq(rules.leader(C), A)


func test_leave_when_not_in_party() -> void:
	assert_eq(rules.leave(A), PartyRules.NOT_IN_PARTY)


func test_leader_leaves_next_member_promoted() -> void:
	_trio()
	assert_eq(rules.leave(A), PartyRules.DONE)
	assert_eq(rules.members(B), [B, C] as Array[int])
	assert_eq(rules.leader(C), B, "earliest-joined member leads")
	assert_eq(rules.invite(B, D, 0), PartyRules.DONE, "new leader can invite")


func test_party_of_one_dissolves_on_leave() -> void:
	_pair()
	rules.leave(B)
	assert_false(rules.is_in_party(A))
	assert_eq(rules.party_count(), 0)
	assert_eq(rules.leader(A), 0)


func test_leader_leaving_pair_dissolves() -> void:
	_pair()
	rules.leave(A)
	assert_false(rules.is_in_party(B))
	assert_eq(rules.party_count(), 0)


func test_leader_kicks_member() -> void:
	_trio()
	assert_eq(rules.kick(A, C), PartyRules.DONE)
	assert_false(rules.is_in_party(C))
	assert_eq(rules.members(A), [A, B] as Array[int])


func test_only_leader_kicks() -> void:
	_trio()
	assert_eq(rules.kick(B, C), PartyRules.NOT_LEADER)
	assert_true(rules.is_in_party(C))


func test_kick_needs_a_member_and_not_self() -> void:
	_pair()
	assert_eq(rules.kick(A, C), PartyRules.NOT_MEMBER)
	assert_eq(rules.kick(A, A), PartyRules.IS_SELF)
	assert_eq(rules.kick(C, A), PartyRules.NOT_IN_PARTY)


func test_kick_to_one_dissolves() -> void:
	_pair()
	rules.kick(A, B)
	assert_eq(rules.party_count(), 0)
	assert_false(rules.is_in_party(A))


# --- Disconnects ---

func test_disconnect_removes_member() -> void:
	_trio()
	rules.remove_peer(C)
	assert_false(rules.is_in_party(C))
	assert_eq(rules.members(A), [A, B] as Array[int])


func test_leader_disconnect_promotes() -> void:
	_trio()
	rules.remove_peer(A)
	assert_eq(rules.leader(B), B)
	assert_eq(rules.members(C), [B, C] as Array[int])


func test_disconnect_dissolves_pair() -> void:
	_pair()
	rules.remove_peer(B)
	assert_eq(rules.party_count(), 0)


func test_disconnect_drops_invites_to_and_from() -> void:
	rules.invite(A, B, 0)
	rules.invite(C, A, 0)
	rules.remove_peer(A)
	assert_true(rules.invite_for(B).is_empty(), "invite from A")
	assert_true(rules.invite_for(A).is_empty(), "invite to A")
	assert_eq(rules.outgoing_invites(C), [] as Array[int])


# --- Views and change tracking ---

func test_view_for_target_and_leader() -> void:
	_pair()
	rules.invite(A, C, 10)
	var leader_view := rules.view_for(A, 30)
	assert_eq(leader_view["members"], [A, B] as Array[int])
	assert_eq(leader_view["leader"], A)
	assert_eq(leader_view["outgoing"], [C] as Array[int])
	assert_eq(leader_view["invite_from"], 0)
	assert_eq(leader_view["max_size"], 3)
	var target_view := rules.view_for(C, 30)
	assert_eq(target_view["members"], [] as Array[int])
	assert_eq(target_view["leader"], 0)
	assert_eq(target_view["invite_from"], A)
	assert_eq(target_view["invite_ticks_left"], 10 + EXPIRY - 30)


func test_changes_mark_affected_peers() -> void:
	rules.invite(A, B, 0)
	var dirty := rules.take_dirty()
	dirty.sort()
	assert_eq(dirty, [A, B] as Array[int])
	assert_eq(rules.take_dirty(), [] as Array[int], "cleared")
	rules.accept(B, 0)
	rules.take_dirty()
	rules.invite(A, C, 0)
	rules.accept(C, 0)
	dirty = rules.take_dirty()
	dirty.sort()
	assert_eq(dirty, [A, B, C] as Array[int], "every member hears about a join")
	rules.leave(C)
	dirty = rules.take_dirty()
	dirty.sort()
	assert_eq(dirty, [A, B, C] as Array[int], "leaver and remaining members")


func test_failed_requests_change_nothing() -> void:
	_pair()
	rules.take_dirty()
	rules.invite(B, C, 0)
	rules.kick(B, A)
	rules.decline(C)
	assert_eq(rules.take_dirty(), [] as Array[int])


# --- Allies ---

func test_player_is_own_ally() -> void:
	assert_true(rules.are_allies(A, A))


func test_party_members_are_allies() -> void:
	_pair()
	assert_true(rules.are_allies(A, B))
	assert_true(rules.are_allies(B, A))


func test_non_members_are_not_allies() -> void:
	_pair()
	assert_false(rules.are_allies(A, C))
	assert_false(rules.are_allies(C, D), "neither in a party")
	rules.invite(C, D, 0)
	assert_false(rules.are_allies(C, D), "a pending invite isn't a party")


func test_separate_parties_are_not_allies() -> void:
	_pair()
	rules.invite(C, D, 0)
	rules.accept(D, 0)
	assert_false(rules.are_allies(A, C))
	assert_false(rules.are_allies(B, D))
	assert_true(rules.are_allies(C, D))


func test_enemies_are_never_allies() -> void:
	_pair()
	assert_false(rules.are_allies(A, -1))
	assert_false(rules.are_allies(-1, A))
	assert_false(rules.are_allies(-1, -1), "not even with itself")
	assert_false(rules.are_allies(-1, -2))
	assert_false(rules.are_allies(0, 0))


func test_allies_no_longer_after_leaving() -> void:
	_pair()
	rules.leave(B)
	assert_false(rules.are_allies(A, B))


func test_world_are_allies_uses_the_party_rules() -> void:
	_pair()
	var world := World.new()
	world.party = PartySystem.new()
	world.party.rules = rules
	assert_true(world.are_allies(A, B))
	assert_true(world.are_allies(C, C))
	assert_false(world.are_allies(A, C))
	assert_false(world.are_allies(A, -1))
	world.party.free()
	world.free()

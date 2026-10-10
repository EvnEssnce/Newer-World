class_name MasteryTree
extends RefCounted
## One weapon's mastery tree (data/mastery_<weapon>.cfg, rules in
## data/mastery.cfg), or a class's Wing tree (data/mastery_wings_<class>.cfg,
## for_wings: 2 slots, its own point budget), and its rules. Pure logic, unit tested
## (tests/test_mastery_tree.gd). An allocation is a list of node ids.
##
## Rules: two branches; a node of tier T needs tier_requirements[T - 1] points
## already spent in its branch on nodes of lower tiers; the total cost can't go
## over `points`. Respecs are free: any valid allocation can replace any other.
## Active nodes unlock abilities; a slot may only hold an unlocked ability.
## Passive and upgrade nodes are server-side modifiers (damage_multiplier,
## block_stamina_multiplier), so they never affect the predicted simulation.

const KIND_ACTIVE := "active"
const KIND_PASSIVE := "passive"
const KIND_UPGRADE := "upgrade"
## An allocation can't list more nodes than this (guards RPC input).
const MAX_NODES := 64


class MasteryNode:
	extends RefCounted
	var id := ""
	var display_name := ""
	var description := ""
	var branch := ""
	## 1-based; the last tier is the capstone.
	var tier := 1
	var kind := KIND_PASSIVE
	var cost := 1
	## Active nodes: the ability it unlocks.
	var ability := ""
	## Passive/upgrade nodes: "damage", "low_health_damage", "block_stamina",
	## "execute_damage", "hold_the_line", "hook_stagger", "crit_staggered",
	## "ability_range", "ramp_on_hit", "backstab_damage", "crit_backstab",
	## "none", or (Wing trees)
	## "damage_taken", "mantle_heal", "surge_stagger", "force_distance",
	## "wall_stun", "roar_guard"; War Hammer: "heavy_shockwave",
	## "heavy_breaks_block".
	var effect := "none"
	## "damage", "crit_staggered", "backstab_damage", "crit_backstab": "light",
	## "heavy", "abilities", "all" or one ability id.
	## "mantle_heal" / "surge_stagger": the Wing ability whose self-buff it needs.
	## "hold_the_line": the internal ability that pokes.
	## "hook_stagger": the mark status it needs (Hooked); "ramp_on_hit": the
	## status each hit adds (Bloodied); "ability_range": the ability.
	var applies_to := ""
	var amount := 0.0
	## "low_health_damage": applies below this fraction of the attacker's max
	## health. "execute_damage": below this fraction of the target's.
	var threshold := 0.0
	## "wall_stun" / "roar_guard": the status (data/status_effects.cfg id) it
	## applies.
	var status := ""


## The weapon id, or "wings_<class>" for a class's Wing tree.
var weapon_id := ""
var branches := PackedStringArray()
var branch_names := PackedStringArray()
var points := 0
## Ability slots an allocation fills: 3 (Q / E / R) for a weapon, 2 (Z / C)
## for Wings.
var slot_count := PlayerState.ABILITY_SLOTS
## Points needed in a branch (on lower tiers) to open each tier, from tier 1.
var tier_requirements := PackedInt32Array()
## Node id -> MasteryNode.
var nodes: Dictionary = {}
## Node ids in file order.
var node_order := PackedStringArray()
var default_nodes := PackedStringArray()
## Ability ids per slot ("" = empty).
var default_slots := PackedStringArray()

static var _cache: Dictionary[String, MasteryTree] = {}


## The tree for a weapon, loaded once; null if it has no mastery file.
static func for_weapon(weapon: String) -> MasteryTree:
	if not _cache.has(weapon):
		if not Tuning.has_file("mastery_" + weapon):
			return null
		_cache[weapon] = from_tuning(weapon)
	return _cache[weapon]


## A class's Wing tree (data/mastery_wings_<class>.cfg, 2 slots), loaded once;
## null if it has none.
static func for_wings(class_id: String) -> MasteryTree:
	var key := "wings_" + class_id
	if not _cache.has(key):
		if not Tuning.has_file("mastery_" + key):
			return null
		var t := from_tuning(key)
		t.slot_count = PlayerState.WING_SLOTS
		_cache[key] = t
	return _cache[key]


## A tree file may set its own [tree] points (the Wing tree does); otherwise
## data/mastery.cfg's.
static func from_tuning(weapon: String) -> MasteryTree:
	var file := "mastery_" + weapon
	var t := MasteryTree.new()
	t.weapon_id = weapon
	t.points = Tuning.get_optional(file, "tree", "points",
			Tuning.get_value("mastery", "rules", "points"))
	t.tier_requirements = PackedInt32Array(Tuning.get_value("mastery", "rules", "tier_requirements"))
	t.branches = PackedStringArray(Tuning.get_value(file, "tree", "branches"))
	t.branch_names = PackedStringArray(Tuning.get_value(file, "tree", "branch_names"))
	t.default_nodes = PackedStringArray(Tuning.get_value(file, "default", "nodes"))
	t.default_slots = PackedStringArray(Tuning.get_value(file, "default", "slots"))
	for section in Tuning.get_sections(file):
		if not section.begins_with("node_"):
			continue
		var n := t.add_node(section.trim_prefix("node_"), Tuning.get_value(file, section, "branch"),
				Tuning.get_value(file, section, "tier"), Tuning.get_value(file, section, "kind"),
				Tuning.get_value(file, section, "cost"),
				Tuning.get_optional(file, section, "ability", ""))
		n.display_name = Tuning.get_value(file, section, "name")
		n.description = Tuning.get_optional(file, section, "description", "")
		n.effect = Tuning.get_optional(file, section, "effect", "none")
		n.applies_to = Tuning.get_optional(file, section, "applies_to", "")
		n.amount = Tuning.get_optional(file, section, "amount", 0.0)
		n.threshold = Tuning.get_optional(file, section, "threshold", 0.0)
		n.status = Tuning.get_optional(file, section, "status", "")
	return t


func add_node(id: String, branch: String, tier: int, kind: String, cost: int,
		ability: String = "") -> MasteryNode:
	var n := MasteryNode.new()
	n.id = id
	n.display_name = id
	n.branch = branch
	n.tier = tier
	n.kind = kind
	n.cost = cost
	n.ability = ability
	nodes[id] = n
	node_order.append(id)
	return n


func get_node(id: String) -> MasteryNode:
	return nodes.get(id)


func tier_count() -> int:
	return tier_requirements.size()


## Total cost of an allocation.
func spent(allocated: PackedStringArray) -> int:
	var total := 0
	for id in allocated:
		var n := get_node(id)
		if n:
			total += n.cost
	return total


## Points spent in a branch on nodes below a tier.
func spent_in_branch(allocated: PackedStringArray, branch: String, below_tier: int = 1 << 20) -> int:
	var total := 0
	for id in allocated:
		var n := get_node(id)
		if n and n.branch == branch and n.tier < below_tier:
			total += n.cost
	return total


func is_tier_open(allocated: PackedStringArray, branch: String, tier: int) -> bool:
	return (tier >= 1 and tier <= tier_count()
			and spent_in_branch(allocated, branch, tier) >= tier_requirements[tier - 1])


## "" if the allocation follows the rules, else why not.
func validate(allocated: PackedStringArray) -> String:
	if allocated.size() > MAX_NODES:
		return "Too many nodes."
	var seen := {}
	for id in allocated:
		var n := get_node(id)
		if n == null:
			return "Unknown node \"%s\"." % id
		if seen.has(id):
			return "%s is listed twice." % n.display_name
		seen[id] = true
		if not (n.branch in branches):
			return "%s is in an unknown branch." % n.display_name
		if not is_tier_open(allocated, n.branch, n.tier):
			return "%s needs %d points in lower tiers of its branch." % [
					n.display_name, tier_requirements[clampi(n.tier - 1, 0, tier_count() - 1)]]
	if spent(allocated) > points:
		return "Not enough points (%d of %d)." % [spent(allocated), points]
	return ""


func can_add(allocated: PackedStringArray, id: String) -> bool:
	if id in allocated:
		return false
	var with := allocated.duplicate()
	with.append(id)
	return validate(with) == ""


## The largest valid part of an allocation, keeping lower tiers first (in their
## listed order): e.g. after removing a node, drops whatever needed it.
func prune(allocated: PackedStringArray) -> PackedStringArray:
	var kept := PackedStringArray()
	for tier in range(1, tier_count() + 1):
		for id in allocated:
			var n := get_node(id)
			if n == null or n.tier != tier or id in kept:
				continue
			var with := kept.duplicate()
			with.append(id)
			if validate(with) == "":
				kept = with
	return kept


## Removes a node and anything that needed it.
func remove(allocated: PackedStringArray, id: String) -> PackedStringArray:
	var without := allocated.duplicate()
	var at := without.find(id)
	if at >= 0:
		without.remove_at(at)
	return prune(without)


## Ability ids unlocked by an allocation's active nodes.
func unlocked_abilities(allocated: PackedStringArray) -> PackedStringArray:
	var abilities := PackedStringArray()
	for id in allocated:
		var n := get_node(id)
		if n and n.kind == KIND_ACTIVE and not n.ability.is_empty():
			abilities.append(n.ability)
	return abilities


## "" if each slot (ability ids, "" = empty) holds a different unlocked ability.
func validate_slots(allocated: PackedStringArray, slots: PackedStringArray) -> String:
	if slots.size() != slot_count:
		return "Expected %d ability slots." % slot_count
	var unlocked := unlocked_abilities(allocated)
	var seen := {}
	for ability in slots:
		if ability.is_empty():
			continue
		if not (ability in unlocked):
			return "%s isn't unlocked." % ability
		if seen.has(ability):
			return "%s is slotted twice." % ability
		seen[ability] = true
	return ""


## Server-side damage modifier from passive and upgrade nodes. attack_kind is
## "light", "heavy" or "ability" (then ability_id says which);
## health_fraction is the attacker's health / max health.
func damage_multiplier(allocated: PackedStringArray, attack_kind: String, ability_id: String,
		health_fraction: float) -> float:
	var bonus := 0.0
	for id in allocated:
		var n := get_node(id)
		if n == null or n.kind == KIND_ACTIVE:
			continue
		match n.effect:
			"damage":
				if covers(n.applies_to, attack_kind, ability_id):
					bonus += n.amount
			"low_health_damage":
				if health_fraction < n.threshold:
					bonus += n.amount
	return maxf(0.0, 1.0 + bonus)


## "execute_damage" nodes (Finishing Thrust): (total amount, threshold) for
## execute_multiplier; the threshold is the largest of them. Zero without one.
func execute_bonus(allocated: PackedStringArray) -> Vector2:
	var result := Vector2.ZERO
	for id in allocated:
		var n := get_node(id)
		if n and n.kind != KIND_ACTIVE and n.effect == "execute_damage":
			result = Vector2(result.x + n.amount, maxf(result.y, n.threshold))
	return result


## Damage multiplier against a target at target_health_fraction (health / max)
## from an execute bonus (amount, threshold): below the threshold it grows
## linearly from 1 at the threshold to 1 + amount at 0 health; 1 above it.
static func execute_multiplier(bonus: Vector2, target_health_fraction: float) -> float:
	if bonus.x <= 0.0 or bonus.y <= 0.0 or target_health_fraction >= bonus.y:
		return 1.0
	var depth := 1.0 - maxf(0.0, target_health_fraction) / bonus.y
	return 1.0 + bonus.x * depth


## True if a node's applies_to ("all", "light", "heavy", "abilities" or an
## ability id) covers an attack (attack_kind "light", "heavy" or "ability",
## then ability_id says which).
static func covers(applies_to: String, attack_kind: String, ability_id: String) -> bool:
	return (applies_to == "all" or applies_to == attack_kind
			or (attack_kind == "ability" and (applies_to == "abilities" or applies_to == ability_id)))


## Crits: crit_damage (the [crit] multiplier, data/combat.cfg) if a node
## covering this attack has its condition: "crit_staggered" (the Halberd's
## Headsman capstone) a target staggered before the hit, "crit_backstab" (the
## Dual Talons' Predator capstone) a backstab (World._is_backstab: from
## behind, or an enemy fighting someone else). Else 1.
func crit_multiplier(allocated: PackedStringArray, attack_kind: String, ability_id: String,
		target_staggered: bool, crit_damage: float, backstab := false) -> float:
	if not target_staggered and not backstab:
		return 1.0
	for id in allocated:
		var n := get_node(id)
		if n == null or n.kind == KIND_ACTIVE or not covers(n.applies_to, attack_kind, ability_id):
			continue
		if ((n.effect == "crit_staggered" and target_staggered)
				or (n.effect == "crit_backstab" and backstab)):
			return crit_damage
	return 1.0


## Damage multiplier on a backstab ("backstab_damage" nodes covering this
## attack: 1 + the sum of their amounts). 1 without one.
func backstab_multiplier(allocated: PackedStringArray, attack_kind: String,
		ability_id: String) -> float:
	var bonus := 0.0
	for id in allocated:
		var n := get_node(id)
		if (n and n.kind != KIND_ACTIVE and n.effect == "backstab_damage"
				and covers(n.applies_to, attack_kind, ability_id)):
			bonus += n.amount
	return 1.0 + bonus


## Hitbox range multiplier for one ability ("ability_range" nodes whose
## applies_to is that ability: Maelstrom doubles Vortex's). 1 = none.
func range_multiplier(allocated: PackedStringArray, ability_id: String) -> float:
	var result := 1.0
	for id in allocated:
		var n := get_node(id)
		if (n and n.kind != KIND_ACTIVE and n.effect == "ability_range"
				and n.applies_to == ability_id and n.amount > 0.0):
			result *= n.amount
	return result


## Server-side multiplier on the stamina a blocked hit costs.
func block_stamina_multiplier(allocated: PackedStringArray) -> float:
	return maxf(0.0, 1.0 + effect_amount(allocated, "block_stamina"))


## Server-side multiplier on damage taken ("damage_taken" nodes: Wing tree).
func damage_taken_multiplier(allocated: PackedStringArray) -> float:
	return maxf(0.0, 1.0 + effect_amount(allocated, "damage_taken"))


## The sum of `amount` over allocated passive/upgrade nodes with this effect
## (and, if applies_to isn't "", that applies_to).
func effect_amount(allocated: PackedStringArray, effect: String, applies_to: String = "") -> float:
	var total := 0.0
	for id in allocated:
		var n := get_node(id)
		if (n and n.kind != KIND_ACTIVE and n.effect == effect
				and (applies_to.is_empty() or n.applies_to == applies_to)):
			total += n.amount
	return total


## The first allocated passive/upgrade node with this effect, or null (Wing
## capstones: mantle_heal, surge_stagger).
func effect_node(allocated: PackedStringArray, effect: String) -> MasteryNode:
	for id in allocated:
		var n := get_node(id)
		if n and n.kind != KIND_ACTIVE and n.effect == effect:
			return n
	return null

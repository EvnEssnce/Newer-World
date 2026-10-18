class_name CharacterBuild
extends RefCounted
## A character's class, equipped weapons, and per weapon its mastery allocation
## and slotted abilities. Pure logic, unit tested (tests/test_character_build.gd).
##
## The server owns one per player and validates every change against the class
## and the mastery rules. What affects the simulation (equipped weapons,
## slotted abilities) goes into PlayerState with apply_to_state(); passive and
## upgrade modifiers stay server-side. Clients get a copy (to_dict) for the UI.

## point_limit's key for the Wing tree (weapon ids never start with "_").
const WING_TREE := "_wings"

var class_def: ClassDef
## Equipped weapon ids, one per weapon slot.
var weapons := PackedStringArray()
## Weapon id -> MasteryTree, for every weapon of the class that has one.
var trees: Dictionary = {}
## Weapon id -> allocated node ids (PackedStringArray).
var allocated: Dictionary = {}
## Weapon id -> ability id per ability slot ("" = empty) (PackedStringArray).
var slots: Dictionary = {}
## The class's Wing tree (null = no Wings), its allocation, and the Wing ability
## ids in slots Z and C ("" = empty).
var wing_tree: MasteryTree
var wing_nodes := PackedStringArray()
var wing_slots := PackedStringArray(["", ""])
## The point pool the character's level gives (CharacterBuild.set_point_pool):
## every tree (the Wing tree and each weapon's) spends from it, each still
## within its own budget. < 0 = no pool (each tree's full budget). Never saved:
## the server sets it from Progression on join and on every level-up; clients
## get it with the build.
var point_pool := -1


## A new character's build: the class's default loadout and each tree's
## default allocation and slots (pruned to what's valid, in case the data
## files disagree). class_wing_tree: the class's Wing tree, or null.
static func create(class_def: ClassDef, class_trees: Dictionary,
		class_wing_tree: MasteryTree = null) -> CharacterBuild:
	var b := CharacterBuild.new()
	b.class_def = class_def
	b.trees = class_trees
	b.weapons = class_def.default_loadout.duplicate()
	b.wing_tree = class_wing_tree
	if class_wing_tree:
		b.wing_nodes = class_wing_tree.prune(class_wing_tree.default_nodes)
		if class_wing_tree.validate_slots(b.wing_nodes, class_wing_tree.default_slots) == "":
			b.wing_slots = class_wing_tree.default_slots.duplicate()
	for weapon_id in class_def.weapons:
		var tree: MasteryTree = class_trees.get(weapon_id)
		var nodes := PackedStringArray()
		var weapon_slots := PackedStringArray(["", "", ""])
		if tree:
			nodes = tree.prune(tree.default_nodes)
			if tree.validate_slots(nodes, tree.default_slots) == "":
				weapon_slots = tree.default_slots.duplicate()
		b.allocated[weapon_id] = nodes
		b.slots[weapon_id] = weapon_slots
	return b


## The default build for a class, with its trees loaded from data/.
static func create_default(class_def: ClassDef) -> CharacterBuild:
	var class_trees := {}
	for weapon_id in class_def.weapons:
		var tree := MasteryTree.for_weapon(weapon_id)
		if tree:
			class_trees[weapon_id] = tree
	return create(class_def, class_trees, MasteryTree.for_wings(class_def.id))


## Equips other weapons (one per weapon slot). "" on success, else why not.
func set_weapons(loadout: PackedStringArray) -> String:
	var error := class_def.validate_loadout(loadout)
	if error.is_empty():
		weapons = loadout.duplicate()
	return error


## `current` (weapon ids, one per weapon slot) with weapon_id put in weapon
## slot `slot`. Picking the weapon that's in the other slot swaps the two, so
## the pair stays distinct. For the K panel's weapon pickers.
static func loadout_with(current: PackedStringArray, slot: int, weapon_id: String) -> PackedStringArray:
	var result := current.duplicate()
	if slot < 0 or slot >= result.size():
		return result
	var other := result.find(weapon_id)
	if other >= 0 and other != slot:
		result[other] = result[slot]
	result[slot] = weapon_id
	return result


## Replaces a weapon's whole allocation and slots (a free respec). "" on
## success, else why not (nothing changes then).
func set_mastery(weapon_id: String, nodes: PackedStringArray, new_slots: PackedStringArray) -> String:
	if not class_def.allows_weapon(weapon_id):
		return "A %s can't use %s." % [class_def.display_name, weapon_id]
	var tree: MasteryTree = trees.get(weapon_id)
	if tree == null:
		return "%s has no mastery tree." % weapon_id
	var error := tree.validate(nodes, point_limit(weapon_id))
	if error.is_empty():
		error = tree.validate_slots(nodes, new_slots)
	if error.is_empty():
		allocated[weapon_id] = nodes.duplicate()
		slots[weapon_id] = new_slots.duplicate()
	return error


## Points spent across every tree (the Wing tree and each weapon's).
func points_spent() -> int:
	var total := wing_tree.spent(wing_nodes) if wing_tree else 0
	for weapon_id: String in trees:
		total += (trees[weapon_id] as MasteryTree).spent(get_allocated(weapon_id))
	return total


## Points of the pool not spent yet (< 0 = no pool).
func points_left() -> int:
	return -1 if point_pool < 0 else maxi(0, point_pool - points_spent())


## The most a weapon's tree may spend for this character: what it spends now
## plus the pool's unspent points (< 0 = its full budget; MasteryTree's limit).
## WING_TREE for the Wing tree.
func point_limit(weapon_id: String) -> int:
	if point_pool < 0:
		return -1
	var tree: MasteryTree = wing_tree if weapon_id == WING_TREE else trees.get(weapon_id)
	var nodes := wing_nodes if weapon_id == WING_TREE else get_allocated(weapon_id)
	return (tree.spent(nodes) if tree else 0) + points_left()


## Sets the pool the character's level gives (< 0 = none) and, if the build
## spends more, cuts it down to the pool (a free respec): nodes are taken back
## one per tree per round, in this order: the Wing tree, the weapon out first,
## the other equipped weapon, the rest; in each tree the slotted abilities'
## nodes first, then the others in their listed order (MasteryTree.fit_order),
## every tree within its own rules. Slots whose ability is no longer learned are
## emptied. Returns a line per tree that lost points ("spear: 18 -> 4 points").
func set_point_pool(pool: int) -> PackedStringArray:
	point_pool = pool
	var cut := PackedStringArray()
	if pool < 0 or points_spent() <= pool:
		return cut
	var order := PackedStringArray()
	if wing_tree:
		order.append(WING_TREE)
	for weapon_id in weapons:
		if trees.has(weapon_id) and not (weapon_id in order):
			order.append(weapon_id)
	for weapon_id: String in trees:
		if not (weapon_id in order):
			order.append(weapon_id)
	var candidates := {}
	var kept := {}
	for key in order:
		var tree := _tree_of(key)
		candidates[key] = tree.fit_order(_nodes_of(key), _slots_of(key))
		kept[key] = PackedStringArray()
	var spent := 0
	var progress := true
	while progress:
		progress = false
		for key in order:
			var tree := _tree_of(key)
			for id: String in candidates[key]:
				var n := tree.get_node(id)
				if id in kept[key] or n == null or spent + n.cost > pool:
					continue
				var with: PackedStringArray = kept[key].duplicate()
				with.append(id)
				if tree.validate(with) == "":
					kept[key] = with
					spent += n.cost
					progress = true
					break  # one node per tree per round
	for key in order:
		var tree := _tree_of(key)
		var before := _nodes_of(key)
		if kept[key].size() == before.size():
			continue
		cut.append("%s: %d -> %d points" % [key, tree.spent(before), tree.spent(kept[key])])
		var unlocked := tree.unlocked_abilities(kept[key])
		var kept_slots := _slots_of(key).duplicate()
		for i in kept_slots.size():
			if not (kept_slots[i] in unlocked):
				kept_slots[i] = ""
		if key == WING_TREE:
			wing_nodes = kept[key]
			wing_slots = kept_slots
		else:
			allocated[key] = kept[key]
			slots[key] = kept_slots
	return cut


func _tree_of(key: String) -> MasteryTree:
	return wing_tree if key == WING_TREE else trees[key]


func _nodes_of(key: String) -> PackedStringArray:
	return wing_nodes if key == WING_TREE else get_allocated(key)


func _slots_of(key: String) -> PackedStringArray:
	return wing_slots if key == WING_TREE else get_slots(key)


func get_allocated(weapon_id: String) -> PackedStringArray:
	return allocated.get(weapon_id, PackedStringArray())


func get_slots(weapon_id: String) -> PackedStringArray:
	return slots.get(weapon_id, PackedStringArray(["", "", ""]))


## PlayerState.ability_slots for the equipped weapons: ability-pool indices.
func state_slots(params: PlayerParams) -> PackedInt32Array:
	var result := PackedInt32Array()
	for weapon_slot in PlayerState.WEAPON_SLOTS:
		var weapon_id := weapons[weapon_slot] if weapon_slot < weapons.size() else ""
		var weapon_slots := get_slots(weapon_id)
		var weapon := params.weapon(weapon_id)
		for slot in PlayerState.ABILITY_SLOTS:
			var ability_id := weapon_slots[slot] if slot < weapon_slots.size() else ""
			var index := -1 if ability_id.is_empty() else weapon.ability_index(ability_id)
			if index >= 0 and weapon.abilities[index].internal:
				index = -1
			result.append(index)
	return result


## Puts the equipped weapons, slotted abilities and Wing slots into the
## simulated state.
func apply_to_state(state: PlayerState, params: PlayerParams) -> void:
	state.set_loadout(weapons, state_slots(params))
	state.set_wings(wing_set_id(), wing_state_slots(params))
	state.set_free_move(free_move_mask())
	state.set_charge_mask(charge_mask(params))


## PlayerState.charge_mask from the Wing tree's "extra_charge" nodes:
## applies_to "roll" (Second Wind) sets bit 0, a Wing ability id (Second Step:
## Ashstep) bit 1 + its pool index. Like free_draw, it reaches the sim through
## apply_to_state.
func charge_mask(params: PlayerParams) -> int:
	if wing_tree == null:
		return 0
	var mask := 0
	var pool := params.wing_set(wing_set_id())
	for id in wing_nodes:
		var n := wing_tree.get_node(id)
		if n == null or n.kind == MasteryTree.KIND_ACTIVE or n.effect != "extra_charge":
			continue
		if n.applies_to == "roll":
			mask |= 1
		elif pool and pool.ability_index(n.applies_to) >= 0:
			mask |= 1 << (1 + pool.ability_index(n.applies_to))
	return mask


## Bit per weapon slot whose tree has a "free_draw" node (the Longbow's
## Skirmisher capstone: its light and heavy attacks don't slow walking). The
## one tree effect that reaches the sim, through apply_to_state like slots.
func free_move_mask() -> int:
	var mask := 0
	for slot in mini(weapons.size(), PlayerState.WEAPON_SLOTS):
		if weapon_effect(weapons[slot], "free_draw"):
			mask |= 1 << slot
	return mask


## Weapon (or Wing) damage modifiers from the trees, for one of the player's
## attacks. weapon_id "" = a Wing ability (the weapon tree doesn't apply). The
## Wing tree's passives apply to every attack.
func damage_multiplier(weapon_id: String, attack_kind: String, ability_id: String,
		health_fraction: float) -> float:
	var result := 1.0
	var tree: MasteryTree = trees.get(weapon_id)
	if tree:
		result *= tree.damage_multiplier(get_allocated(weapon_id), attack_kind, ability_id,
				health_fraction)
	if wing_tree:
		result *= wing_tree.damage_multiplier(wing_nodes, attack_kind, ability_id, health_fraction)
	return result


## The weapon tree's execute bonus (amount, threshold) for that weapon's
## attacks (MasteryTree.execute_bonus / execute_multiplier); zero for a Wing
## ability (weapon_id "") or without one.
func execute_bonus(weapon_id: String) -> Vector2:
	var tree: MasteryTree = trees.get(weapon_id)
	return tree.execute_bonus(get_allocated(weapon_id)) if tree else Vector2.ZERO


## The weapon tree's crit multiplier for one of that weapon's attacks on a
## target (MasteryTree.crit_multiplier); 1 without a crit node.
func crit_multiplier(weapon_id: String, attack_kind: String, ability_id: String,
		target_staggered: bool, crit_damage: float, backstab := false) -> float:
	var tree: MasteryTree = trees.get(weapon_id)
	if tree == null:
		return 1.0
	return tree.crit_multiplier(get_allocated(weapon_id), attack_kind, ability_id,
			target_staggered, crit_damage, backstab)


## The weapon tree's backstab damage multiplier for one of that weapon's
## attacks (MasteryTree.backstab_multiplier); 1 without one.
func backstab_multiplier(weapon_id: String, attack_kind: String, ability_id: String) -> float:
	var tree: MasteryTree = trees.get(weapon_id)
	return tree.backstab_multiplier(get_allocated(weapon_id), attack_kind, ability_id) if tree else 1.0


## The weapon tree's hitbox range multiplier for one of its abilities
## (MasteryTree.range_multiplier: Maelstrom); 1 without one.
func range_multiplier(weapon_id: String, ability_id: String) -> float:
	var tree: MasteryTree = trees.get(weapon_id)
	return tree.range_multiplier(get_allocated(weapon_id), ability_id) if tree else 1.0


## The allocated passive/upgrade node with this effect in a weapon's tree
## (Hold the Line), or null.
func weapon_effect(weapon_id: String, effect: String) -> MasteryTree.MasteryNode:
	var tree: MasteryTree = trees.get(weapon_id)
	return tree.effect_node(get_allocated(weapon_id), effect) if tree else null


## Tree effects whose node's applies_to names a mark status that only exists
## for that node (Hooked, for Caught on the Hook).
const MARK_EFFECTS: Array[String] = ["hook_stagger"]


## False if status_id is a capstone's mark in this weapon's tree (the
## applies_to of a MARK_EFFECTS node) and no such node is allocated: Hooking
## Pull only marks Hooked with Caught on the Hook. True for any other status.
func applies_mark(weapon_id: String, status_id: String) -> bool:
	var tree: MasteryTree = trees.get(weapon_id)
	if tree == null or status_id.is_empty():
		return true
	var is_mark := false
	var learned := get_allocated(weapon_id)
	for id in tree.node_order:
		var n := tree.get_node(id)
		if n and n.effect in MARK_EFFECTS and n.applies_to == status_id:
			is_mark = true
			if id in learned:
				return true
	return not is_mark


func block_stamina_multiplier(weapon_id: String) -> float:
	var tree: MasteryTree = trees.get(weapon_id)
	var result := tree.block_stamina_multiplier(get_allocated(weapon_id)) if tree else 1.0
	if wing_tree:
		result *= wing_tree.block_stamina_multiplier(wing_nodes)
	return result


# --- Wings ---

## The PlayerState.wing_set id: the class id, or "" without a Wing tree.
func wing_set_id() -> String:
	return class_def.id if wing_tree else ""


## Replaces the Wing tree allocation and the Z / C slots (a free respec). ""
## on success, else why not (nothing changes then).
func set_wing_mastery(nodes: PackedStringArray, new_slots: PackedStringArray) -> String:
	if wing_tree == null:
		return "A %s has no Wing tree." % class_def.display_name
	var error := wing_tree.validate(nodes, point_limit(WING_TREE))
	if error.is_empty():
		error = wing_tree.validate_slots(nodes, new_slots)
	if error.is_empty():
		wing_nodes = nodes.duplicate()
		wing_slots = new_slots.duplicate()
	return error


## PlayerState.wing_slots: Wing-pool indices for Z and C.
func wing_state_slots(params: PlayerParams) -> PackedInt32Array:
	var result := PackedInt32Array()
	var pool := params.wing_set(wing_set_id())
	for slot in PlayerState.WING_SLOTS:
		var ability_id := wing_slots[slot] if slot < wing_slots.size() else ""
		result.append(-1 if ability_id.is_empty() else pool.ability_index(ability_id))
	return result


## Server-side multiplier on damage taken (Wing tree "damage_taken" nodes).
func damage_taken_multiplier() -> float:
	return wing_tree.damage_taken_multiplier(wing_nodes) if wing_tree else 1.0


## The sum of `amount` over allocated Wing-tree nodes with this effect
## ("force_distance"), 0 without a Wing tree.
func wing_effect_amount(effect: String) -> float:
	return wing_tree.effect_amount(wing_nodes, effect) if wing_tree else 0.0


## The allocated Wing-tree node with this effect (capstones), or null.
func wing_effect(effect: String) -> MasteryTree.MasteryNode:
	return wing_tree.effect_node(wing_nodes, effect) if wing_tree else null


# --- Network ---

## with_limits: also the point pool (the owner's copy; saves leave it out, it
## comes from the level).
func to_dict(with_limits := false) -> Dictionary:
	var data := {"class": class_def.id, "weapons": weapons, "allocated": allocated, "slots": slots,
			"wing_nodes": wing_nodes, "wing_slots": wing_slots}
	if with_limits:
		data["point_pool"] = point_pool
	return data


## Puts a saved build (to_dict of the same class) on this one, through the same
## checks as a player's requests, so a save made under older data files can't
## sneak in a build the rules now refuse: each part that fails (the loadout, a
## weapon's tree and slots, the Wing tree and slots) keeps what this build has
## (the class default, for a fresh one). Returns why each refused part failed.
func apply_saved(data: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	if data.has("weapons"):
		var error := set_weapons(_strings(data["weapons"]))
		if not error.is_empty():
			problems.append("weapons: " + error)
	var data_allocated: Variant = data.get("allocated", {})
	var data_slots: Variant = data.get("slots", {})
	if data_allocated is Dictionary and data_slots is Dictionary:
		for weapon_id: Variant in data_allocated:
			if not (weapon_id is String and trees.has(weapon_id)):
				problems.append("%s: no such tree" % weapon_id)
				continue
			var error := set_mastery(weapon_id, _strings(data_allocated[weapon_id]),
					_strings(data_slots.get(weapon_id, ["", "", ""])))
			if not error.is_empty():
				problems.append("%s: %s" % [weapon_id, error])
	if wing_tree and data.has("wing_nodes"):
		var error := set_wing_mastery(_strings(data["wing_nodes"]),
				_strings(data.get("wing_slots", ["", ""])))
		if not error.is_empty():
			problems.append("wings: " + error)
	return problems


## A saved list of ids as a PackedStringArray (empty if it isn't a list).
static func _strings(value: Variant) -> PackedStringArray:
	if value is Array or value is PackedStringArray:
		return PackedStringArray(value)
	return PackedStringArray()


## Rebuilds a server's build on a client (trusted data). Null if the class is unknown.
static func from_dict(data: Dictionary) -> CharacterBuild:
	var class_def := ClassDef.for_id(str(data.get("class", "")))
	if class_def == null:
		return null
	var b := create_default(class_def)
	b.weapons = PackedStringArray(data.get("weapons", b.weapons))
	var data_allocated: Dictionary = data.get("allocated", {})
	var data_slots: Dictionary = data.get("slots", {})
	for weapon_id: String in data_allocated:
		b.allocated[weapon_id] = PackedStringArray(data_allocated[weapon_id])
	for weapon_id: String in data_slots:
		b.slots[weapon_id] = PackedStringArray(data_slots[weapon_id])
	b.wing_nodes = PackedStringArray(data.get("wing_nodes", b.wing_nodes))
	b.wing_slots = PackedStringArray(data.get("wing_slots", b.wing_slots))
	b.point_pool = int(data.get("point_pool", -1))
	return b

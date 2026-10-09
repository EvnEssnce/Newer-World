class_name CharacterBuild
extends RefCounted
## A character's class, equipped weapons, and per weapon its mastery allocation
## and slotted abilities. Pure logic, unit tested (tests/test_character_build.gd).
##
## The server owns one per player and validates every change against the class
## and the mastery rules. What affects the simulation (equipped weapons,
## slotted abilities) goes into PlayerState with apply_to_state(); passive and
## upgrade modifiers stay server-side. Clients get a copy (to_dict) for the UI.

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
	var error := tree.validate(nodes)
	if error.is_empty():
		error = tree.validate_slots(nodes, new_slots)
	if error.is_empty():
		allocated[weapon_id] = nodes.duplicate()
		slots[weapon_id] = new_slots.duplicate()
	return error


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


## The allocated passive/upgrade node with this effect in a weapon's tree
## (Hold the Line), or null.
func weapon_effect(weapon_id: String, effect: String) -> MasteryTree.MasteryNode:
	var tree: MasteryTree = trees.get(weapon_id)
	return tree.effect_node(get_allocated(weapon_id), effect) if tree else null


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
	var error := wing_tree.validate(nodes)
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

func to_dict() -> Dictionary:
	return {"class": class_def.id, "weapons": weapons, "allocated": allocated, "slots": slots,
			"wing_nodes": wing_nodes, "wing_slots": wing_slots}


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
	return b

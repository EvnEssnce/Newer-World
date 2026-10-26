class_name LootRoller
## Rolls loot. Server only. Pure logic driven by a RandomNumberGenerator, so it's
## unit tested (tests/test_loot.gd) and the same seed reproduces the same drops.


## Personal loot for a kill: every player who damaged the enemy (peer ids, in
## order) gets their own roll of the table. Returns peer id -> items, leaving
## out players whose roll dropped nothing. enemy_gear_score: the killed enemy's
## (a relative table's band is around it). item_weights: peer -> that player's
## item weights (class_item_weights); a peer missing from it rolls the table's.
static func roll_kill(table: ItemDatabase.LootTable, db: ItemDatabase, contributors: Array[int],
		rng: RandomNumberGenerator, enemy_gear_score := 100,
		item_weights: Dictionary[int, Dictionary] = {}) -> Dictionary[int, Array]:
	var result: Dictionary[int, Array] = {}
	for peer in contributors:
		var items := roll_table(table, db, rng, enemy_gear_score, item_weights.get(peer, {}))
		if not items.is_empty():
			result[peer] = items
	return result


## One player's drop from a kill: nothing (drop_chance failed), or `rolls` items,
## each with its own item, rarity and gear score.
static func roll_table(table: ItemDatabase.LootTable, db: ItemDatabase,
		rng: RandomNumberGenerator, enemy_gear_score := 100, item_weights := {}) -> Array[Item]:
	if item_weights.is_empty():
		item_weights = table.item_weights
	var drops: Array[Item] = []
	if table.drop_chance < 1.0 and rng.randf() >= table.drop_chance:
		return drops
	for i in table.rolls:
		var item_id := pick_weighted(item_weights, rng)
		var rarity := pick_weighted(table.rarity_weights, rng)
		if item_id.is_empty() or rarity.is_empty():
			continue
		var gear_score := table.roll_gear_score(enemy_gear_score, db.drop_gear_score_floor,
				db.drop_gear_score_ceiling, rng)
		drops.append(roll_item(db.items[item_id], rarity, gear_score, db, rng))
	return drops


## A table's item weights for a player of class_id (its weapon types
## class_weapons): class-locked items (weapons, Wing Enhancements) that class can
## use × own_class, other classes' × other_class; armor (any class) unchanged.
## So drops lean to the killer's class (loot.cfg [drops]).
static func class_item_weights(weights: Dictionary, db: ItemDatabase, class_id: String,
		class_weapons: PackedStringArray, own_class: float, other_class: float) -> Dictionary:
	var result := {}
	for item_id: String in weights:
		var def: ItemDatabase.ItemDef = db.items.get(item_id)
		var weight: float = weights[item_id]
		if def != null and not (def.weapon_type.is_empty() and def.class_id.is_empty()):
			var own := (def.weapon_type.is_empty() or def.weapon_type in class_weapons) \
					and (def.class_id.is_empty() or def.class_id == class_id)
			weight *= own_class if own else other_class
		result[item_id] = weight
	return result


## An item of a known kind, rarity and gear score: its main stat on the gear
## score curve (ItemDatabase.gear), and its affixes rolled: as
## many as the rarity allows (fewer if the slot's pool is smaller, after leaving
## out affixes whose min_rarity this rarity doesn't reach), never the same one
## twice, each value rolled in its range and scaled by gear score / 100.
static func roll_item(def: ItemDatabase.ItemDef, rarity: String, gear_score: int,
		db: ItemDatabase, rng: RandomNumberGenerator) -> Item:
	var item := Item.new()
	item.item_id = def.id
	item.rarity = rarity
	item.gear_score = gear_score
	item.primary_value = def.primary_base * db.gear.factor(gear_score)
	var pool := db.affixes_for_slot(def.slot, rarity)
	var count := mini(db.rarities[rarity].affix_count, pool.size())
	for i in count:
		var index := rng.randi_range(0, pool.size() - 1)
		var affix: ItemDatabase.AffixDef = pool[index]
		pool.remove_at(index)
		var value := rng.randf_range(affix.min_per_100_gs, affix.max_per_100_gs)
		item.affixes[affix.id] = value * gear_score / 100.0
	return item


## A key chosen with probability proportional to its weight. Keys with weight 0
## (or less) are never chosen; returns "" if no key has a positive weight.
static func pick_weighted(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	var last_valid := ""
	for key: String in weights:
		var weight := float(weights[key])
		if weight > 0.0:
			total += weight
			last_valid = key
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for key: String in weights:
		var weight := float(weights[key])
		if weight <= 0.0:
			continue
		if roll < weight:
			return key
		roll -= weight
	return last_valid  # only reachable through float rounding at the very top

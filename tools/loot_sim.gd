extends Node
## Loot simulator: rolls a loot table for many kills and prints what actually
## dropped (rarity spread vs. the weights, items, gear scores, affix values),
## so drop rates can be tuned from numbers. Run with tools\roll_loot.ps1.
##
## Options (after "--"): --table=husk  --kills=50000  --seed=1

func _ready() -> void:
	var table_id := LaunchArgs.get_value("table", "husk")
	var kills := int(LaunchArgs.get_value("kills", "50000"))
	var db := ItemDatabase.from_tuning()
	var problems := db.validate()
	if not problems.is_empty():
		for problem in problems:
			printerr("Item data: " + problem)
		get_tree().quit(1)
		return
	if not db.tables.has(table_id):
		printerr("No loot table '%s'. Tables: %s" % [table_id, ", ".join(db.tables.keys())])
		get_tree().quit(1)
		return
	var table: ItemDatabase.LootTable = db.tables[table_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(LaunchArgs.get_value("seed", "1"))

	var drops: Array[Item] = []
	var kills_with_drop := 0
	for i in kills:
		var dropped := LootRoller.roll_table(table, db, rng)
		if not dropped.is_empty():
			kills_with_drop += 1
		drops.append_array(dropped)

	print("Loot table '%s': %d kills, %d dropped something (%.1f%%), %d items" % [
			table_id, kills, kills_with_drop, 100.0 * kills_with_drop / kills, drops.size()])
	_print_rarities(db, table, drops, kills)
	_print_items(db, table, drops)
	_print_gear_scores(drops)
	_print_affixes(db, drops)
	_print_best(db, drops)
	get_tree().quit()


func _print_rarities(db: ItemDatabase, table: ItemDatabase.LootTable, drops: Array[Item],
		kills: int) -> void:
	print("\nRarity        actual  expected   about 1 in N kills")
	var total_weight := _total(table.rarity_weights)
	for rarity_id in db.rarity_order:
		var count := drops.filter(func(item: Item) -> bool: return item.rarity == rarity_id).size()
		var expected := float(table.rarity_weights.get(rarity_id, 0)) / total_weight
		var one_in := "never" if count == 0 else str(roundi(float(kills) / count))
		print("%-12s %6.2f%%  %6.2f%%   %s" % [db.rarities[rarity_id].name,
				100.0 * count / maxi(drops.size(), 1), 100.0 * expected, one_in])


func _print_items(db: ItemDatabase, table: ItemDatabase.LootTable, drops: Array[Item]) -> void:
	print("\nItem               actual  expected")
	var total_weight := _total(table.item_weights)
	for item_id: String in table.item_weights:
		var count := drops.filter(func(item: Item) -> bool: return item.item_id == item_id).size()
		print("%-17s %6.2f%%  %6.2f%%" % [db.items[item_id].name,
				100.0 * count / maxi(drops.size(), 1),
				100.0 * float(table.item_weights[item_id]) / total_weight])


func _print_gear_scores(drops: Array[Item]) -> void:
	if drops.is_empty():
		return
	var low := 1 << 30
	var high := 0
	var sum := 0
	for item in drops:
		low = mini(low, item.gear_score)
		high = maxi(high, item.gear_score)
		sum += item.gear_score
	print("\nGear score: min %d, average %.1f, max %d" % [low, float(sum) / drops.size(), high])


func _print_affixes(db: ItemDatabase, drops: Array[Item]) -> void:
	print("\nAffix              rolled   min      avg      max")
	var affix_total := 0
	for affix: ItemDatabase.AffixDef in db.affixes.values():
		var values: Array[float] = []
		for item in drops:
			if item.affixes.has(affix.id):
				values.append(item.affixes[affix.id])
		affix_total += values.size()
		if values.is_empty():
			print("%-17s %7d" % [affix.name, 0])
			continue
		var sum := 0.0
		for v in values:
			sum += v
		print("%-17s %7d   %-8s %-8s %s" % [affix.name, values.size(),
				_short(affix.stat, values.min()), _short(affix.stat, sum / values.size()),
				_short(affix.stat, values.max())])
	print("Average affixes per item: %.2f" % (float(affix_total) / maxi(drops.size(), 1)))


func _print_best(db: ItemDatabase, drops: Array[Item]) -> void:
	var best := drops.duplicate()
	best.sort_custom(func(a: Item, b: Item) -> bool:
		var rank_a := db.rarity_order.find(a.rarity)
		var rank_b := db.rarity_order.find(b.rarity)
		return rank_a > rank_b if rank_a != rank_b else a.gear_score > b.gear_score)
	print("\nBest drops:")
	for item in best.slice(0, 5):
		print("  " + item.describe(db))


static func _total(weights: Dictionary) -> float:
	var total := 0.0
	for key in weights:
		total += maxf(0.0, float(weights[key]))
	return maxf(total, 0.000001)


static func _short(stat: String, value: float) -> String:
	return Item.format_stat(stat, value).trim_prefix(stat + " ")

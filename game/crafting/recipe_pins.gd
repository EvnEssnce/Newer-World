class_name RecipePins
extends RefCounted
## The recipes a player pinned (client only, a UI preference kept in
## user://pinned_recipes.cfg, never on the server): shown in the Forge panel's
## Pinned tab and in the HUD's pinned recipe list with what you have of each
## input. Pure logic apart from load/save, unit tested (tests/test_recipe_pins.gd).

const PATH := "user://pinned_recipes.cfg"
## The most recipes pinned at once (the HUD list stays short).
const MAX_PINS := 6

## Pinned recipe ids, oldest first.
var ids := PackedStringArray()


func is_pinned(recipe_id: String) -> bool:
	return recipe_id in ids


## Pins or unpins it. False (nothing changed) when pinning past MAX_PINS.
func toggle(recipe_id: String) -> bool:
	var at := ids.find(recipe_id)
	if at >= 0:
		ids.remove_at(at)
		return true
	if ids.size() >= MAX_PINS:
		return false
	ids.append(recipe_id)
	return true


## Drops pins of recipes that no longer exist (renamed in data/recipes.cfg).
func keep_only(known: Array) -> void:
	var kept := PackedStringArray()
	for id in ids:
		if id in known:
			kept.append(id)
	ids = kept


func save(path := PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("pins", "recipes", ids)
	cfg.save(path)


static func load_from(path := PATH) -> RecipePins:
	var pins := RecipePins.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		for id in PackedStringArray(cfg.get_value("pins", "recipes", PackedStringArray())):
			if pins.ids.size() < MAX_PINS and not id in pins.ids:
				pins.ids.append(id)
	return pins

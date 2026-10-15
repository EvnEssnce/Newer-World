class_name RecipeDefs
extends RefCounted
## Every crafting recipe (data/recipes.cfg) and station kind (data/stations.cfg),
## in simulation units (ticks). Pure data; tests build one by hand (add_recipe,
## add_station). Loaded once, again when Tuning.version moves.
##
## Output kinds: OUTPUT_ITEM makes `output_count` of a fixed item (refining:
## resources). OUTPUT_GEAR is where Milestone 3 item 4 plugs in gear recipes
## (an item rolled through LootRoller, gear score from the skill level): the
## format accepts it, validate() refuses it until CraftingRules can make one.

const RECIPE_PREFIX := "recipe_"
const STATION_PREFIX := "station_"
const OUTPUT_ITEM := "item"
const OUTPUT_GEAR := "gear"
const OUTPUT_KINDS: PackedStringArray = [OUTPUT_ITEM, OUTPUT_GEAR]


## One recipe ([recipe_<id>]).
class Recipe:
	extends RefCounted
	var id := ""
	## "" = the output item's name (display_name).
	var name := ""
	var tradeskill := ""
	var level := 1
	var station := ""
	## Ticks one craft takes (at least 1).
	var craft_ticks := 60
	## Tradeskill XP per craft.
	var xp := 0
	## Item id -> count per craft.
	var inputs: Dictionary[String, int] = {}
	var output_kind := OUTPUT_ITEM
	var output := ""
	var output_count := 1

	## Ticks a batch of `quantity` takes.
	func ticks_for(quantity: int) -> int:
		return maxi(1, craft_ticks * maxi(1, quantity))

	func display_name(db: ItemDatabase) -> String:
		if not name.is_empty():
			return name
		var def: ItemDatabase.ItemDef = db.items.get(output) if db else null
		return def.name if def else output


## One station kind ([station_<kind>]).
class StationDef:
	extends RefCounted
	var id := ""
	var name := ""
	## The prompt's verb ("Use").
	var action := "Use"
	## Meters (horizontal) from its center it can be used from.
	var reach := 3.0
	var visual := ""


static var _current: RecipeDefs
static var _current_version := -1

## Most crafts one request can queue.
var max_batch := 50
## Extra meters the server allows past a station's reach.
var range_tolerance := 0.75
## Recipe id -> Recipe, in file order.
var recipes: Dictionary[String, Recipe] = {}
var stations: Dictionary[String, StationDef] = {}


## The game's recipes and stations, loaded once (again when Tuning.version moves).
static func current() -> RecipeDefs:
	if _current == null or _current_version != Tuning.version:
		_current_version = Tuning.version
		_current = from_tuning()
	return _current


static func from_tuning() -> RecipeDefs:
	var defs := RecipeDefs.new()
	if not Tuning.has_file("recipes"):
		return defs
	var tps := float(Engine.physics_ticks_per_second)
	defs.max_batch = Tuning.get_value("recipes", "crafting", "max_batch")
	defs.range_tolerance = Tuning.get_value("recipes", "crafting", "range_tolerance")
	for section in Tuning.get_sections("recipes"):
		if not section.begins_with(RECIPE_PREFIX):
			continue
		var recipe := defs.add_recipe(section.trim_prefix(RECIPE_PREFIX),
				Tuning.get_value("recipes", section, "tradeskill"),
				Tuning.get_value("recipes", section, "station"))
		recipe.name = Tuning.get_optional("recipes", section, "name", "")
		recipe.level = Tuning.get_value("recipes", section, "level")
		recipe.craft_ticks = maxi(1, roundi(float(Tuning.get_value("recipes", section, "craft_time")) * tps))
		recipe.xp = Tuning.get_value("recipes", section, "xp")
		var inputs: Dictionary = Tuning.get_value("recipes", section, "inputs")
		for item_id: Variant in inputs:
			var count: Variant = inputs[item_id]
			recipe.inputs[str(item_id)] = int(count) if (count is int or count is float) else 0
		recipe.output_kind = Tuning.get_optional("recipes", section, "output_kind", OUTPUT_ITEM)
		recipe.output = Tuning.get_value("recipes", section, "output")
		recipe.output_count = Tuning.get_optional("recipes", section, "output_count", 1)
	if Tuning.has_file("stations"):
		for section in Tuning.get_sections("stations"):
			if not section.begins_with(STATION_PREFIX):
				continue
			var station := defs.add_station(section.trim_prefix(STATION_PREFIX),
					Tuning.get_value("stations", section, "name"))
			station.action = Tuning.get_optional("stations", section, "action", "Use")
			station.reach = Tuning.get_value("stations", section, "range")
			station.visual = Tuning.get_optional("stations", section, "visual", station.id)
	return defs


## Adds a recipe (data loading and tests).
func add_recipe(id: String, tradeskill: String, station: String) -> Recipe:
	var recipe := Recipe.new()
	recipe.id = id
	recipe.tradeskill = tradeskill
	recipe.station = station
	recipes[id] = recipe
	return recipe


## Adds a station kind (data loading and tests).
func add_station(id: String, display_name: String) -> StationDef:
	var station := StationDef.new()
	station.id = id
	station.name = display_name
	stations[id] = station
	return station


func get_recipe(id: String) -> Recipe:
	return recipes.get(id)


func get_station(kind: String) -> StationDef:
	return stations.get(kind)


## The recipes a station kind crafts, in file order.
func recipes_for(station_kind: String) -> Array[Recipe]:
	var result: Array[Recipe] = []
	for recipe: Recipe in recipes.values():
		if recipe.station == station_kind:
			result.append(recipe)
	return result


## Problems with the data against the items and tradeskills, or none (a unit
## test runs it on the real files).
func validate(db: ItemDatabase, skills: TradeskillDefs) -> PackedStringArray:
	var problems := PackedStringArray()
	if max_batch < 1:
		problems.append("[crafting] max_batch must be at least 1")
	if range_tolerance < 0.0:
		problems.append("[crafting] range_tolerance must be >= 0")
	for station: StationDef in stations.values():
		if station.name.is_empty() or station.reach <= 0.0:
			problems.append("station '%s' needs a name and a range above 0" % station.id)
	for recipe: Recipe in recipes.values():
		var where := "recipe '%s'" % recipe.id
		if not skills.has_skill(recipe.tradeskill):
			problems.append("%s: unknown tradeskill '%s'" % [where, recipe.tradeskill])
		elif skills.is_gathering(recipe.tradeskill):
			problems.append("%s: '%s' is a gathering skill" % [where, recipe.tradeskill])
		if recipe.level < Tradeskills.START_LEVEL or recipe.level > skills.level_cap:
			problems.append("%s: level must be %d..%d" % [where, Tradeskills.START_LEVEL, skills.level_cap])
		if not stations.has(recipe.station):
			problems.append("%s: unknown station '%s'" % [where, recipe.station])
		if recipe.craft_ticks < 1 or recipe.xp < 0:
			problems.append("%s: craft_time must be above 0 and xp >= 0" % where)
		if recipe.inputs.is_empty():
			problems.append("%s has no inputs" % where)
		for item_id in recipe.inputs:
			if not db.items.has(item_id):
				problems.append("%s: unknown input '%s'" % [where, item_id])
			elif not db.items[item_id].is_resource():
				problems.append("%s: input '%s' isn't a resource" % [where, item_id])
			if recipe.inputs[item_id] < 1:
				problems.append("%s: input '%s' needs a count of at least 1" % [where, item_id])
			if item_id == recipe.output:
				problems.append("%s uses its own output" % where)
		if not recipe.output_kind in OUTPUT_KINDS:
			problems.append("%s: unknown output_kind '%s'" % [where, recipe.output_kind])
		elif recipe.output_kind == OUTPUT_GEAR:
			problems.append("%s: gear recipes aren't built yet (Milestone 3 item 4)" % where)
		var out: ItemDatabase.ItemDef = db.items.get(recipe.output)
		if out == null:
			problems.append("%s: unknown output '%s'" % [where, recipe.output])
		elif recipe.output_kind == OUTPUT_ITEM:
			if not out.is_resource():
				problems.append("%s: an \"item\" output must be a resource ('%s' isn't)" % [where, recipe.output])
			if recipe.output_count < 1:
				problems.append("%s: output_count must be at least 1" % where)
	return problems

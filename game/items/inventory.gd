class_name Inventory
extends RefCounted
## One player's bag of items (server-owned; the client gets a copy). A fixed
## number of slots; each item gets a uid when added, which requests (discard,
## and equip later) name it by. Gear takes one slot each (add); resources stack
## up to their max_stack per slot (add_stack, count_of, remove_count). Pure
## logic, unit tested (tests/test_inventory.gd, tests/test_gathering.gd).

var capacity := 0
## In the order they were added.
var items: Array[Item] = []
var _next_uid := 1


func _init(slots: int = 0) -> void:
	capacity = slots


func is_full() -> bool:
	return items.size() >= capacity


func free_slots() -> int:
	return maxi(0, capacity - items.size())


## Adds the item and gives it a new uid. False (and unchanged) when full.
func add(item: Item) -> bool:
	if is_full():
		return false
	item.uid = _next_uid
	_next_uid += 1
	items.append(item)
	return true


func get_item(uid: int) -> Item:
	for item in items:
		if item.uid == uid:
			return item
	return null


## Takes the item out and returns it, or null if there's no such uid.
func remove(uid: int) -> Item:
	for i in items.size():
		if items[i].uid == uid:
			var item := items[i]
			items.remove_at(i)
			return item
	return null


## How many more of resource `item_id` fit: room in its stacks plus free slots.
func room_for(item_id: String, max_stack: int) -> int:
	var room := free_slots() * max_stack
	for item in items:
		if item.item_id == item_id:
			room += maxi(0, max_stack - item.count)
	return room


## Adds `amount` of resource `item_id`: tops up its existing stacks first (in
## order), then fills new slots (each a new uid). Returns how many didn't fit
## (0 = all of it); those are simply not added.
func add_stack(item_id: String, amount: int, max_stack: int) -> int:
	var left := amount
	for item in items:
		if left <= 0:
			break
		if item.item_id == item_id and item.count < max_stack:
			var moved := mini(left, max_stack - item.count)
			item.count += moved
			left -= moved
	while left > 0 and not is_full():
		var moved := mini(left, max_stack)
		add(Item.resource(item_id, moved))
		left -= moved
	return left


## How many of `item_id` the bag holds, over all its stacks.
func count_of(item_id: String) -> int:
	var total := 0
	for item in items:
		if item.item_id == item_id:
			total += item.count
	return total


## Takes `amount` of `item_id` out (newest stacks first; emptied stacks free
## their slot). False and unchanged if the bag holds fewer.
func remove_count(item_id: String, amount: int) -> bool:
	if amount <= 0 or count_of(item_id) < amount:
		return amount == 0
	var left := amount
	for i in range(items.size() - 1, -1, -1):
		if left == 0:
			break
		var item := items[i]
		if item.item_id != item_id:
			continue
		var taken := mini(left, item.count)
		item.count -= taken
		left -= taken
		if item.count == 0:
			items.remove_at(i)
	return true


## Item.to_dict() of each, in order: what the server sends its owner.
func to_array() -> Array:
	var data := []
	for item in items:
		data.append(item.to_dict())
	return data


static func items_from_array(data: Array) -> Array[Item]:
	var result: Array[Item] = []
	for entry: Dictionary in data:
		result.append(Item.from_dict(entry))
	return result

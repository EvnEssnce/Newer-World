class_name CraftProgress
extends RefCounted
## The craft under way, as the crafting panel shows it (client), and the rules
## that stop one (server). Pure, unit tested.
##
## A batch is one lock of `each_ticks` x `quantity` (RecipeDefs.Recipe.ticks_for),
## so its progress is the lock's: the bar fills over the whole batch, and the
## piece being made is the one the elapsed time has reached ("3 / 5").

## Moves shorter than this (stick noise) don't cancel a craft.
const MOVE_DEADZONE := 0.1
## Input bits that count as moving (besides the move direction).
const MOVE_BUTTONS := PlayerState.BUTTON_JUMP | PlayerState.BUTTON_DODGE

var recipe_id := ""
var quantity := 1
## The whole lock (ticks) and one piece's share of it.
var total_ticks := 1
var each_ticks := 1


func _init(recipe := "", count := 1, total := 1, each := 1) -> void:
	recipe_id = recipe
	quantity = maxi(1, count)
	total_ticks = maxi(1, total)
	each_ticks = maxi(1, each)


## How far along the batch is (0..1) with `ticks_left` of the lock to go.
func fraction(ticks_left: int) -> float:
	return clampf(1.0 - float(ticks_left) / float(total_ticks), 0.0, 1.0)


## The piece being made (1..quantity) with `ticks_left` to go.
func piece(ticks_left: int) -> int:
	var elapsed := clampi(total_ticks - ticks_left, 0, total_ticks)
	return clampi(elapsed / each_ticks + 1, 1, quantity)


## Seconds left (never negative).
func seconds_left(ticks_left: int, ticks_per_second: int) -> float:
	return maxf(0.0, float(ticks_left)) / float(maxi(1, ticks_per_second))


## The panel's line under the bar: "3 / 5   1.4 s left" (no count for one piece).
func status_text(ticks_left: int, ticks_per_second: int) -> String:
	var time := "%.1f s left" % seconds_left(ticks_left, ticks_per_second)
	if quantity <= 1:
		return time
	return "%d / %d   %s" % [piece(ticks_left), quantity, time]


## Ticks left from the client's own clock: `elapsed_ticks` since the server's
## start message (used until the predicted lock shows up).
func ticks_left_after(elapsed_ticks: int) -> int:
	return clampi(total_ticks - elapsed_ticks, 0, total_ticks)


## Server: whether an input moves the player (any move direction past the dead
## zone, a jump or a dodge), which cancels a craft: crafting means standing at
## the station with its panel open.
static func is_moving(move: Vector2, buttons: int) -> bool:
	return move.length() > MOVE_DEADZONE or (buttons & MOVE_BUTTONS) != 0


## Server: whole pieces finished when a batch stops with `ticks_left` of its
## `total_ticks` lock to go (`each_ticks` per piece): those are still made.
static func pieces_done(total_ticks: int, ticks_left: int, each_ticks: int, quantity: int) -> int:
	var elapsed := clampi(total_ticks - ticks_left, 0, total_ticks)
	return clampi(elapsed / maxi(1, each_ticks), 0, maxi(0, quantity))


## Client: whether moving closes the station panel now. `armed` turns true once
## the player has stood still with it open, so the move that walked up to the
## station (still held as F opened it) doesn't close it at once.
static func move_closes(armed: bool, moving: bool) -> bool:
	return armed and moving


## Client: whether closing the panel (or it being closed) must ask the server to
## cancel: a craft is under way, or one was asked for and hasn't been answered.
static func cancel_on_close(crafting: bool, request_pending: bool) -> bool:
	return crafting or request_pending

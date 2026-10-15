class_name ItemIcon
extends Control
## An item's symbol, drawn in code (no art files): a small dark tile with an
## edge and glyph in the item's rarity colour (resources: a neutral one), and
## an anvil badge in the corner for crafted gear. Which symbol comes from the
## item data (ItemDef.icon_id(): items.cfg `icon`, or the slot and the weapon
## file's `ranged`). Used by the inventory's cards and the loot feed;
## EquipmentSummary draws its slot symbols with draw_glyph too.

## Glyph and edge colour of resources (they have no rarity).
const RESOURCE_COLOR := Color(0.8, 0.76, 0.68)
const EMPTY_COLOR := Color(0.4, 0.4, 0.45)
## The crafted badge (an anvil).
const CRAFTED_COLOR := Color(1.0, 0.8, 0.4)

## One of ItemDatabase.ICONS (or "" for a blank tile).
var icon := ""
var color := EMPTY_COLOR
## False draws the dim "empty slot" look.
var filled := true
var crafted := false


## A tile for `item` (null: an empty tile showing `empty_icon`), `side` px square.
static func for_item(item: Item, db: ItemDatabase, side: float, empty_icon := "") -> ItemIcon:
	var tile := ItemIcon.new()
	tile.custom_minimum_size = Vector2(side, side)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the card shows the tooltip
	if item == null:
		tile.icon = empty_icon
		tile.filled = false
		return tile
	var def: ItemDatabase.ItemDef = db.items.get(item.item_id)
	tile.icon = def.icon_id() if def else ""
	tile.color = RESOURCE_COLOR if def == null or def.is_resource() else item.rarity_color(db)
	tile.crafted = item.crafted
	return tile


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	var back := Color(color, 0.2) if filled else Color(0.05, 0.05, 0.07, 0.6)
	draw_rect(box, Color(0.04, 0.045, 0.06, 0.9))
	draw_rect(box, back)
	draw_rect(box.grow(-0.5), Color(color, 0.95 if filled else 0.6), false, 1.0)
	var glyph := color.lightened(0.25) if filled else Color(EMPTY_COLOR, 0.8)
	var pad := maxf(1.0, size.x * 0.08)
	draw_set_transform(Vector2(pad, pad), 0.0, (size - Vector2(pad, pad) * 2.0) / 24.0)
	draw_glyph(self, icon, glyph, back)
	draw_set_transform(Vector2.ZERO)
	if crafted:
		_draw_anvil_badge()


## An anvil in a dark disc over the bottom-right corner.
func _draw_anvil_badge() -> void:
	var r := clampf(size.x * 0.3, 6.0, 11.0)
	var center := size - Vector2(r, r) + Vector2(1, 1)
	draw_circle(center, r, Color(0.06, 0.05, 0.03, 0.95))
	draw_circle(center, r, CRAFTED_COLOR, false, 1.0)
	# The anvil on a 14 x 9 grid around the disc's centre: a pointed horn on
	# the left, a flat face, a waist and a wide foot.
	var s := r / 8.5
	var o := center - Vector2(7, 4.5) * s
	var points := PackedVector2Array()
	for p: Vector2 in [Vector2(0, 0.4), Vector2(4.5, 0), Vector2(14, 0), Vector2(14, 3),
			Vector2(10, 3), Vector2(9.5, 5.5), Vector2(12, 7), Vector2(12, 9), Vector2(3.5, 9),
			Vector2(3.5, 7), Vector2(6, 5.5), Vector2(5.5, 3), Vector2(3.5, 2.6)]:
		points.append(o + p * s)
	draw_colored_polygon(points, CRAFTED_COLOR)


## Draws symbol `icon` on a 24 x 24 grid (the caller sets the transform).
## `back` is the tile's colour behind it (for cut-outs).
static func draw_glyph(ci: CanvasItem, icon: String, glyph: Color, back: Color) -> void:
	var dark := Color(back.darkened(0.6), 1.0)
	match icon:
		"sword":  # one blade (an empty weapon slot)
			ci.draw_line(Vector2(5, 19), Vector2(17, 7), glyph, 2.5)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(16, 5), Vector2(19, 5),
					Vector2(19, 8), Vector2(17, 7)]), glyph)
			ci.draw_line(Vector2(4, 14), Vector2(10, 20), glyph, 2.0)
		"melee":  # crossed swords
			for flip in [false, true]:
				var f := func(p: Vector2) -> Vector2: return Vector2(24.0 - p.x, p.y) if flip else p
				ci.draw_line(f.call(Vector2(7, 17)), f.call(Vector2(20.5, 3.5)), glyph, 2.2)  # blade
				ci.draw_line(f.call(Vector2(7, 17)), f.call(Vector2(4, 20)), glyph, 1.4)  # grip
				ci.draw_line(f.call(Vector2(5, 15)), f.call(Vector2(9, 19)), glyph, 2.2)  # guard
				ci.draw_circle(f.call(Vector2(3.5, 20.5)), 1.3, glyph)  # pommel
		"ranged":  # a bow with an arrow
			ci.draw_arc(Vector2(1, 12), 11.5, -1.1, 1.1, 12, glyph, 2.2)  # limbs
			var tip := Vector2(1, 12) + Vector2.from_angle(1.1) * 11.5
			ci.draw_line(Vector2(tip.x, 24.0 - tip.y), tip, glyph, 0.8)  # string
			ci.draw_line(Vector2(4, 12), Vector2(19, 12), glyph, 1.5)  # shaft
			ci.draw_colored_polygon(PackedVector2Array([Vector2(23, 12), Vector2(18.5, 9.5),
					Vector2(18.5, 14.5)]), glyph)  # head
			ci.draw_line(Vector2(4, 12), Vector2(2, 9.5), glyph, 1.2)  # fletching
			ci.draw_line(Vector2(4, 12), Vector2(2, 14.5), glyph, 1.2)
		"head":  # helmet
			var dome := PackedVector2Array()
			for i in 9:
				dome.append(Vector2(12, 14) + Vector2.from_angle(PI + PI * i / 8.0) * 8.0)
			ci.draw_colored_polygon(dome, glyph)
			ci.draw_rect(Rect2(3, 14, 18, 3), glyph)  # brim
			ci.draw_rect(Rect2(11, 7, 2, 7), dark)  # nose guard gap
		"chest":  # chestplate
			ci.draw_colored_polygon(PackedVector2Array([Vector2(8, 4), Vector2(10, 4),
					Vector2(12, 7), Vector2(14, 4), Vector2(16, 4), Vector2(21, 8),
					Vector2(18, 12), Vector2(17, 11), Vector2(17, 20), Vector2(7, 20),
					Vector2(7, 11), Vector2(6, 12), Vector2(3, 8)]), glyph)
		"legs":  # legwear
			ci.draw_rect(Rect2(6, 4, 12, 4), glyph)  # belt
			ci.draw_colored_polygon(PackedVector2Array([Vector2(6, 9), Vector2(11.5, 9),
					Vector2(10.5, 21), Vector2(6, 21)]), glyph)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(12.5, 9), Vector2(18, 9),
					Vector2(18, 21), Vector2(13.5, 21)]), glyph)
		"wings":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(11, 9), Vector2(5, 4),
					Vector2(2, 8), Vector2(3, 14), Vector2(6, 18), Vector2(11, 14)]), glyph)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(13, 9), Vector2(19, 4),
					Vector2(22, 8), Vector2(21, 14), Vector2(18, 18), Vector2(13, 14)]), glyph)
			ci.draw_circle(Vector2(12, 11), 1.6, glyph)
		"ore":  # a rough chunk with veins
			ci.draw_colored_polygon(PackedVector2Array([Vector2(3, 15), Vector2(6, 8),
					Vector2(12, 4), Vector2(18, 6), Vector2(21, 12), Vector2(19, 19),
					Vector2(11, 21), Vector2(5, 19)]), glyph)
			ci.draw_line(Vector2(7, 11), Vector2(11, 13), dark, 1.2)
			ci.draw_line(Vector2(11, 13), Vector2(10, 17), dark, 1.2)
			ci.draw_line(Vector2(14, 8), Vector2(17, 13), dark, 1.2)
			ci.draw_circle(Vector2(15, 16), 1.3, dark)
		"ingot":  # a bar: front face, lighter top
			ci.draw_colored_polygon(PackedVector2Array([Vector2(2, 19), Vector2(22, 19),
					Vector2(19, 12), Vector2(5, 12)]), glyph)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(5, 12), Vector2(19, 12),
					Vector2(17, 8), Vector2(7, 8)]), glyph.lightened(0.35))
			ci.draw_line(Vector2(5, 12), Vector2(19, 12), dark, 0.8)
		"log":  # a log with its cut end showing rings
			ci.draw_rect(Rect2(4, 7, 14, 10), glyph)
			ci.draw_circle(Vector2(4, 12), 5.0, glyph)
			ci.draw_line(Vector2(5, 10), Vector2(14, 10), dark, 0.8)  # bark
			ci.draw_line(Vector2(3, 14.5), Vector2(12, 14.5), dark, 0.8)
			ci.draw_circle(Vector2(18, 12), 5.0, glyph.lightened(0.35))
			ci.draw_circle(Vector2(18, 12), 3.0, dark, false, 0.8)
			ci.draw_circle(Vector2(18, 12), 0.9, dark)
		"plank":  # two boards with grain
			for board: Rect2 in [Rect2(2, 6, 20, 5), Rect2(2, 13, 20, 5)]:
				ci.draw_rect(board, glyph)
				var y := board.position.y + board.size.y * 0.5
				ci.draw_line(Vector2(5, y), Vector2(13, y), dark, 0.8)
				ci.draw_circle(Vector2(18, y), 0.8, dark)
		"fiber":  # a wheat-like stalk
			ci.draw_line(Vector2(12, 22), Vector2(12, 5), glyph, 1.2)
			for i in 4:
				var y := 7.0 + i * 3.4
				for side in [-1.0, 1.0]:
					ci.draw_colored_polygon(PackedVector2Array([Vector2(12, y + 2.0),
							Vector2(12 + side * 2.0, y + 1.6), Vector2(12 + side * 4.0, y - 1.6),
							Vector2(12 + side * 1.0, y - 0.4)]), glyph)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(12, 1.5), Vector2(13.4, 4.5),
					Vector2(12, 7), Vector2(10.6, 4.5)]), glyph)
			ci.draw_line(Vector2(12, 20), Vector2(7, 16), glyph, 1.0)  # leaf
		"cloth":  # a folded stack
			for i in 3:
				var fold := Rect2(3 + i, 15 - i * 5, 18 - i * 2, 5)
				ci.draw_rect(fold, glyph if i % 2 == 0 else glyph.lightened(0.25))
				ci.draw_circle(Vector2(fold.position.x, fold.position.y + 2.5), 2.5,
						glyph.darkened(0.15))  # the folded edge
				ci.draw_line(fold.position, fold.position + Vector2(fold.size.x, 0), dark, 0.8)
		_:  # unknown: a question mark
			ci.draw_string(ThemeDB.fallback_font, Vector2(7, 19), "?", HORIZONTAL_ALIGNMENT_LEFT,
					-1, 18, glyph)

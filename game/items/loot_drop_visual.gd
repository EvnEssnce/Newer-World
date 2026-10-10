class_name LootDropVisual
extends Node3D
## Client: one of our drops on the ground. A small bobbing sack, a beam of
## light in the colour of its best item's rarity (seen from across the camp),
## and that item's name above it, drawn on top of everything so a body or a
## crate can't hide it. Placeholder art, built in code.

const SACK_COLOR := Color(0.45, 0.32, 0.2)
const BEAM_HEIGHT := 3.0
const BOB_HEIGHT := 0.06
const BOB_SPEED := 2.5
const SPIN_SPEED := 0.8

var _sack: MeshInstance3D
var _beam_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _label: Label3D
var _time := 0.0


func _ready() -> void:
	_sack = MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.22
	body.height = 0.36
	_sack.mesh = body
	var sack_material := StandardMaterial3D.new()
	sack_material.albedo_color = SACK_COLOR
	_sack.material_override = sack_material
	add_child(_sack)
	# The tied neck, in the rarity colour.
	var trim := MeshInstance3D.new()
	var neck := CylinderMesh.new()
	neck.top_radius = 0.05
	neck.bottom_radius = 0.09
	neck.height = 0.12
	trim.mesh = neck
	trim.position.y = 0.2
	_trim_material = StandardMaterial3D.new()
	_trim_material.emission_enabled = true
	trim.material_override = _trim_material
	_sack.add_child(trim)

	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.02
	beam_mesh.bottom_radius = 0.09
	beam_mesh.height = BEAM_HEIGHT
	beam.mesh = beam_mesh
	beam.position.y = BEAM_HEIGHT / 2.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_material = StandardMaterial3D.new()
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.material_override = _beam_material
	add_child(beam)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.004
	_label.font_size = 36
	_label.outline_size = 10
	_label.no_depth_test = true
	_label.position.y = 0.9
	add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	_sack.position.y = 0.2 + sin(_time * BOB_SPEED) * BOB_HEIGHT
	_sack.rotation.y = _time * SPIN_SPEED


## Colours it and names its best item ("+N more" when it holds several).
func show_items(items: Array[Item], db: ItemDatabase) -> void:
	if items.is_empty():
		return
	var best := Item.best_of(items, db)
	var color := best.rarity_color(db)
	_beam_material.albedo_color = Color(color, 0.35)
	_trim_material.albedo_color = color
	_trim_material.emission = color
	_label.modulate = color
	_label.text = best.display_name(db)
	if items.size() > 1:
		_label.text += "  +%d" % (items.size() - 1)

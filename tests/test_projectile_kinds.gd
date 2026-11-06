extends TestCase
## The real data/projectiles.cfg: every kind loads and makes sense, `like` kinds
## (an ability's own-colored copy of its weapon's projectile) fly exactly like
## the kind they copy, and every attack's `projectile` names a kind. Only
## relations between the files are checked, never particular values.

const FILE := "projectiles"
const PREFIX := "projectile_"


func test_every_kind_validates() -> void:
	var kinds := ProjectileParams.all_kinds()
	assert_true(kinds.size() > 0, "kinds loaded")
	for p in kinds:
		assert_eq(p.validate(), "", p.id)


func test_like_kinds_copy_everything_they_dont_list() -> void:
	var checked := 0
	for section in Tuning.get_sections(FILE):
		if not section.begins_with(PREFIX) or not Tuning.has_value(FILE, section, "like"):
			continue
		var base_id := str(Tuning.get_value(FILE, section, "like"))
		var copy := ProjectileParams.get_kind(section.trim_prefix(PREFIX))
		var base := ProjectileParams.get_kind(base_id)
		assert_true(base != null, "%s copies a kind that exists (%s)" % [section, base_id])
		if copy == null or base == null:
			continue
		for key in ["speed", "gravity", "pitch", "aim_pitch", "lifetime_ticks", "hit_radius",
				"pierce", "walls", "stopped_by_guard", "release_height", "release_forward",
				"returns", "visual", "length", "spin", "glow", "bounces", "homing_turn", "hits"]:
			var file_key: String = "lifetime" if key == "lifetime_ticks" else key
			if not Tuning.has_value(FILE, section, file_key):
				assert_eq(copy.get(key), base.get(key), "%s %s" % [section, key])
		if not Tuning.has_value(FILE, section, "color"):
			assert_eq(copy.color, base.color, section + " color")
		checked += 1
	assert_true(checked > 0, "some kinds use like")


func test_every_attack_names_a_kind() -> void:
	for prefix in ["weapon_", "wings_", "enemy_"]:
		for file in Tuning.files_with_prefix(prefix):
			for section in Tuning.get_sections(file):
				var kind: String = str(Tuning.get_optional(file, section, "projectile", ""))
				if not kind.is_empty():
					assert_true(ProjectileParams.get_kind(kind) != null,
							"%s.cfg [%s] projectile=%s" % [file, section, kind])

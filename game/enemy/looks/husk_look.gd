extends EnemyLook
## The Husk: a purple capsule with glowing eyes and a club it raises during the
## windup and brings down in the strike.

## Club pitch at rest, raised at the end of the windup, and at the end of the strike.
const CLUB_IDLE := -0.6
const CLUB_WOUND := 1.9
const CLUB_STRUCK := -1.5


func build() -> void:
	club_pivot.visible = true


func base_color() -> Color:
	return Color(0.42, 0.3, 0.48)


func pose(attack_tick: float) -> void:
	var club := CLUB_IDLE
	var strike := strike_fraction(attack_tick)
	var recovery := recovery_fraction(attack_tick)
	if strike >= 0.0:
		club = lerpf(CLUB_WOUND, CLUB_STRUCK, strike)
	elif recovery >= 0.0:
		club = lerpf(CLUB_STRUCK, CLUB_IDLE, recovery)
	elif attack_tick >= 0.0:
		club = lerpf(CLUB_IDLE, CLUB_WOUND, windup_fraction(attack_tick))
	club_pivot.rotation.x = club

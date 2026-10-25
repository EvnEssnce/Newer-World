# Enemies and camps

Build order 5.1 (Milestone 6, session 62): three camp enemy kinds beside the Husk,
each with its own loot table and a higher gear score band, placed as camps on the
test map. Names are original. Every number is in `data/enemy_<kind>.cfg` and
`data/loot.cfg`; this file is the intent.

| Kind (id) | Role | Health | Hits | Loot (GS, drop) | XP (kill / mastery) | Camp |
|---|---|---|---|---|---|---|
Stats below are at the kind's own gear score; the camps are placed higher (see
"Scaling by gear score"). Loot is a band around the killed enemy's gear score.

| Kind (id) | Role | Kind GS | Health | Hits | Loot band (drop) | XP (kill / mastery) | Camp (placed GS) |
|---|---|---|---|---|---|---|---|
| Husk (`husk`) | slow melee club | 120 | 600 | 120, 0.6 s windup | −19/+20 (30%) | 50 / 40 | 2 at (0, -15) (120) |
| Thornling (`thorn`) | fast pack skirmisher: lunging bites that bleed, backs off between bites | 125 | 320 | 55 + Bleed, 0.35 s windup | −15/+25 (22.5%) | 40 / 30 | 2 east at (24, 0) (140) |
| Cinder Seer (`seer`) | ranged caster: a slow, dodgeable ember orb; keeps its distance | 135 | 420 | 70 (+ Burn) at 13 m, 0.8 s windup | −15/+25 (30%) | 70 / 55 | 2 west at (-24, -6) (150) |
| Cragmaw (`crag`) | lone bruiser: a slow frontal slam that breaks guards and knocks back; barely staggers, turns slowly (flank it) | 160 | 2400 | 240 cone, 1.2 s windup | −10/+20 (50%, 2 items) | 220 / 160 | 1 north-east at (21, -23) (180) |

Shared engine work (session 62):
- **Looks** per kind: `game/enemy/looks/<kind>_look.gd` (extends `EnemyLook`),
  placeholder low-poly parts built in code; a kind without one looks like a Husk.
- **Camps:** an `EnemySpawns` marker's `metadata/camp`; when one member starts
  fighting, the idle rest join in against the same player (`EnemyBrain.alert`).
- **Keep distance** (`[ai] keep_distance`, `retreat_speed`): between swings the
  enemy backs away from a nearer target (Thornling hit-and-run, the Seer's spacing).
- **Enemy projectiles:** an enemy `[attack]` with `projectile` throws it at its
  target on the release tick (`ProjectileSystem.server_fire_enemy`); they hit
  players only, through the normal block/parry/i-frame rules.
- **Display names** (`[stats] name`) and a ~10-byte smaller enemy snapshot entry
  (yaw as a 32-bit float, health rounded up).

Snapshot budget: 8 enemies (with the dummy). `-Bots 6` measured 1111 bytes max with
3 enemies before; more camps need interest management (build order "network headroom").

## Scaling by gear score (developer's direction; built in session 62)

Few kinds, many strengths: about **10–12 enemy kinds across the whole game**, each
reused in every zone tier, with its **gear score** set by where it's placed. Drops
follow the enemy you fought, not a fixed band per kind.

- **Enemy gear score per placement**: a camp marker gives the enemy's GS
  (`metadata/gear_score`; later a zone's default), else the kind file's
  `[stats] gear_score`, which is also the GS its stats are written at.
- **Stats scale with it** (`data/scaling.cfg`): health and damage multipliers
  per GS (a curve like `GearScore.factor`, likely steeper, since players gain from gear
  and levels too); block stamina damage with damage; speeds, timings, ranges and AI
  don't scale (they're the kind's feel). Armor piercing already uses the enemy's GS.
  XP per kill scales too.
- **Loot GS from the enemy's GS**: a loot table gives a band *relative* to the enemy
  (e.g. −10 to +15), so the same Thornling drops 110–150 in a starting zone and
  250–290 later; a kind's table keeps its item weights and drop chance, and elites
  (the Cragmaw) get a higher offset and better rarity odds. Rarity odds may also rise
  with GS.
- Built: `data/scaling.cfg` (health 1.6%, damage 1.12%, XP 1.6% per 5 GS),
  `EnemyParams.scaled_to`, relative loot bands, nameplates "Name  GS N" (clients read
  the marker by enemy id, so snapshots stay the same size). Not yet: rarity odds
  rising with GS, zone-wide defaults (5.2).
- Drop chances halved (developer, session 62), rarity weights unchanged.

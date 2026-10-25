# Enemies and camps

Build order 5.1 (Milestone 6, session 62): three camp enemy kinds beside the Husk,
each with its own loot table and a higher gear score band, placed as camps on the
test map. Names are original. Every number is in `data/enemy_<kind>.cfg` and
`data/loot.cfg`; this file is the intent.

| Kind (id) | Role | Health | Hits | Loot (GS, drop) | XP (kill / mastery) | Camp |
|---|---|---|---|---|---|---|
| Husk (`husk`) | slow melee club | 600 | 120, 0.6 s windup | 101–140, 60% | 50 / 40 | 2 at (0, -15) |
| Thornling (`thorn`) | fast pack skirmisher: lunging bites that bleed, backs off between bites | 320 | 55 + Bleed, 0.35 s windup | 110–150, 45% | 40 / 30 | 2 east at (24, 0) |
| Cinder Seer (`seer`) | ranged caster: a slow, dodgeable ember orb; keeps its distance | 420 | 70 (+ Burn) at 13 m, 0.8 s windup | 120–160, 60% | 70 / 55 | 2 west at (-24, -6) |
| Cragmaw (`crag`) | lone bruiser: a slow frontal slam that breaks guards and knocks back; barely staggers, turns slowly (flank it) | 2400 | 240 cone, 1.2 s windup | 135–175, always, 2 items | 220 / 160 | 1 north-east at (21, -23) |

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

## Planned: scaling by zone (developer, session 62)

Few kinds, many strengths: about **10–12 enemy kinds across the whole game**, each
reused in every zone tier, with its **gear score** set by where it's placed. Drops
follow the enemy you fought, not a fixed band per kind.

- **Enemy gear score per placement**: a camp marker (later the zone) gives the enemy's
  GS (`metadata/gear_score`, falling back to the zone's, then the kind file's
  `[stats] gear_score`). The kind file holds its stats at a reference GS (100).
- **Stats scale with it** (`data/enemy_scaling.cfg`): health and damage multipliers
  per GS (a curve like `GearScore.factor`, likely steeper, since players gain from gear
  and levels too); block stamina damage with damage; speeds, timings, ranges and AI
  don't scale (they're the kind's feel). Armor piercing already uses the enemy's GS.
  XP per kill scales too.
- **Loot GS from the enemy's GS**: a loot table gives a band *relative* to the enemy
  (e.g. −10 to +15), so the same Thornling drops 110–150 in a starting zone and
  250–290 later; a kind's table keeps its item weights and drop chance, and elites
  (the Cragmaw) get a higher offset and better rarity odds. Rarity odds may also rise
  with GS.
- Session 62's fixed bands (110–150 / 120–160 / 135–175) become these offsets around
  each camp's GS when this is built.
- Clients would show the GS (or a level) on the nameplate: they can read it from the
  marker by enemy id (same scene, same order), so snapshots stay the same size.

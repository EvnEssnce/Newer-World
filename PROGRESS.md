# Progress

## Current milestone

**2. Loot loop.** Enemy drops with rarity and rolled stats, inventory, equipping gear
that changes the player's numbers.

Milestone 1 (networked combat slice) is **done**: on 2026-10-07 the developer
playtested fighting Husks alongside the bot and called the combat loop great, with
Husks behaving as expected.

## Session log

### 2026-10-07 (9): First enemy (Husk)

Done:
- Husk: a slow, heavy-hitting melee enemy, fully server-controlled. Two of them at a
  camp ~15 m north of spawn. They wander, notice players within 8 m, chase, and swing
  (0.6 s windup telegraphed by glowing red, 120 damage, 0.3 s stagger on hit). Roll and
  block work against them as against players.
- Players hit Husks with the same attacks; heavies stagger them (interrupting their
  windup). 600 health; dead Husks respawn at the camp after 10 s. Pulled more than 25 m
  from camp, a Husk walks home and heals.
- All values in `data/enemy_husk.cfg`. Camps are `Marker3D`s in `world.tscn`.
- The bot fights the nearest Husk within 15 m (else you), so you can fight Husks
  together, which is milestone 1's "done" check.
- Tests: 76 (11 for the enemy brain). Smoke test: Husks and bots must hit each other;
  0 corrections across 5 runs. Visuals checked from game frames (telegraph, club,
  labels).

Needs a hand playtest (milestone 1 check): fight the Husks with the bot (or a second
person). Is it fun? Tune `data/enemy_husk.cfg`.

### 2026-10-07 (8): Block

Controls changed (developer's choice, New World layout): **tap left click = light,
hold left click = heavy, hold right click = block.**

Done:
- Block: frontal arc (120°) blocks hits; blocked hits cost stamina
  (`block_stamina_damage` per attack) instead of health. Slower movement and stamina
  regen while blocking; the guard faces the camera. Attacking or rolling drops the
  guard, and it comes back if right click is still held.
- Guard break: heavy attacks always break a guard (`breaks_block`), and so does any hit
  with more stamina damage than the blocker has. Guard break = 1.2 s stagger (raised
  from 0.8: at 0.8 the stagger ended before the attacker could follow up after a heavy).
- "Blocked" / "Guard broken!" labels; placeholder shield raises when blocking.
- Fixed a real prediction bug: the client didn't restore the body's on-floor flag when
  reconciling, so a correction that moved you into the air made the replay drift. The
  flag is now part of `PlayerState`.
- Bots take turns: one attacks (heavy, then two lights) while the other blocks. Smoke
  test (now 12 s) requires blocks and guard breaks too. `--verbose` logs unexpected
  corrections and dropped inputs.
- Tests: 65.

Needs a hand playtest: block feel, guard break length, stamina cost of blocked hits,
and whether heavies should always break guard.

### 2026-10-07 (7): Death, respawn and stagger

Done:
- Death at 0 health: the player drops (grey, face down), can't act or be hit. A
  "Defeated / Respawning in N" banner counts down; after 5 s (`[death] respawn_time`)
  they respawn at a random spawn point with full health and stamina.
- Stagger: heavy hits stagger the target for 0.4 s (`stagger` per attack in
  `weapon_sword.cfg`; light is 0). Interrupts their attack or roll; presses during it
  are buffered. Body tilts back while staggered.
- `--tune=file/section/key=value` launch option to override tuning for one run.
- Fixed two sources of false prediction corrections: respawning in mid-air (now on the
  ground) and two snapshots acknowledging the same input. Corrections caused by server
  events (stagger/death/respawn) aren't counted.
- Tests: 51 (11 new for stagger/death). Smoke test runs with 300 health and 0.5 s
  respawn: 1–2 deaths and respawns per run, 0 corrections.

Needs a hand playtest: respawn time, stagger length, whether light hits should stagger.

### 2026-10-07 (6): Attack playtest feedback

Playtest verdict (developer): hitbox size is fine for now (revisit with real animations);
light attack recovery feels good.

Done:
- Heavy attack moved to right click; light attack (left click) now fires on press.
  The tap/hold logic is gone. Note: New World uses right click for block, so block
  will need a key decision when we build it.
- Attacks track the camera during the whole swing (facing and hitbox turn toward the
  aim at `turn_speed` in `weapon_sword.cfg`, 720°/s), instead of locking at the start.
- Shorter reach: light 2.2 → 1.8 m, heavy 2.4 → 2.0 m.
- `run_local_test.ps1` now makes the second window a bot by default (`-NoBot` for two
  player windows). The bot fights the nearest player, circles, jumps and dodges.
- Tests: 40, all pass. Smoke test: 0 corrections, all bot attacks land.

Needs a hand playtest: right-click heavy, aim tracking speed during swings.

### 2026-10-07 (5): Light and heavy sword attacks

Done:
- Left click: tap = light attack (starts on release), hold 0.25 s = heavy attack (starts
  while still held; releasing afterwards does nothing). Attacks face the camera.
- Each attack: windup → active (hitbox live) → recovery. Movement slowed during attacks,
  no jumping. A dodge can cancel recovery only. Presses mid-attack/mid-roll are buffered.
- Server-side hit detection: box hitbox vs capsule (`MeleeHitbox`), one hit per target
  per attack, respects i-frames ("Evaded" shown on the target).
- Health (1000), HUD health bar, health under other players' names, damage numbers,
  red hit flash. At 0 health it refills and shows "Defeated!" (placeholder).
- F3 (or `--hitboxes`) shows hitboxes: faint during the attack, bright while live.
- All values in `data/weapon_sword.cfg` and `data/combat.cfg` [health].
- Tests: 38 (12 attack rules, 6 hitbox math). Bots now fight; smoke test requires the
  server to resolve hits. Result: 3–8 attacks per bot, all landed, 0 corrections.
- `--screenshot-dir` flag so visuals can be checked from the game's own frames.

Needs a hand playtest: attack feel (timings, reach, slow-down), tap vs hold threshold,
whether dodge should also cancel windup, and hitting a player who's rolling.

### 2026-10-07 (4): Neutral dodge rolls forward

- Dodging with no movement input now rolls forward (the way the character faces)
  instead of backstepping. Backstep removed entirely; every roll is a forward roll.

### 2026-10-07 (3): Dodge playtest feedback, air dodge

Playtest verdict (developer): roll distance/speed, recovery into movement, time between
rolls, i-frame window and stamina values all feel right; keep them. Holding Shift
rolling only once is intended. Stamina may later depend on equipped weapon/armor.

Done:
- Air dodge: allowed in the air, changes only horizontal movement; gravity and the jump
  arc carry on. Limited to `air_dodges` per time in the air (default 1, resets on
  landing; 0 = ground only) in `data/combat.cfg`.
- Tests: 19 (air dodge rules, plus physics tests proving an air dodge leaves vertical
  motion unchanged). Test runner now waits a frame so tests can add physics bodies.
- Bot now jumps, air dodges and ground dodges; smoke test requires both kinds with
  0 corrections. Result: 5 dodges (3–4 in the air) per bot, 0 corrections.

Needs a hand playtest: air dodge feel, and whether 1 air dodge per jump is right.

### 2026-10-07 (2): Stamina and dodge roll

Done:
- Dodge on **Shift**: rolls in the movement direction, or backsteps (straight back,
  without turning) with no movement input (changed to forward in session 4). Costs stamina; can't dodge in the air or with
  too little stamina. Presses up to `buffer` seconds early (mid-roll, or just before
  landing) still fire.
- I-frames for a window inside the roll (`PlayerState.is_invulnerable`). Nothing can hit
  yet; for now the body flashes white during i-frames so the window is visible.
- Stamina regenerates after a delay once the roll ends. Stamina bar on the HUD.
- Placeholder roll visual: the capsule somersaults over the roll.
- Fully predicted and reconciled: stamina, dodge and facing now live in `PlayerState`,
  which the server sends in every snapshot.
- All values in `data/combat.cfg`.
- Unit tests: small in-repo runner (`tests/framework/`, `tools/run_tests.ps1`), 14 tests
  for stamina/dodge rules. All pass.
- Smoke test now also requires each bot to dodge with ≤ 2 corrections. Result: 5 dodges
  per bot, 0 corrections.

Needs a hand playtest: roll in both windows with `run_local_test.ps1`, check that it feels
right and that the other window shows the roll, then tune `data/combat.cfg`.

### 2026-10-07 (1): Project setup and networked movement

- Godot 4.7.2, git, private GitHub repo (`EvnEssnce/Newer-World`), folder layout, docs.
- Dedicated server (`--headless -- --server`), client connect screen.
- Server-authoritative movement, client prediction + reconciliation, snapshot
  interpolation for other players. Hand-tested with two windows: smooth.
- Smoke test (`tools/smoke_test.ps1`).

## Next

Milestone 2, one session each:
1. Items and loot rolls (pure logic + tests): item definitions, rarity tiers, rolled
   stats, gear score ranges, Husk loot table, all in `data/`. Plus a script that rolls
   50,000 drops and prints the real rarity distribution.
2. Drops in the world: a dead Husk drops loot the server rolls; walk over or press a key
   to pick it up (server-authoritative); a simple inventory screen.
3. Equipment slots: equip a weapon/armor piece and its stats change your damage and
   defense (attributes like STR/CON can start here). Check `design/classes.md` first.

Later / unscheduled:
- Light attack combo chain (New World-style 3-hit string)?
- Swap the capsule for a CC0 character with Mixamo idle/run/roll animations
  (download the packs yourself; Mixamo needs an Adobe login).

## Known issues / notes

- Husks steer straight at their target (no navmesh), so a crate between you and a
  Husk can stall it. Fine for the open test area; add navigation before real zones.
- A heavy's hitbox can hit both Husks at once when they stand together.

- About 1 smoke run in 20 shows a few (≤4) small unexpected corrections on flat ground
  (~0.1 m sideways), not near any server event. Cause unconfirmed; the server logged no
  dropped inputs in 12 runs that tried to catch it. Smoke test tolerates ≤5. Run with
  `--verbose` to get the details if it shows up in play.

- Movement and combat tuning are read separately by server and client. If they run
  different `data/*.cfg` files, prediction will constantly correct. Later: the server
  could send its values on connect.
- Clients send input every physics tick (60/s) and get full snapshots of every player
  (including their stamina). Fine for 50 players on a LAN; add interest management
  and delta compression before a public playtest.
- No render smoothing after a correction yet: a big correction snaps the local player.
- Holding Space keeps jumping (jump is sent as "held").
- Dodge recovery into movement was judged smooth in playtest (no recovery phase needed).
- No lag compensation for hits: the server checks targets' current positions, while
  the attacker sees them ~100 ms in the past. Fine on LAN; matters over the internet.
- Hit events arrive before the attacker's swing is drawn on other clients (remote
  players are drawn 100 ms in the past, hit events aren't delayed).
- Attacks pass through crates (the hitbox ignores world geometry).
- Placeholder sword swing/flash/damage-number constants live in `player.gd` (cosmetic
  only, to be replaced by real animation and VFX).
- This repo has a local git `user.name`/`user.email` (no global identity configured).

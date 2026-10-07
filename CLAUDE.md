# Newer World

Small online action RPG (10–50 players per server) with combat, gathering, crafting and
loot modeled on New World: Aeternum, using low-poly art. Godot 4.7, GDScript. The project
brief and build order are in `newer-world-handoff.md` (Part 1).

**Start every session by reading this file and `PROGRESS.md`. Don't re-explore the
codebase.** Update `PROGRESS.md` at the end of every session.

## Rules

- **Server-authoritative.** The server decides movement, hits, loot, inventory, crafting.
  Clients send inputs and predict only their own movement. Never let a client tell the
  server an outcome ("I hit X", "I picked up Y").
- **Tuning values go in `data/*.cfg`, never in code.** Damage, timings, speeds, costs,
  drop rates, respawn timers. Read them with `Tuning.get_value(file, section, key)`.
  Every value gets a comment saying what it does and its units. The developer edits
  these files directly to tune game feel.
- **Persistence goes through one module** (not built yet; milestone 5). SQLite in dev,
  Postgres later. Nothing else touches the database.
- **Tests** for systems that don't depend on feel: loot rolls, damage formulas, crafting
  outputs, inventory rules, stamina/dodge rules. Combat feel is playtested by hand. Tests
  use a small in-repo runner (`tests/framework/`), not GUT: extend `TestCase`, put
  `test_*` methods in `tests/test_*.gd`, and build params by hand instead of reading
  `data/` so tuning edits don't break tests.
- **Keep game logic separate from physics where possible** (like `PlayerState`), so it
  can be unit tested without a scene.
- **Original names, art and UI.** Mechanics can be borrowed from New World; names,
  item names, art and UI layouts can't.
- One testable goal per session. Keep sessions focused (the developer is on Claude Pro).

## Layout

```
project.godot        Autoloads: Tuning, Net. Main scene: game/main.tscn. 60 physics ticks/s.
core/
  tuning.gd          Autoload. Loads every res://data/*.cfg.
  net.gd             Autoload. ENet server/client setup, connection signals, ping.
  launch_args.gd     Command-line flags (after "--").
  input_actions.gd   Key bindings, registered in code.
game/
  main.gd/.tscn      Entry point: server or client. Adds World at /root/Main/World.
  world/world.gd     Server sim loop, snapshots, hit resolution; client input sending,
                     prediction, interpolation, hit display; test bot.
  player/player.gd   One player; server/local/remote roles (see below), health, visuals.
  player/player_movement.gd  Shared deterministic sim step: PlayerState + physics.
  player/player_state.gd     Stamina, dodge, attacks, stagger, death, facing. Pure logic, unit tested.
  player/player_params.gd    Player tuning converted to ticks/radians, loaded once.
  combat/attack_params.gd    One attack's tuning (phases, damage, hitbox). Players and enemies.
  combat/melee_hitbox.gd     Box hitbox vs capsule test, frontal arc. Pure math, unit tested.
  combat/hit_feedback.gd     Floating combat text over whoever was hit (client).
  enemy/enemy.gd/.tscn       One enemy: server runs its brain, health, death; clients interpolate.
  enemy/enemy_brain.gd       Enemy AI state machine. Pure logic, unit tested.
  enemy/enemy_params.gd      Enemy tuning from data/enemy_<kind>.cfg.
  items/item_database.gd     Rarity, item, affix and loot table definitions; validate().
  items/item.gd              One rolled item (plain data, to_dict/from_dict).
  items/loot_roller.gd       Rolls loot tables and items. Pure logic, unit tested.
ui/                  connect_menu (client start screen), hud (health/stamina bars, debug info).
data/                Tuning files: network, movement, combat, camera, weapon_sword, enemy_husk,
                     loot (rarities + loot tables), items, affixes (.cfg).
design/              Design docs. classes.md: classes, weapons, abilities, Ember, build waves.
assets/              CC0 art packs go here (Kenney, Quaternius, Mixamo).
tests/               test_*.gd unit tests; framework/ holds the runner and TestCase.
tools/               PowerShell run scripts, unit test runner, smoke test.
```

## Networking model

- The server is peer 1. `World` exists at `/root/Main/World` on every machine, because
  RPCs are matched by node path. Player nodes are named by peer id under `World/Players`.
- `server_relay` is off: clients never hear from each other directly, only via snapshots.
- **Client → server**, every physics tick, `World._submit_inputs` (unreliable ordered,
  channel 1): the last `input_redundancy` inputs, each
  `[seq, move: Vector2, buttons: int, aim_yaw: float]`. `move` is a world-space XZ
  direction (camera rotation already applied), length ≤ 1. `buttons` holds
  `PlayerState.BUTTON_*` bits: jump, attack and block are sent while held; dodge only on
  the tick it's pressed (the sim buffers it). Tap vs hold (light vs heavy) is decided
  inside the sim from the held attack bit. `aim_yaw` is the camera yaw; attacks and
  block face it. New actions get new bits.
- **Server**: queues inputs per player (validated, bounded by `max_input_buffer`) and
  simulates at most `max_inputs_per_tick` per tick. **One input = one sim step**; a
  player with no queued input doesn't move. That keeps server and client in lockstep.
- **Server → each client**, `snapshot_rate` times per second, `World._receive_snapshot`
  (unreliable ordered, channel 2): `tick` and every player's
  `[peer_id, position, velocity, last_processed_seq, PlayerState.to_array(), health]`.
  Snapshots also drive spawning/despawning on clients: new id → spawn, missing id → remove.
- **Local player**: applies each input immediately and remembers the predicted position
  and `PlayerState` per seq (keeping the latest acknowledged one, since two snapshots
  can acknowledge the same seq). On a snapshot, if the server's position or state for
  `last_processed_seq` differs from the prediction, it restores the server's position,
  velocity and state and replays unacknowledged inputs. "Corrections" on the HUD count
  only unexpected ones and should stay 0 on localhost; a mismatch caused by a server
  event (`PlayerState.server_events` changed: blocked hit, stagger, death, respawn)
  isn't counted. `--verbose` logs each unexpected one, and server-side input drops.
- **On-floor is synced state**: `PlayerMovement` reads `PlayerState.on_floor` (set after
  each `move_and_slide`), never `body.is_on_floor()` directly, so a restored state
  carries it. Server-side teleports (respawn) should still land exactly on the ground.
- **Remote players**: drawn `interpolation_delay` seconds in the past, interpolated
  between snapshots on a render clock synced to server ticks. Roll and i-frame visuals
  come from the interpolated `PlayerState`.
- Players don't collide with each other (layer 2, mask 1). The world is layer 1.
- **All simulated state lives in `PlayerState`** (plus position/velocity). If something
  affects the sim and isn't in `to_array()`, reconciliation will break. Anything that
  changes the sim goes in `PlayerState.step` or `PlayerMovement.step`, which both server
  and prediction run. Keep them deterministic: no randomness, no `Input`, durations in ticks.
- **I-frames**: `PlayerState.is_invulnerable(params)`. Clients flash the body white while
  it's true.

## Combat model

- Tap left click = light (fires on release), hold left click `heavy_hold_time` = heavy
  (fires while held). Hold right click = block. Attacks: windup → active (hitbox live)
  → recovery, all in ticks from the weapon file. A dodge can cancel recovery only.
  Presses during an attack or roll are buffered. Facing starts at `aim_yaw` and tracks
  it at `turn_speed` (weapon file) for the whole attack, so the hitbox follows the
  camera; movement is slowed by `move_multiplier`.
- **Block** (`[block]` in combat.cfg): `PlayerState.blocking` while the button is held
  and not attacking/dodging/staggered (attack or dodge drops the guard; it comes back if
  still held). Slower movement and stamina regen; facing tracks the aim. On the server,
  a hit on a blocker from within `arc` in front (`MeleeHitbox.is_in_front`) calls
  `take_blocked_hit`: costs the attack's `block_stamina_damage` instead of health
  (`damage_taken` fraction still applies). `breaks_block` attacks (heavy) or running out
  of stamina = guard break: `guard_break_stagger`. Results `HIT_BLOCKED` /
  `HIT_GUARD_BROKEN`.
- **Hits are server-only.** After each server sim step with a live hitbox, `Player` emits
  `attack_stepped`; `World._on_attack_stepped` tests `MeleeHitbox.hits` against every
  other player's current server position. Each target is hit at most once per attack
  (`Player.attack_results`). A target in i-frames "evades" (reported once) but can still
  be hit later in the same active window.
- Health is server-owned, outside `PlayerState` (clients don't predict damage), sent in
  snapshots. Hit events go to clients via reliable `World._receive_hit` (`HIT_*`
  results) for damage numbers, labels and the red flash.
- **Stagger**: a hit with `stagger > 0` (weapon file; heavy only by default) calls
  `PlayerState.apply_stagger`: interrupts the target's attack/dodge, and it can't act
  until it ends (presses stay buffered).
- **Death**: at 0 health the server calls `PlayerState.kill()`; dead players can't act,
  can't be hit, and lie grey on the ground. After `[death] respawn_time` the server
  `_respawn`s them at a random point on the spawn circle with full health and stamina
  (`revive()`). The client shows a countdown banner from the `HIT_DEFEATED` event.
- No lag compensation yet: hits use targets' current server positions, while the
  attacker sees them `interpolation_delay` in the past.

## Enemies

- Placed by `Marker3D`s under `World/EnemySpawns` (level data; `metadata/kind` picks
  `data/enemy_<kind>.cfg`). The server spawns one `Enemy` per marker at startup with a
  negative id (`-1`, `-2`, ...), which is also its node name under `World/Enemies` and
  how hit events address it (peer ids are always positive).
- **Server only**: each tick after the players, `Enemy.server_step` runs its
  `EnemyBrain` (IDLE wander → CHASE nearest living player within `aggro_range` →
  ATTACK when within `attack_range` and off cooldown → back to CHASE; STAGGERED when hit
  by a staggering attack; RETURN home past `leash_range`, healing on arrival). Movement
  is direct steering, no navmesh yet. Not predicted, so no PlayerState-style rules.
- Enemy swings go through the same `World._strike_player` as player attacks (evade,
  block, guard break, stagger, death). Player attacks on enemies: damage, aggro the
  attacker, stagger × `stagger_multiplier`; death → respawn at home after `respawn_time`.
- Snapshots carry `Enemy.get_snapshot()` per enemy; clients interpolate like remote
  players. The windup is telegraphed by the body glowing red.
- Enemies don't collide with players (layer 4; players and enemies only mask the world).

## Loot (milestone 2; rolls only so far)

- `data/loot.cfg`: rarity tiers (affix count, color) and loot tables (`[table_<id>]`:
  drop chance, rolls, gear score range, item and rarity weights). `data/items.cfg`: item
  definitions (slot, weapon type for weapons, primary stat per gear score).
  `data/affixes.cfg`: bonus stats, their slots and value ranges per 100 gear score.
- **No attributes** (STR/DEX...): `design/classes.md` decided against them. Gear stats
  modify combat numbers directly (damage_pct, crit_chance, max_health, ...).
- Weapon items only name a weapon type (`data/weapon_<type>.cfg` holds the attacks) and
  are class-locked. `weapon_power` is a percent of the weapon file's damage.
- `LootRoller` is server only and seeded by a `RandomNumberGenerator`. Loot will be
  personal: each player who damaged an enemy gets their own roll.
- `ItemDatabase.validate()` checks the three files against each other; a unit test runs
  it on the real data. `tools\roll_loot.ps1 [-Table husk] [-Kills 50000]` prints what a
  table really drops.
- Not built yet: drops in the world, pickup (F), inventory (I), equipping. See
  PROGRESS.md for the order and its dependency on the other session's Wave 1.
- Only the sword exists; `PlayerParams.from_tuning` reads `data/weapon_sword.cfg`.

## Running

Godot was installed with winget; there is no `godot` on PATH. `tools/find_godot.ps1`
locates it (override with the `GODOT` env var). PowerShell blocks scripts by default, so
run them with `-ExecutionPolicy Bypass`:

```
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1          # server + you + a bot window
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -NoBot   # server + 2 player windows
powershell -ExecutionPolicy Bypass -File tools\run_server.ps1            # headless server only
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1             # unit tests
powershell -ExecutionPolicy Bypass -File tools\roll_loot.ps1             # what a loot table drops over 50,000 kills
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1            # 2 bots, 12 s: move, dodge, fight each other and Husks, block, die, respawn
```

Run both `run_tests.ps1` and `smoke_test.ps1` before committing.

Game flags (after `--`): `--server`, `--port=N`, `--connect`, `--address=host[:port]`,
`--bot` (auto-connect; repeats every 6 s: take turns attacking and blocking: the nearest Husk within 15 m, else the nearest player; then circle with
jump/air dodge/ground dodge; see `World._bot_input`), `--verbose` (log positions every 2 s,
server logs hits), `--hitboxes` (start with hitboxes shown; F3 toggles),
`--screenshot-dir=PATH` (save the game window every 0.25 s, for checking visuals),
`--quit-after=SECONDS` (prints `SUMMARY` lines, used by the smoke test),
`--tune=file/section/key=value` (repeatable; overrides a `data/` value for that run;
give the server and every client the same overrides). The smoke test uses `--tune`
for low health and a fast respawn so deaths happen within the run.

To check visuals without a person, run a windowed `--bot --screenshot-dir=...` client and
read the saved frames. Never screenshot the desktop: it captures the developer's screen.

After adding a `class_name` script outside the editor, run
`<godot_console.exe> --headless --import` once so Godot registers the class.
`--check-only --script` gives false "Tuning not found" errors because it skips autoloads;
use the smoke test instead.

## Export notes (for later)

- `data/*.cfg` aren't Godot resources: add `data/*` to the export preset's
  "include non-resource files" filter, or exported builds won't find tuning files.
- The dedicated server export should use the "Dedicated Server" preset; `main.gd`
  treats the `dedicated_server` feature tag like `--server`.

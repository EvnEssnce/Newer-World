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
  world/build_service.gd  World/Builds node: class/weapon/mastery requests (RPCs), validation.
  player/player.gd   One player; server/local/remote roles (see below), health, visuals.
  player/player_movement.gd  Shared deterministic sim step: PlayerState + physics.
  player/player_state.gd     Stamina, dodge, attacks, abilities, cooldowns, weapon swap,
                             stagger, death, facing. Pure logic, unit tested.
  player/player_params.gd    Player tuning converted to ticks/radians, every weapon, loaded once.
  combat/attack_params.gd    One attack's tuning (phases, hit windows, damage, hitbox). Players and enemies.
  combat/ability_params.gd   An ability: AttackParams + cooldown, dash, parry/counter.
  combat/weapon_params.gd    One weapon: light/heavy attacks, ability pool (data/weapon_<id>.cfg).
  combat/melee_hitbox.gd     Box/radial hitbox vs capsule test, frontal arc. Pure math, unit tested.
  combat/force_params.gd     An attack's forced movement (force_* keys): knockback/pull/push, launch.
  combat/forced_motion.gd    A push/launch in progress (players: in PlayerState; enemies). Unit tested.
  combat/hit_feedback.gd     Floating combat text over whoever was hit (client).
  build/class_def.gd         A class (data/class_<id>.cfg): allowed weapons, default loadout.
  build/mastery_tree.gd      A weapon's mastery tree and its rules. Pure logic, unit tested.
  build/character_build.gd   Class + equipped weapons + per-weapon tree allocation and slots.
  enemy/enemy.gd/.tscn       One enemy: server runs its brain, health, death; clients interpolate.
  enemy/enemy_brain.gd       Enemy AI state machine. Pure logic, unit tested.
  enemy/enemy_params.gd      Enemy tuning from data/enemy_<kind>.cfg.
  items/item_database.gd     Rarity, item, affix and loot table definitions; validate().
  items/item.gd              One rolled item (plain data, to_dict/from_dict).
  items/loot_roller.gd       Rolls loot tables and items. Pure logic, unit tested.
  party/party_rules.gd       Parties, invites, ally rule. Pure logic, unit tested.
  party/party_system.gd      World/Party: party RPCs, server validation, client keys/HUD/bot.
  status/status_def.gd       One status effect's tuning (data/status_effects.cfg).
  status/status_defs.gd      Every status, by index (what the network sends); validate().
  status/status_effects.gd   One owner's statuses: apply/stack/refresh, tick, queries,
                             cleanse, on-hit (Bloodlust). Pure logic, unit tested.
ui/                  connect_menu (client start screen), hud (health/stamina bars, ability bar,
                     weapon line, status row, debug info), mastery_panel (K: equipped weapons, tree, respec, slots),
                     party_hud (party frames, invite prompt, party notices; built in code).
data/                Tuning files: network, movement, combat, camera, enemy_husk,
                     weapon_<id> (broadsword, spear, dual_axes), class_<id> (fighter),
                     mastery (shared tree rules), mastery_<weapon>, loot (rarities + loot
                     tables), items, affixes, party, status_effects (.cfg).
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
  `PlayerState.BUTTON_*` bits: jump (1), attack (4) and block (8) are sent while held;
  dodge (2), swap (16) and abilities 1–3 (32/64/128, Q/E/R) only on the tick they're
  pressed (the sim buffers them). Tap vs hold (light vs heavy) is decided inside the sim
  from the held attack bit. `aim_yaw` is the camera yaw; attacks, abilities and block
  face it. New actions get new bits.
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
  event (`PlayerState.server_events` changed: blocked hit, stagger, death, respawn,
  parry counter, ability stopped on hit, loadout change, a status applied/used
  up/cleansed by the server, forced movement) isn't counted. `--verbose` logs
  each unexpected one, and server-side input drops.
- **Builds** (`World/Builds`, `BuildService`): the client sends its class in
  `World._client_ready(class_id)`; the server gives the player its class's default
  `CharacterBuild`. Reliable RPCs: client → server `_request_mastery(weapon_id, nodes,
  slots)` (a whole tree allocation + Q/E/R ability ids: a free respec) and
  `_request_weapons(weapons)`; server → client `_receive_build(build_dict, error)` after
  every request and on join. The server validates (class weapon list, mastery rules, not
  mid-attack/ability/swap) and puts what affects the sim (equipped weapon ids, slotted
  ability indices) into `PlayerState.set_loadout`, a server event, so it reaches the
  client through snapshots. Passive/upgrade nodes are server-only damage/stamina
  modifiers, never sim state.
- **On-floor is synced state**: `PlayerMovement` reads `PlayerState.on_floor` (set after
  each `move_and_slide`), never `body.is_on_floor()` directly, so a restored state
  carries it. Server-side teleports (respawn) should still land exactly on the ground.
- **Remote players**: drawn `interpolation_delay` seconds in the past, interpolated
  between snapshots on a render clock synced to server ticks. Roll and i-frame visuals
  come from the interpolated `PlayerState`.
- **ENet's packet throttle is off** (`Net._disable_packet_throttle`, both directions).
  Left on, it drops unreliable packets (inputs, snapshots) in bursts whenever ping
  spikes, e.g. while several clients start at once; enough to defeat input
  redundancy, so the server skips inputs ("never arrived" in `--verbose`) and clients
  get corrections that feel like lag.
- Players don't collide with each other (layer 2, mask 1). The world is layer 1.
- **All simulated state lives in `PlayerState`** (plus position/velocity). If something
  affects the sim and isn't in `to_array()`, reconciliation will break. Anything that
  changes the sim goes in `PlayerState.step` or `PlayerMovement.step`, which both server
  and prediction run. Keep them deterministic: no randomness, no `Input`, durations in ticks.
- **`PlayerState.to_array()` layout**: indices 0–26 as listed in `to_array()`; 27 =
  `StatusEffects.to_packed()` (`PackedInt32Array`, 4 ints per status: index into
  `StatusDefs`, stacks, ticks left, ticks elapsed); 28–30 = forced movement (see below);
  31 = `dodge_cooldown` (ticks after a roll before the next, `[dodge] cooldown`). Append
  new fields at the end.
  Enemy snapshots: `[id, kind, position, yaw, mode, attack_tick, health, dead,
  statuses (same packing)]`.
- **I-frames**: `PlayerState.is_invulnerable(params)`: a dodge's window, or an ability's
  `iframe_start`/`iframe_end` (Vault). Clients flash the body white while it's true.
- **Forced movement** is sim state too: `PlayerState.force` (a `ForcedMotion`: horizontal
  velocity, ticks left, pending launch speed) is entries 28 (velocity), 29 (ticks) and 30
  (launch) of `to_array()`. The server starts it (`start_force`, a server
  event); `PlayerMovement` applies it on both sides, so the client replays it exactly.

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
  other player's current server position. Each target is hit at most once per hit
  window (`Player.attack_results`, keyed by `attack_serial` + window). A target in
  i-frames "evades" (reported once) but can still be hit later in the same window.
  Damage is scaled by the attacker's mastery modifiers (`Player.damage_multiplier`).
  `_strike_player` ignores allies (`World.are_allies`): no damage, stagger, block cost
  or label.
- **Weapons and swap.** A class (`data/class_<id>.cfg`) lists the only weapons it can
  equip. Two are equipped (`PlayerState.weapons`, `equipped`); attacks, abilities and
  `block_stamina_multiplier` come from the one that's out. X swaps (`[swap]` in
  combat.cfg): not mid-attack/ability/roll (buffered), and while `swap_tick` runs you
  can move but not attack, block, dodge or use abilities. The new weapon is out from
  the first swap tick. The Fighter has three (Broadsword, Spear, Dual Axes); the K
  panel's "Equipped weapons" pickers choose the two (`BuildService._request_weapons`;
  picking the other slot's weapon swaps them, `CharacterBuild.loadout_with`).
- **Abilities** (`[ability_<id>]` in the weapon file, pool order = `[weapon]
  abilities`): Q/E/R use the equipped weapon's slots (`ability_slots`, pool indices).
  `attack_type == ATTACK_ABILITY` and `ability` = pool index, so abilities share the
  attack timeline (windup → hit windows → recovery; dodge cancels recovery; presses are
  buffered by `[abilities] buffer`). Cooldown starts with the ability and counts down
  for both weapons (`cooldowns`, per weapon slot × pool index). Variants:
  `windows`/`window_interval` (Frenzy: a target can be hit once per window),
  `shape="radial"` (Whirlwind Edge, Crashing Leap slam), dash (`dash_distance`, moved in
  `PlayerMovement` like a dodge: Shield Charge, Crashing Leap, Lunge;
  `dash_direction="back"` dashes away from the facing, `"input"` the way the movement input
  points, backward with none: Vault), ability i-frames (`iframe_start`/`iframe_end`:
  Vault), `max_targets` (the server calls `end_active_window` once reached; everything the
  hitbox touches on that step is still hit, so Shield Charge stops at its first contact
  but hits the whole group there), on-hit statuses (one charge per hit window, given to
  every target that swing hits: `Player.on_hit_statuses_for_window`), and
  parry (`parry_arc` + `counter`: Riposte). **Parry**: a hit on a player in a parry
  window from within the arc in front is negated (`HIT_PARRIED`) and the server calls
  `start_counter`, which starts the internal counter ability facing the attacker.
- **Mastery** (`data/mastery_<weapon>.cfg`, rules in `data/mastery.cfg`): two
  branches; a node of tier T needs `tier_requirements[T-1]` points in lower tiers of its
  branch; total ≤ `points`. Active nodes unlock abilities (a slot may only hold an
  unlocked one); passive/upgrade nodes are server-side modifiers (`effect` = damage,
  low_health_damage, block_stamina, none). Respecs are free any time except
  mid-attack/ability/swap. K opens the panel.
- **Forced movement** (the `FORCE` tag: knockback, pull, launch). Per attack, optional
  `force_direction` ("away" / "toward" / "forward"), `force_distance` (m),
  `force_height` (launch peak, m), `force_duration` (s), `force_needs_stagger` (only
  moves a target already staggered: Rising Cut) in the weapon or enemy file; shared
  limits in `[force]` of combat.cfg (max distance/height, pull gap). `ForceParams`
  computes the displacement, launch speed and ticks (at least the launch's airtime).
  Server only decides it: `World._force_player` / `_force_enemy`, after a hit that
  damaged or guard-broke (not evaded, blocked, parried or fatal), never between allies
  (`are_allies`). `PlayerState.start_force` refuses i-frames, death and
  `is_force_immune()` (the one immunity hook, false for now; Brace/Steadfast/Unbowed
  will change it). **Choice:** being moved interrupts like a stagger (attack, ability,
  dodge, swap, guard), and the target can't act until it ends; presses stay buffered.
  `PlayerMovement` sets the horizontal velocity from it (linear ease-out, so the
  distance is exact) and the launch speed on its first step; gravity and
  `move_and_slide` (walls) do the rest, and on-floor stays synced state. Enemies:
  `Enemy.start_force` (server) staggers the brain for the same ticks, so steering and
  swings pause. Players show the stagger tilt while moved.
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

## Status effects

- `data/status_effects.cfg`, one `[status_<id>]` each: `category` = **debuff** (never
  from an ally; removed by a cleanse) or **buff**; `affects` = **sim** (changes
  movement/actions, predicted: slow, root, stun) or **damage** (server-only numbers:
  bleed, exposed, damage_up, damage_reduction, bloodlust). Duration, max_stacks, then
  only the keys for what it does. Reapplying adds stacks (capped) and resets the time to
  full (never shortens). `StatusDefs.validate()` checks the file (a unit test runs it).
- **Players**: `PlayerState.statuses` (synced in `to_array()`), ticked down at the top of
  `PlayerState.step`. Slow scales walking speed and root stops walking/dodging/jumping/
  dashing in `PlayerMovement`/`can_dodge`. **Stun = stagger**: applying a stun staggers
  for its duration (same interrupt and "can't act"); the status entry is the name/timer
  and what a cleanse removes (`cleanse()` also ends the stagger). Enemies: stun =
  `brain.stagger`.
- **Server events vs prediction**: the server applying a status (`apply_status`), using
  up an on-hit stack (`take_on_hit_statuses`) or cleansing (`cleanse`) bumps
  `server_events`. A self-buff from your own attack/ability (`self_status`) starts inside
  `step()` (`_apply_self_status`), so it's predicted.
- **Applying**: attack/ability keys `applies_status`, `status_stacks`, `status_duration`
  (target, server, on `HIT_DAMAGED` only: not blocked/evaded/parried/killing hits) and
  `self_status`, `self_status_stacks` (self, in the sim). Owner statuses with
  `on_hit_status` (Bloodlust) add that status to each damaging hit and, with
  `consume_on_hit`, use up a stack per hit. All in `World._give_hit_statuses` /
  `_give_status`, which refuses debuffs between allies (`are_allies`). Death and respawn
  clear statuses.
- **Damage** (server, `World`): attacker `damage_dealt_multiplier` × target
  `damage_taken_multiplier` (per-stack bonuses add up, then multiply) in
  `_on_attack_stepped`, `_on_enemy_attack_stepped` and `_strike_player`. Damage over time:
  `StatusEffects.tick()` returns what's due (`PlayerState.status_damage`,
  `Enemy.status_damage`); `World._apply_player_status_damage` /
  `_apply_enemy_status_damage` apply it (× damage taken) after the tick's steps, through
  the normal death path (`_kill_player`, `_damage_enemy`), reported as
  `HIT_STATUS_DAMAGE` (or `HIT_DEFEATED`) with the status's source as attacker.
- **UI**: HUD status row (local player, predicted: name, stacks, seconds; green edge =
  buff, red = debuff); a status line under remote players' and Husks' health.
- Fighter status abilities: Broadsword **Opening Strike** (Exposed), Dual Axes
  **Bloodlust** (self-buff: next 4 hits bleed) and **Hamstring** (Slow, default axes R
  slot). Root, stun, damage_up and damage_reduction exist for later abilities (nothing
  applies them yet).

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
- Abilities hit enemies through the same path (`max_targets` and modifiers apply); a
  Husk swing into a Riposte is parried like a player's.
- Forced movement works on enemies too (server only, `Enemy.start_force`, same
  `force_*` params; `Enemy.is_force_immune()` is the hook). An enemy's own attack can
  have `force_*` keys: the Husk's `force_distance` is 0 (off); the smoke test turns it
  on (0.4 m: a longer shove pushed the bots out of their fights and broke the guard
  check) with `--tune` so predicted players get knocked back in most runs.

## Controls

WASD move, Space jump, Shift dodge, left click tap = light / hold = heavy, hold right
click = block, Q/E/R abilities, X swap weapon, K mastery panel (K or Esc closes it),
T/Y/N/L/Delete party (see below), F3 hitboxes, Esc frees the mouse. Panels that need
the mouse join the `modal_ui` group: while one is visible, clicks and wheel scrolls
don't recapture the mouse. Z and C are reserved for the two Wing
abilities, 1–9 for later, F for pickup and I for inventory (milestone 2): don't bind
them to anything else.

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
  PROGRESS.md for the order.

## Parties and allies

- **`World.are_allies(a, b)` is the one place that answers "same side?"** (peer ids; a
  player is its own ally, members of one party are allies, enemies (ids ≤ 0) never are).
  Use it for anything that targets friends or foes (heals, shields, buffs). It's
  authoritative on the server; a client only knows its own party. PvE-first: party
  members never damage each other.
- `PartyRules` (pure, unit tested) holds parties and invites: only a leader (or a
  player not in a party) invites; one pending invite per target; pending invites count
  toward `max_size`; the party is created on the first accepted invite; invites expire
  and die if the inviter stops leading the party they were sent from; leader leaves →
  earliest-joined member leads; a party of 1 dissolves; disconnect = leave. Tuning in
  `data/party.cfg`.
- `PartySystem` is `World/Party` on both sides (created in `World._add_party_system`).
  Not part of the predicted sim: it never touches `PlayerState` or the input bits.
  **Client → server**, reliable: `_request_invite(target_id)`, `_request_answer(accept)`,
  `_request_leave()`, `_request_kick(target_id)`. The server checks the sender has a
  player, the target exists and (for invites) is within `invite_range` by server
  positions, then applies `PartyRules`. **Server → client**, reliable:
  `_receive_view(PartyRules.view_for(peer))` to every peer whose view changed (members,
  leader, pending invite and its time left, outgoing invites, max size), and
  `_receive_notice(text)` to a requester whose request failed. Clients draw the view:
  `PartyHud` frames (health from snapshots), the invite prompt, and party members'
  nameplates in `Player.PARTY_NAME_COLOR`.
- Keys: **T** invite the player nearest the crosshair (within `invite_range`), **Y** join,
  **N** decline, **L** leave, **Delete** kick the party member nearest the crosshair
  (leader). Q, E, R, X, K, Z, C and 1–9 are reserved for abilities, weapon swap, the tree
  panel and Wing abilities.

## Running

Godot was installed with winget; there is no `godot` on PATH. `tools/find_godot.ps1`
locates it (override with the `GODOT` env var). PowerShell blocks scripts by default, so
run them with `-ExecutionPolicy Bypass`:

```
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1          # server + you + a bot window
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -NoBot   # server + 2 player windows
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -Party   # the bot parties with you
powershell -ExecutionPolicy Bypass -File tools\run_server.ps1            # headless server only
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1             # unit tests
powershell -ExecutionPolicy Bypass -File tools\roll_loot.ps1             # what a loot table drops over 50,000 kills
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1            # 2 bots, 32 s: move, dodge, fight each other and Husks, block, die, respawn, abilities, swap, respec, statuses (on a Husk), a bleed tick, Spear, knockback on players and Husks
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1 -Party     # same bots in a party: 0 hits, debuffs or forced moves on each other, Husk fights still happen
```

Run `run_tests.ps1`, `smoke_test.ps1` and `smoke_test.ps1 -Party` before committing.
Both smoke scripts take `-Port N` (default 24599) so parallel runs (e.g. two worktrees)
don't collide.

Game flags (after `--`): `--server`, `--port=N`, `--connect`, `--address=host[:port]`,
`--class=ID` (client: character class, default `fighter`; unknown = default),
`--bot` (auto-connect; repeats every 8 s: take turns attacking and blocking (the nearest
Husk within 15 m, else the nearest player), then both use abilities (guard up between; a
knockback ability first), then circle with weapon swap/jump/air dodge/ground dodge, a free
respec (odd cycles also learn new abilities like Rising Cut) and the next cycle's weapons
(the default loadout in the first cycle; then a different focus weapon each cycle:
Spear, Dual Axes, Broadsword; `BuildService.bot_weapons_for_cycle`); see
`World._bot_input`. On joining it slots its status abilities first
(`BuildService.bot_slot_status_abilities`); it uses Bloodlust as soon as its target is
within 2 m on its own turn or in the ability phase, then a hitting ability; the ability
phase's first press prefers a knockback ability, then a self-buff, then a status ability),
`--bot-party` (with `--bot`: the lower peer id invites the nearest player, and the bot
accepts any invite; it doesn't attack or use abilities until it's in a party, then
still swings at its ally when no Husk is near, which the server ignores; see
`PartySystem._bot_step`), `--verbose` (log positions every 2 s, server logs hits and
refused build changes), `--hitboxes` (start with hitboxes shown; F3 toggles),
`--mastery-panel` (open the K panel at start, for screenshot checks),
`--perf-log` (print every frame slower than 50 ms with the time since launch, plus a
`SUMMARY perf` line with the worst frame and worst physics step; for chasing lag),
`--screenshot-dir=PATH` (save the game window every 0.25 s, for checking visuals; a
relative path avoids trouble with the space in the project path),
`--quit-after=SECONDS` (prints `SUMMARY` lines, used by the smoke test),
`--tune=file/section/key=value` (repeatable; overrides a `data/` value for that run;
give the server and every client the same overrides; only keys that exist in the file
can be overridden, strings need no quotes). The smoke test uses `--tune` for low health
and a fast respawn so deaths happen within the run, and to switch on effects that are off
in the real data (Husk swings bleed, Broadsword heavies push) so its status and force
checks don't depend on bot luck.

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

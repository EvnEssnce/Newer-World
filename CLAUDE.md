# Newer World

Small online action RPG (10–50 players per server) with combat, gathering, crafting and
loot modeled on New World: Aeternum, using low-poly art. Godot 4.7, GDScript. The project
brief, build order and outstanding work are in `PROGRESS.md`.

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
  world/build_service.gd  World/Builds node: class/weapon/mastery/Wing requests (RPCs), validation.
  player/player.gd   One player; server/local/remote roles (see below), health, visuals
                     (incl. placeholder wings, the Rebirth fire and the Juggernaut
                     weapons, built in code: `_build_halberd_greataxe`,
                     `_build_hammer_model`/`_show_hammer`).
  player/player_movement.gd  Shared deterministic sim step: PlayerState + physics.
  player/player_state.gd     Stamina, dodge, attacks, abilities, cooldowns, weapon swap,
                             stagger, death, facing, Wing abilities, Ember, Rebirth.
                             Pure logic, unit tested.
  player/player_params.gd    Player tuning converted to ticks/radians, every weapon and
                             Wing set, Ember/Rebirth, loaded once.
  combat/attack_params.gd    One attack's tuning (phases, hit windows, damage, hitbox). Players and enemies.
  combat/ability_params.gd   An ability: AttackParams + cooldown, dash, parry/counter, ember_cost.
  combat/weapon_params.gd    One weapon: light/heavy attacks, ability pool (data/weapon_<id>.cfg).
  combat/wing_params.gd      A class's Wing ability pool (data/wings_<class>.cfg).
  combat/melee_hitbox.gd     Box/radial/cone hitbox vs capsule test, frontal arc. Pure math, unit tested.
  combat/force_params.gd     An attack's forced movement (force_* keys): knockback/pull/push, launch.
  combat/forced_motion.gd    A push/launch in progress (players: in PlayerState; enemies);
                             pushed_into_wall (Tempest Wings). Unit tested.
  combat/heavy_counter.gd    Counts heavies once each (War Hammer Earthshaker). Unit tested.
  combat/hit_feedback.gd     Floating combat text over whoever was hit (client).
  combat/projectile_params.gd  One projectile kind (data/projectiles.cfg [projectile_<id>]).
  combat/projectile.gd       One projectile in flight: steps, boomerang legs, pierce, hit-once
                             bookkeeping, swept segment-vs-capsule test. Pure logic, unit tested.
  combat/projectile_system.gd  World/Projectiles: server flight + hits, spawn/turn/end events,
                             client copies (render clock / local cosmetic copy).
  combat/projectile_visual.gd  Client look: feather (quill + vane + streak), spinning axe or
                             wave (a crescent on the ground: Shockwave).
  build/class_def.gd         A class (data/class_<id>.cfg): allowed weapons, default loadout.
  build/mastery_tree.gd      A weapon's mastery tree (or a class's Wing tree) and its rules.
                             Pure logic, unit tested.
  build/character_build.gd   Class + equipped weapons + per-weapon tree allocation and slots
                             + Wing tree allocation and Z/C slots.
  enemy/enemy.gd/.tscn       One enemy: server runs its brain, health, death; clients interpolate.
  enemy/enemy_brain.gd       Enemy AI state machine. Pure logic, unit tested.
  enemy/threat_table.gd      Threat per player, target choice, taunts. Pure logic, unit tested.
  enemy/enemy_params.gd      Enemy tuning from data/enemy_<kind>.cfg.
  enemy/damage_meter.gd      Damage/DPS of one fight (the training dummy's readout). Unit tested.
  items/item_database.gd     Rarity, item, affix and loot table definitions; validate().
  items/item.gd              One rolled item (plain data, to_dict/from_dict).
  items/loot_roller.gd       Rolls loot tables and items (and a kill: one roll per contributor).
                             Pure logic, unit tested.
  items/inventory.gd         One player's items (slots, uids). Pure logic, unit tested.
  items/gear_score.gd        Gear score curve (New World's) and armor mitigation (data/gear.cfg).
                             Pure, unit tested.
  items/equipment.gd         Equipped gear: equip slots, class locks, weapon items following the
                             loadout, stat totals (Equipment.Stats). Pure logic, unit tested.
  items/ground_loot.gd       Personal drops on the ground: owner, reach, expiry, partial
                             pickups. Pure logic, unit tested.
  items/loot_system.gd       World/Loot: kill rolls, drop/pickup/discard/equip RPCs, inventories
                             and equipment; client drop visuals, pickup prompt, bot pickups/equips.
  items/loot_drop_visual.gd  Client look of a drop: sack, rarity beam, best item's name.
  party/party_rules.gd       Parties, invites, ally rule. Pure logic, unit tested.
  party/party_system.gd      World/Party: party RPCs, server validation, client keys/HUD/bot.
  status/status_def.gd       One status effect's tuning (data/status_effects.cfg).
  status/status_defs.gd      Every status, by index (what the network sends); validate().
  status/status_effects.gd   One owner's statuses: apply/stack/refresh, tick, queries,
                             cleanse, on-hit (Bloodlust), immunities, taunt source.
                             Pure logic, unit tested.
ui/                  connect_menu (client start screen), hud (health/stamina/Ember bars, ability
                     bar, Wing slots, weapon line, status row, Rebirth banner, debug info),
                     mastery_panel (K: equipped weapons, weapon trees and a Wings tab, respec, slots),
                     party_hud (party frames, invite prompt, party notices; built in code),
                     loot_hud (pickup prompt, loot feed, equip bar) and inventory_panel (I:
                     equipped gear and the bag).
data/                Tuning files: network, movement, combat, camera, enemy_husk, enemy_dummy,
                     weapon_<id> (broadsword, spear, dual_axes; Juggernaut: halberd,
                     greataxe, war_hammer), class_<id> (fighter, juggernaut),
                     mastery (shared tree rules), mastery_<weapon>, wings_<class> (Wing
                     abilities), mastery_wings_<class> (Wing tree), ember (Ember + Rebirth),
                     loot (rarities + loot tables), items, affixes, gear (gear score curve,
                     armor, equip time), party, status_effects, projectiles (.cfg).
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
  `[seq, move: Vector2, buttons: int, aim_yaw: float, aim_pitch: float]`. `move` is a world-space XZ
  direction (camera rotation already applied), length ≤ 1. `buttons` holds
  `PlayerState.BUTTON_*` bits: jump (1), attack (4) and block (8) are sent while held;
  dodge (2), swap (16), abilities 1–3 (32/64/128, Q/E/R) and Wings 1–2 (256/512, Z/C)
  only on the tick they're pressed (the sim buffers them). Tap vs hold (light vs heavy) is decided inside the sim
  from the held attack bit. `aim_yaw` is the camera yaw; attacks, abilities and block
  face it. `aim_pitch` is the camera pitch (radians, up = positive; the server clamps
  it to ±90°; bots send 0); only pitch-aimed dashes use it. New actions get new bits.
- **Server**: queues inputs per player (validated, bounded by `max_input_buffer`) and
  simulates at most `max_inputs_per_tick` per tick. **One input = one sim step**; a
  player with no queued input doesn't move. That keeps server and client in lockstep.
- **Server → each client**, `snapshot_rate` times per second, `World._receive_snapshot`
  (unreliable ordered, channel 2): `tick` and every player's
  `[peer_id, position, velocity, last_processed_seq, PlayerState.to_array(),
  Vector2(health, max_health)]` (max health includes gear; one Vector2 is the size of
  the old float health).
  Snapshots also drive spawning/despawning on clients: new id → spawn, missing id → remove.
- **Local player**: applies each input immediately and remembers the predicted position
  and `PlayerState` per seq (keeping the latest acknowledged one, since two snapshots
  can acknowledge the same seq). On a snapshot, if the server's position or state for
  `last_processed_seq` differs from the prediction, it restores the server's position,
  velocity and state and replays unacknowledged inputs. "Corrections" on the HUD count
  only unexpected ones and should stay 0 on localhost; a mismatch caused by a server
  event (`PlayerState.server_events` changed: blocked hit, stagger, death, respawn,
  parry counter, ability stopped on hit, loadout or Wing slot change, a status
  applied/used up/cleansed by the server, forced movement, Ember gained, Rebirth
  started/finished, equip time started) isn't counted. `--verbose` logs
  each unexpected one, and server-side input drops.
- **Loot** (`World/Loot`, `LootSystem`; see "Loot"): reliable RPCs. Client → server
  `_request_pickup()` (no arguments: the server picks up the sender's own drops in
  reach of its server position), `_request_discard(uid)`, `_request_equip(uid,
  equip_slot)` and `_request_unequip(equip_slot)`; server → that client only
  `_receive_drop(id, position, items)` (new or what's left of one),
  `_receive_drop_removed(id)`, `_receive_inventory(items, slots, equipment)`,
  `_receive_picked(items)` (the feed), `_receive_equip_started(text, ticks)` (the
  equip bar's label) and `_receive_notice(text)`. Items travel as `Item.to_dict()`.
  Never in snapshots. The only sim state it touches is the equip time
  (`PlayerState.start_equip`, a server event) and, for weapon items, the loadout
  (through `BuildService.apply_weapons`).
- **Builds** (`World/Builds`, `BuildService`): the client sends its class in
  `World._client_ready(class_id)`; the server gives the player its class's default
  `CharacterBuild`. Reliable RPCs: client → server `_request_mastery(weapon_id, nodes,
  slots)` (a whole tree allocation + Q/E/R ability ids: a free respec),
  `_request_wings(nodes, slots)` (the Wing tree allocation + Z/C ability ids) and
  `_request_weapons(weapons)`; server → client `_receive_build(build_dict, error)` after
  every request and on join. The server validates (class weapon list, mastery rules, not
  mid-attack/ability/swap) and puts what affects the sim (equipped weapon ids, slotted
  ability indices, Wing set and slots) into `PlayerState.set_loadout` / `set_wings`,
  server events, so it reaches the client through snapshots. Passive/upgrade nodes are
  server-only damage/stamina/damage-taken modifiers, never sim state.
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
  31 = `dodge_cooldown` (ticks after a roll before the next, `[dodge] cooldown`);
  32 = `ember` (float); 33 = `wing_set` (class id, "" = no Wings); 34 = one
  `PackedInt32Array` (kept small for snapshot size): `[combat_ticks, rebirth_left,
  rebirth_cooldown, rebirth_charges, Z slot, C slot, equip_left, Wing cooldowns by
  pool index without trailing zeros]` (`PACKED_WING_HEADER` = 7; new small ints can
  go in that header too); 35 = `attack_speed_carry` (float, Rampage: see "Attack
  speed" under Status effects). Append new fields at the end. A player's snapshot entry is
  about 520 bytes, so 2 players + 2 Husks is ~1.3 KB, near ENet's 1392-byte MTU: a third
  player already goes over it (Godot warns "above the MTU"); interest management /
  delta compression will be needed before bigger tests.
  Enemy snapshots: `[id, kind, position, yaw, mode, attack_tick, health, dead,
  statuses (same packing)]`.
- **I-frames**: `PlayerState.is_invulnerable(params)`: a dodge's window, or an ability's
  `iframe_start`/`iframe_end` (Vault). Clients flash the body white while it's true.
- **Forced movement** is sim state too: `PlayerState.force` (a `ForcedMotion`: horizontal
  velocity, ticks left, pending launch speed) is entries 28 (velocity), 29 (ticks) and 30
  (launch) of `to_array()`. The server starts it (`start_force`, a server
  event); `PlayerMovement` applies it on both sides, so the client replays it exactly.
- **Projectiles are never in snapshots** (packet size). `World/Projectiles`
  (`ProjectileSystem`, both sides) sends reliable events to every player: on a throw
  `_receive_spawn(id, kind, owner, origin, velocity, server_tick)`, then
  `_receive_event(id, type, age, position)`: `type` 0 = TURN (a returning one turned
  back: its timer, a wall or its pierce), else `Projectile.END_*` (1 hit, 2 wall, 3
  expired, 4 caught) with where it stopped; `age` = steps flown. Clients fly a copy with
  the same `Projectile.step` math and apply each event when their copy reaches that age.
  Other players' throws run on the render clock (age = render tick − spawn tick), so they
  leave the thrower as drawn. The local player's own throw shows at once: its predicted
  attack reaching the release tick emits `Player.projectile_released` (also on the server,
  which throws the real one) and the client makes a cosmetic copy on its own clock; the
  server's spawn confirms the oldest unconfirmed copy of that kind (unconfirmed after 0.5 s:
  removed), and late events rewind it to the event and re-fly the difference. Nothing
  about projectiles touches the thrower's predicted sim beyond the attack timeline, so they
  cause no corrections.

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
  `shape="radial"` (Whirlwind Edge, Crashing Leap slam; with `arc` (degrees) a cone in
  front, `AttackParams.hitbox_arc`: Seismic Slam; the F3 debug draws the full circle), dash (`dash_distance`, moved in
  `PlayerMovement` like a dodge: Shield Charge, Crashing Leap, Lunge;
  `dash_direction="back"` dashes away from the facing, `"input"` the way the movement input
  points, backward with none: Vault; `dash_ease="in"` speeds up over the dash, same
  distance, `AbilityParams.dash_speed_at`: Diving Strike; `dash_aim_pitch` with
  `aim_full_pitch`/`aim_zero_pitch` shortens it as the camera looks up, to 0 m:
  Crashing Leap, the fraction stored as the length of `PlayerState.ability_dir`, so
  `to_array()` didn't change; cosmetic `leap_height` peaks at `leap_peak` of the dash,
  `AbilityParams.leap_lift`), ability i-frames (`iframe_start`/`iframe_end`:
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
  low_health_damage, block_stamina, execute_damage, hold_the_line, hook_stagger,
  crit_staggered, ability_range, ramp_on_hit, heavy_shockwave, heavy_breaks_block,
  none; Wing trees add damage_taken, mantle_heal, surge_stagger, force_distance,
  wall_stun, roar_guard; a node may name a `status`). `MasteryTree.covers(applies_to,
  kind, ability_id)` is the one "does this node apply to this attack" rule. Respecs are free any time except
  mid-attack/ability/swap. K opens the panel. A tree file may set its own `[tree] points`
  (the Wing tree does).
- **Execute damage** (Spear capstone **Finishing Thrust**, `effect="execute_damage"`,
  `amount` 0.6, `threshold` 0.3): the one per-*target* damage factor.
  `Player.execute_bonus()` = (amount, threshold) of the weapon that's out (zero for a
  Wing ability); `MasteryTree.execute_multiplier(bonus, target health fraction)` = 1 +
  amount × (1 − fraction / threshold) below the threshold. It's passed as the optional
  `execute` argument of `_strike_player` / `resolve_strike` / `strike_enemy`; a
  projectile captures it at release (`Projectile.execute`) like `damage_scale`. An
  attack can have its own (`execute_damage` / `execute_threshold` keys →
  `AttackParams.execute`: Executioner's Swing); `World._execute_scale` multiplies the two.
- **Hold the Line** (Spear Lancer capstone, `effect="hold_the_line"`, `applies_to` = the
  internal ability `line_poke` in `weapon_spear.cfg`: its box, damage 40, Slow 2 s, and
  its `cooldown` (2 s) is **per target**). Server only (`World._hold_the_line`, every
  tick after enemies move): while a player with the node and that weapon out is
  blocking, each hostile player or living enemy that *enters* the poke's box (outside
  last tick, inside now: `Player.line_inside` / `line_ready_at`) is struck once through
  `resolve_strike` / `strike_enemy` (allies skipped; blocks, i-frames, parries,
  statuses, Ember, execute as usual). Never touches the holder's `PlayerState`, so
  nothing to predict. No poke animation yet (the hit label shows it).
- **Shield Wall** (Broadsword Vanguard tier 2, ALLY): a short cast that self-buffs
  `shield_wall` (6 s; `cover_depth` 2.5 m, `cover_width` 1.8 m in
  `status_effects.cfg`). In `resolve_strike`, after the target's own parry, a target
  not guarding the hit itself (`_guards_against`) is covered by a blocking ally with a
  cover status (`StatusEffects.cover_box`) that faces the attacker within its block arc
  and has the target inside the box straight behind it (`MeleeHitbox.is_behind`):
  `_covered_hit` runs the normal blocked-hit path on the holder (stamina, guard break +
  force, `block_damage_taken`) and the target takes nothing; both get a hit event (the
  target a 0-damage `HIT_BLOCKED`) and `resolve_strike` returns `HIT_BLOCKED`, so
  melee, Husk swings and projectiles (a guard-stopped one stops) are all covered.
  Counted as `shield_wall_covers=` on the `SUMMARY party` line.
- **War Hammer** (Juggernaut, `data/weapon_war_hammer.cfg`, model "war_hammer"): slow
  and heavy (light 95 dmg 0.2 s stagger; heavy 240 dmg 0.7 s stagger, 0.6 s windup,
  `breaks_block=false`; turn speed 420°/s). Abilities: Seismic Slam (90° cone 4 m,
  stagger 0.8 s, knockback 2 m), Clout (one target, Stun 1.5 s), Shatter (Shattered),
  Upheaval (3 m radial launch 1.5 m), Shockwave (projectile "shockwave": a low, flat,
  piercing wave, 14 m/s, ~10 m, stagger 0.6 s, a guard doesn't stop it), Steadfast
  (self). Tree `mastery_war_hammer.cfg`: Earthshaker (Slam, Upheaval, Shockwave) and
  Breaker (Clout, Shatter, Steadfast); default slots Slam, Clout, Upheaval. Capstones
  (server, `World._with_hammer_capstones`, every live heavy tick): **Earthshaker**
  (`heavy_shockwave`: `Player.heavy_counter` (`HeavyCounter`, by `attack_serial`) sends
  the internal `aftershock`'s wave every `amount`-th heavy via
  `ProjectileSystem.server_fire_attack`; no cosmetic copy waits on the thrower's
  client, so it draws the server's spawn on the render clock) and **Breaker**
  (`heavy_breaks_block`: the heavy's hits use `AttackParams.copy()` with
  `breaks_block=true`, made after `damage_multiplier`, which tells heavies apart by
  identity). Counted on the `SUMMARY juggernaut` line (aftershocks, wall_stuns,
  roar_guards; not checked).
- **Forced movement** (the `FORCE` tag: knockback, pull, launch). Per attack, optional
  `force_direction` ("away" / "toward" / "forward"), `force_distance` (m),
  `force_height` (launch peak, m), `force_duration` (s), `force_needs_stagger` (only
  moves a target already staggered: Rising Cut) in the weapon or enemy file; shared
  limits in `[force]` of combat.cfg (max distance/height, pull gap). `ForceParams`
  computes the displacement, launch speed and ticks (at least the launch's airtime).
  Server only decides it: `World._force_player` / `_force_enemy`, after a hit that
  damaged or guard-broke (not evaded, blocked, parried or fatal), never between allies
  (`are_allies`). `PlayerState.start_force` refuses i-frames, death and
  `is_force_immune(params)` (the one immunity hook: a `force_immune` status, see
  "Status effects"). **Choice:** being moved interrupts like a stagger (attack, ability,
  dodge, swap, guard), and the target can't act until it ends; presses stay buffered.
  `PlayerMovement` sets the horizontal velocity from it (linear ease-out, so the
  distance is exact) and the launch speed on its first step; gravity and
  `move_and_slide` (walls) do the rest, and on-floor stays synced state. Enemies:
  `Enemy.start_force` (server) staggers the brain for the same ticks, so steering and
  swings pause. Players show the stagger tilt while moved.
- **Projectiles** (the `PROJ` tag). Kinds in `data/projectiles.cfg` (`[projectile_<id>]`:
  speed, gravity, pitch, lifetime, hit_radius, pierce, walls, stopped_by_guard, release
  point, optional `returns`/`return_after`/`return_speed`/`catch_radius`, and the look:
  `visual` "feather", "axe" or "wave", length, color, spin). An attack or ability throws with
  `projectile` (kind id), `projectile_time` (s from its start), optional
  `projectile_count`/`projectile_spread` (degrees); usually `shape="none"`. Its damage,
  stagger, block cost, statuses and `force_*` are what the projectile's hit does,
  scaled by the thrower's modifiers at release (`damage_multiplier`, damage-dealt
  statuses). The release is the predicted attack timeline; the projectile is server
  state. **Server** (`ProjectileSystem.server_step`, once per tick after players and
  enemies): `Projectile.step` (gravity; a returning one turns at the start of a step and
  steers toward its thrower's current server position, or the throw origin if the
  thrower is gone/dead), then the step's segment: a ray against layer 1 (walls/ground;
  a returning one turns back there, and ignores the world on its way back), and a swept
  sphere vs every player/enemy capsule (`Projectile.sweep_capsule`, no tunnelling),
  nearest first. Each target is hit once per projectile, once **per leg** for a
  boomerang (`Projectile.results`; an evade doesn't count). Players go through
  `World.resolve_strike` (the rest of `_strike_player`, with the attacker position = 2 m
  back along the projectile's path): allies ignored (it flies on), i-frames evade (flies
  on), a guard facing where it came from blocks (stamina; stops it if
  `stopped_by_guard`), statuses (+ the thrower's on-hit statuses, taken once per
  projectile) and force on `HIT_DAMAGED`, Ember as usual. **A Riposte parries
  projectiles** from the front like melee (negated, stops a `stopped_by_guard` one; the
  counter turns toward where it came from). Enemies: `World.strike_enemy` (same as
  melee). `pierce` = targets it passes through (0 = stops at the first); a returning one
  that runs out turns back instead.
  Fighter: Spear **Javelin Cast** (feather javelin, 28 m/s, ~22 m, slows 3 s) and Dual
  Axes **Boomerang Axe** (9 m out, back to the thrower, pierces, hits each target once
  each way; a guard doesn't stop it). Both are tier-1 nodes in their trees and in the
  default allocation, not in the default slots (slot them in K).
- Health is server-owned, outside `PlayerState` (clients don't predict damage), sent in
  snapshots. Hit events go to clients via reliable `World._receive_hit` (`HIT_*`
  results) for damage numbers, labels and the red flash.
- **Stagger**: a hit with `stagger > 0` (weapon file; heavy only by default) calls
  `PlayerState.apply_stagger`: interrupts the target's attack/dodge, and it can't act
  until it ends (presses stay buffered).
- **Death**: at 0 health the server calls `PlayerState.kill()`; dead players can't act,
  can't be hit, and lie grey on the ground. Then a Rebirth if eligible (see "Ember,
  Wings and Rebirth"); otherwise after `[death] respawn_time` the server
  `_respawn`s them at a random point on the spawn circle with full health and stamina
  (`revive()`, Ember back to resting). The client shows a countdown banner from the
  `HIT_DEFEATED` event.
- No lag compensation yet: hits use targets' current server positions, while the
  attacker sees them `interpolation_delay` in the past.

## Juggernaut (Halberd, Greataxe)

`data/class_juggernaut.cfg` (`--class=juggernaut`, `-Class juggernaut` for the run and
smoke scripts). Heavier and slower than the Fighter's weapons (turn_speed 540, longer
windups/recoveries, bigger numbers). Placeholder models are built in code in
`player.gd` (`_build_halberd_greataxe`, poses in `_halberd_pose` / `_greataxe_pose`).
Every new mechanic is server-only (no new `to_array()` fields); the `World` helpers sit
in one block, "Juggernaut: Halberd and Greataxe mechanics", and the bot needs nothing
special (it slots self-buffs, statuses and Hurl like any weapon).

- **Halberd** (`weapon_halberd.cfg`, tree `mastery_halberd.cfg`: Warden / Headsman).
  Light = reaching sweep (3 m × 2 m), heavy = overhead chop (3.4 m). Hooking Pull (5.5 m
  line, `max_targets` 1, pull 4.5 m, marks **Hooked**), Wide Reap (3.6 × 6 m sweep),
  Pole Vault (6 m dash + 1.6 m cosmetic leap, 2.3 m radial landing, knockback 2.5 m),
  Brace (self-buff **Braced**), Cleaving Arc (overhead chop, Exposed), Crowd Sweep
  (3 × 4.5 m box, push 4 m). Defaults: all six learned, Q/E/R = Hooking Pull, Wide Reap,
  Crowd Sweep.
- **Greataxe** (`weapon_greataxe.cfg`, tree `mastery_greataxe.cfg`: Maelstrom /
  Bloodied). Light = wide diagonal cleave (2.2 × 2.8 m), heavy = big chop. Vortex (3
  radial windows of 3.5 m, each pulling in; the body spins like Whirlwind Edge),
  Charging Chop (6 m dash, chop at the end), Grounding Blow (3.2 m slam, Slow 3 s),
  Executioner's Swing (attack-level execute: +150% at 0 health from 30%), Iron Hide
  (self-buff), Hurl (`[projectile_greataxe]`, ~15 m, stops at the first target, Slow
  5 s; the model leaves the hands in flight via `set_axe_thrown`). **Choice:** no
  pickup: "slowed until you pick the axe up" is a fixed 5 s slow. Defaults: all six
  learned, Q/E/R = Vortex, Charging Chop, Grounding Blow.
- **Brace** (`charge_stagger` 1 s, `charge_window` 1 s on `status_braced`): a melee hit
  (`_strike_player`, not projectiles) that lands on a Braced player (damaged, blocked or
  guard broken) staggers the attacker if it's a **charge**: the attacking player was
  mid-dash (`PlayerState.is_dashing`), or the hit landed within the first second of
  Braced (`StatusEffects.charge_stagger_ticks`, using the entry's `elapsed`). Enemies
  get `brain.stagger`; immunities apply. `World._brace_counter`.
- **Iron Hide** (`status_iron_hide`: `crowd_damage_taken` −0.08 per hostile within
  `crowd_radius` 5 m, at most `crowd_max` 5 → −40%, 6 s): `World._crowd_multiplier`
  counts living enemies and non-allied players around the target and multiplies the
  damage taken in `resolve_strike`, `_covered_hit` and damage over time
  (`StatusEffects.crowd_damage_taken_multiplier`).
- **Crits** (`[crit] damage_multiplier` 1.5 in combat.cfg, `PlayerParams.
  crit_damage_multiplier`): the Headsman capstone **Headsman's Verdict**
  (`effect="crit_staggered"`, `applies_to="heavy"`): a covered attack on a target that
  was staggered *before* the hit crits (`Player.crit_multiplier` →
  `MasteryTree.crit_multiplier`; `World._crit_multiplier` in `resolve_strike` /
  `strike_enemy`). Clients get `HIT_CRITICAL` (8) instead of `HIT_DAMAGED` (only on the
  wire; server results stay `HIT_DAMAGED`) and show "Critical! -N". Gear crit chance
  can reuse the multiplier.
- **Caught on the Hook** (Warden capstone, `effect="hook_stagger"`, `applies_to="hooked"`,
  `amount` 0.8 s): Hooking Pull always applies **Hooked** (2.5 s debuff, no effect of its
  own; `Entry.source` = the hooker). With the node (Halberd out), the hooker's next
  damaging hit on that target staggers ≥ 0.8 s and removes the mark
  (`World._with_hook_stagger`; players via `PlayerState.remove_status`, a server event).
- **Maelstrom** (`effect="ability_range"`, `applies_to="vortex"`, `amount` 2): the
  server tests the ability's hitbox with `range` × amount (`AttackParams.range_copy`,
  `World._with_range_upgrade` in `_on_attack_stepped`), so Vortex hits and pulls from
  7 m. F3 still draws the base 3.5 m.
- **Red Tide** (Bloodied capstone, `effect="ramp_on_hit"`, `applies_to="bloodied"`): each
  step a melee attack/ability connects (`_on_player_attack_connected`) gives the attacker
  a stack of **Bloodied** (+3% damage dealt per stack, max 8, 2.5 s, refreshed per hit).
  Projectile hits don't add stacks.
- Counters: `SUMMARY juggernaut crits= hook_staggers= brace_staggers= bloodied_stacks=`
  (server, no smoke check).

## Status effects

- `data/status_effects.cfg`, one `[status_<id>]` each: `category` = **debuff** (never
  from an ally; removed by a cleanse) or **buff**; `affects` = **sim** (changes
  movement/actions, predicted: slow, root, stun, rampage) or **damage** (server-only
  numbers: bleed, exposed, damage_up, damage_reduction, bloodlust, pyre_heart's healing,
  shield_wall's cover; also the server-decided immunities and taunt).
  Duration, max_stacks, then
  only the keys for what it does. Reapplying adds stacks (capped) and resets the time to
  full (never shortens). `StatusDefs.validate()` checks the file (a unit test runs it).
- **Players**: `PlayerState.statuses` (synced in `to_array()`), ticked down at the top of
  `PlayerState.step`. Slow scales walking speed and root stops walking/dodging/jumping/
  dashing in `PlayerMovement`/`can_dodge`. **Stun = stagger**: applying a stun staggers
  for its duration (same interrupt and "can't act"); the status entry is the name/timer
  and what a cleanse removes (`cleanse()` also ends the stagger). Enemies: stun =
  `brain.stagger`.
- **Attack speed** (`attack_speed` 1–2, `attack_speed_min_stamina` fraction; Rampage
  1.25 at ≥ 50% stamina): `StatusEffects.attack_speed(defs, stamina fraction)`. In
  `PlayerState._step_attack_speed`, a light or heavy attack (not abilities) adds
  (speed − 1) per tick to `attack_speed_carry` (synced, index 35); each whole tick
  skips the tick just reached, but only a windup or recovery tick (never from the first
  hit window to the last, never a projectile release), else it waits for the next one.
  So hit windows keep every tick; the carry resets when the attack ends.
- **Server events vs prediction**: the server applying a status (`apply_status`), using
  up an on-hit stack (`take_on_hit_statuses`) or cleansing (`cleanse`) bumps
  `server_events`. A self-buff from your own attack/ability (`self_status`) starts inside
  `step()` (`_apply_self_status`), so it's predicted.
- **Applying**: attack/ability keys `applies_status`, `status_stacks`, `status_duration`
  (target, server, on `HIT_DAMAGED` only: not blocked/evaded/parried/killing hits), a
  second one for the same targets with `applies_status_2`, `status_stacks_2`,
  `status_duration_2` (Challenger's Roar; `AttackParams.target_statuses()`), and
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
  Healing over time (`heal_per_second`, Pyre Heart): `StatusEffects.heal_due` →
  `PlayerState.status_heal` → `Player.status_heal_pending` → `World._heal_player`.
- **Healing**: every heal goes through `World._heal_player(target, amount, healer_id)`:
  capped at max health, gives the healer Ember (`per_heal`), reported as `HIT_HEALED`
  (green "+N"). Use it for future ally heals too.
- **UI**: HUD status row (local player, predicted: name, stacks, seconds; green edge =
  buff, red = debuff); a status line under remote players' and Husks' health.
- Fighter status abilities: Broadsword **Opening Strike** (Exposed), Dual Axes
  **Bloodlust** (self-buff: next 4 hits bleed) and **Hamstring** (Slow, default axes R
  slot), Spear **Skewer** (Root 1.5 s, Lancer tier 2) and **Perforate** (5 thrusts, each
  its own hit window adding a bleed stack; Impaler tier 2; both in the default
  allocation, not the default slots), Dual Axes **Rampage** (self-buff, attack speed;
  Berserker tier 2) and Broadsword **Shield Wall** (self-buff, cover; Vanguard tier 2),
  both in the default allocation, not the default slots. The Fighter Wings apply damage_reduction (Ember
  Mantle), damage_up (Wingbeat Surge) and pyre_heart. Juggernaut: War Hammer **Clout**
  (Stun 1.5 s), **Shatter** (Shattered: +15% damage taken per stack, 2 stacks, 8 s),
  **Steadfast** (self); Wings **Challenger's Roar** (Taunted + Slow 3 s), **Unbowed**
  (self); the Anchor capstone's **Defiant** (−6% damage taken per stack, up to 5).
- **Immunities** (server-decided keys; they refuse what would be applied, never remove
  what's there): `force_immune` (`PlayerState.is_force_immune` / `Enemy.is_force_immune`
  refuse knockback, pull, launch), `stagger_immune` (`PlayerState.apply_stagger(ticks,
  params)` refuses hit staggers and guard-break staggers (the stamina is still taken);
  enemies skip `brain.stagger` in `take_hit`; stuns are refused), `cc_immune` (refuses
  crowd-control debuffs, `StatusDef.is_crowd_control`: slow, root, stun, taunt).
  `StatusEffects.apply` checks `refuses()` itself, so players and enemies both respect
  it. Prediction is safe: the statuses are synced, and stagger, force and applied
  statuses only ever come from the server. Juggernaut buffs: **Braced** (force immune,
  3 s; Halberd Brace, see "Juggernaut"), **Steadfast** (force + stagger, 4 s; War
  Hammer), **Unbowed** (all three, 4 s; Wings).
- **Taunt**: `forces_target=true` (debuff only, `validate()` checks), status
  **Taunted** (4 s; Challenger's Roar applies it). On an enemy,
  `Enemy.apply_status` calls `brain.taunt(source)` (threat to the top) and
  `server_step` sets `brain.forced_target` from `StatusEffects.forced_target()` (the
  entry's server-only `source`) while it lasts. No effect on players.

## Ember, Wings and Rebirth

- **Ember** (`data/ember.cfg [ember]`, every class): `PlayerState.ember`, 0..cap
  (`ember_cap(params)` is the one place that reads the cap, for later upgrades). It's
  sim state because it decides whether a predicted Wing ability can start. **Gains are
  server events** (`gain_ember`): `World._ember_from_damage` gives the target
  `per_damage_taken` and the attacking player `per_damage_dealt` for every hit and
  damage-over-time tick (players and Husks; before a fatal hit kills, so it counts
  toward a Rebirth), `_heal_player` gives the healer `per_heal`. **Spending** (a Wing
  ability's `ember_cost`) and **settling** happen in `step()`, so they're predicted.
- **In combat**: `PlayerState.combat_ticks` (synced) is set to `combat_time` by any
  damage gain (dealt or taken, even a fully blocked hit; healing doesn't count) and
  counted down in `step()`. At 0, Ember moves toward `resting` (50) by
  `settle_per_second`, refilling or draining. Frozen while dead. Spawn and respawn
  start at resting.
- **Wing slots** (Z / C, `BUTTON_WING_1/2`): `PlayerState.wing_set` (class id; pool =
  `PlayerParams.wing_set(id)`, from `data/wings_<class>.cfg`, same ability format as
  weapon files + `ember_cost`), `wing_slots` (pool indices), `wing_cooldowns` (per pool
  index). A Wing ability is `attack_type == ATTACK_WING`, `ability` = pool index, on the
  same attack timeline as weapon abilities (dashes, i-frames, statuses, force, hit
  windows, `is_using_ability()`/`current_ability()` cover both; `is_using_wing()` tells
  them apart). It needs its cooldown at 0 and `can_afford` (Ember ≥ cost); an
  unaffordable press stays buffered for `[abilities] buffer`. Weapon swaps don't touch
  Wings (a queued Wing press survives a swap). Weapon abilities could cost Ember too
  (`ember_cost`, 0 for all so far; the Mage will use it).
- **Wing tree** (`data/mastery_wings_<class>.cfg`, `MasteryTree.for_wings`, 2 slots,
  `[tree] points` = 12 for now): Fighter branches Bulwark and Fury. Same rules and free
  respecs; K panel "Wings" tab. Its passives apply to every attack
  (`CharacterBuild.damage_multiplier`); a Wing ability gets only the Wing tree's.
  Capstones (server, `World`): **Mantle of Renewal** (`mantle_heal`: while Ember
  Mantle's Warded is on, heal half the damage it prevented, `_mantle_heal`) and
  **Crushing Wingbeat** (`surge_stagger`: while Wingbeat Surge's Empowered is on, hits
  stagger ≥ 0.3 s, `_with_surge_stagger`).
- **Fighter Wings** (`data/wings_fighter.cfg`): Ember Mantle (25 Ember, Warded −40% 4 s),
  Wingbeat Surge (25, Empowered +20% 6 s), Pyre Heart (30, heals 200 over 5 s), Diving
  Strike (20, 5 m dive: steep rise, then an eased-in swoop whose 2.5 m radial hit
  window covers the second half and the landing; height cosmetic). Defaults: Z Ember Mantle,
  C Wingbeat Surge.
- **Juggernaut Wings** (`data/wings_juggernaut.cfg`, tree branches Tempest Wings and
  Anchor, 12 points): Gale Burst (20 Ember, 12 s: 4 m radial, 60 damage, knockback
  3.5 m), Challenger's Roar (25, 15 s: 8 m radial, no damage, Taunted + Slow 3 s; a guard
  facing you blocks it), Meteor Drop (30, 16 s: 6 m eased-in leap, 4 m cosmetic height,
  3 m radial crash at the landing, 160 damage, launch 1.8 m), Unbowed (25, 20 s: self
  Unbowed). Defaults: Z Gale Burst, C Challenger's Roar. Passives: `force_distance`
  (Strong Gusts / Hurricane +20% each: your "away"/"forward" pushes go farther,
  `ForceParams.scaled`, capped at `[force] max_distance`; `World._force_displacement`),
  damage_taken, block_stamina. Capstones (server, `World`): **Tempest Wings**
  (`wall_stun`: a target your knockback drives into a wall gets `status` (stun) for
  `amount` s, once per knockback, players and enemies: `_force_player`/`_force_enemy`
  set `wall_stun_source`, `_check_wall_stun` runs after each player/enemy moves,
  `ForcedMotion.pushed_into_wall` on `is_on_wall()`/`get_wall_normal()`) and **Anchor**
  (`roar_guard`: each enemy Challenger's Roar taunts gives you a Defiant stack,
  `_roar_guard` from `_give_status`).
- **Rebirth** (`[rebirth]`, every class, server-decided): in `_kill_player`,
  `PlayerState.start_rebirth` runs if `can_rebirth` (Ember ≥ `rebirth_ember_needed()`
  and `rebirth_cooldown` 0, or an extra charge). It spends `cost` Ember, sets
  `rebirth_left` (ticks, counted down in `step()`) and starts the cooldown (which only
  counts down once they've risen). When `rebirth_left` reaches 0, `World._rebirth`
  raises them where they fell with `health_fraction` of max health (`finish_rebirth`:
  like `revive` but keeps the Ember left). Otherwise the normal respawn runs unchanged.
  All of it is synced state (index 34), so the HUD banner and cooldown come from the
  predicted state. **Paladin hooks**: `rebirth_ember_needed()` (threshold modifiers),
  `rebirth_charges` + `grant_rebirth_charge()` (extra Rebirths that ignore the
  cooldown), `reduce_rebirth_cooldown()`.
- **UI**: Ember bar under stamina with a white marker at the Rebirth threshold and a
  line ("Ember 63   Rebirth ready" / "Rebirth in 4:32" / "Rebirth needs 50 Ember");
  Wing slots right of Q/E/R (cost in the corner, red when unaffordable); "Rebirth /
  Rising from the ashes in N" banner; placeholder orange wings during Wing abilities and
  Rebirth, and a fire column rising under a rebirthing body (also seen by others).

## Enemies

- Placed by `Marker3D`s under `World/EnemySpawns` (level data; `metadata/kind` picks
  `data/enemy_<kind>.cfg`). The server spawns one `Enemy` per marker at startup with a
  negative id (`-1`, `-2`, ...), which is also its node name under `World/Enemies` and
  how hit events address it (peer ids are always positive).
- **Server only**: each tick after the players, `Enemy.server_step` runs its
  `EnemyBrain` (IDLE wander → CHASE its threat target → ATTACK when within
  `attack_range` and off cooldown → back to CHASE; STAGGERED when hit by a staggering
  attack; RETURN home past `leash_range` or when nobody has threat, healing on
  arrival). Movement is direct steering, no navmesh yet. Not predicted, so no
  PlayerState-style rules.
- **Threat** (`ThreatTable` in `EnemyBrain.threat`, pure, unit tested; tuning in
  `[threat]` of `data/enemy_<kind>.cfg`): threat per peer id from damage it takes
  (`per_damage`; hits, projectiles, bleed: `Enemy.take_hit`), healing someone it has
  threat on (`per_heal` to the healer: `World._heal_player` → `Enemy.on_heal`), and
  coming within `aggro_range` the first time (`proximity`, nearest first so ties go to
  the nearest). Optional `decay_per_second`. The target is the highest threat, but it
  only switches when a challenger has more than `switch_ratio` × the current target's;
  a swing keeps its target, CHASE/IDLE/end of stagger retarget every tick. Dead or
  departed players drop out (`keep_only(targets)`): the next with threat is chased;
  an empty table means RETURN. Leashing wipes the table, and threat is ignored while
  walking home. A taunt (status `forces_target`, see Status effects) forces the
  target and lifts the taunter to `switch_ratio` × the top. `SUMMARY enemies` adds
  `target_switches`, `taunts` (on enemies) and `heal_threat` (enemies that gained
  threat from a heal).
- Enemy swings go through the same `World._strike_player` as player attacks (evade,
  block, guard break, stagger, death). Player attacks on enemies: damage, threat for
  the attacker, stagger × `stagger_multiplier`; death → respawn at home after
  `respawn_time`.
- Snapshots carry `Enemy.get_snapshot()` per enemy; clients interpolate like remote
  players. The windup is telegraphed by the body glowing red.
- Enemies don't collide with players (layer 4; players and enemies only mask the world).
- **Training dummy** (`data/enemy_dummy.cfg`, marker `TrainingDummy` at z = +18, the far
  side from the Husks): `[ai] stationary=true` makes `EnemyBrain.step` only count down
  staggers (never moves, turns, swings or keeps threat); hits, statuses and forced movement
  still work. `[stats] reset_time` (any enemy; 0 for the Husk): that long without damage
  → `Enemy._reset` heals to full and puts it back home. Clients show the local player's
  damage on it (`DamageMeter`, fed by `Enemy.record_my_damage` from `_receive_hit`):
  "You: N dmg  N DPS  N s", a pause of `reset_time` ends the fight. Bots ignore it
  (`World._nearest_enemy`). Iron Hide counts it as a hostile nearby. No loot
  (`[loot] table=""`); a reset also forgets who hit it (`damaged_by`).
- Abilities hit enemies through the same path (`max_targets` and modifiers apply); a
  Husk swing into a Riposte is parried like a player's.
- Forced movement works on enemies too (server only, `Enemy.start_force`, same
  `force_*` params; `Enemy.is_force_immune()` is the hook: a `force_immune` status). An enemy's own attack can
  have `force_*` keys: the Husk's `force_distance` is 0 (off); the smoke test turns it
  on (0.4 m: a longer shove pushed the bots out of their fights and broke the guard
  check) with `--tune` so predicted players get knocked back in most runs.

## Controls

WASD move, Space jump, Shift dodge, left click tap = light / hold = heavy, hold right
click = block, Q/E/R abilities, Z/C Wing abilities, X swap weapon, K mastery panel (K
or Esc closes it), T/Y/N/L/Delete party (see below), F pick up your loot in reach, I
inventory (I or Esc closes it), F3 hitboxes, Esc frees the mouse.
Panels that need the mouse join the `modal_ui` group: while one is visible, clicks and
wheel scrolls don't recapture the mouse. 1–9 are reserved for later (consumables):
don't bind them to anything else.

## Loot and gear (milestone 2)

- `data/loot.cfg`: rarity tiers (affix count, color) and loot tables (`[table_<id>]`:
  drop chance, rolls, gear score range, item and rarity weights). `data/items.cfg`: item
  definitions (slot, weapon type for weapons, primary stat per gear score).
  `data/affixes.cfg`: bonus stats, their slots and value ranges per 100 gear score.
- **No attributes** (STR/DEX...): `design/classes.md` decided against them. Gear stats
  modify combat numbers directly (damage_pct, crit_chance, max_health, ...).
- Weapon items only name a weapon type (`data/weapon_<type>.cfg` holds the attacks) and
  are class-locked. `weapon_power` is a percent of the weapon file's damage.
- `LootRoller` is server only and seeded by a `RandomNumberGenerator`.
- **Personal loot** (`LootSystem`, server): an enemy's `[loot] table` (enemy file; ""
  = none) is rolled once per player in `Enemy.damaged_by` (anyone whose hit, projectile
  or damage over time took health since it (re)spawned or healed at home) when it dies
  (`World._damage_enemy` → `on_enemy_killed`), `LootRoller.roll_kill`. Each roll that
  drops something becomes its own `GroundLoot.Drop`, `[drops] scatter` m from the body
  (snapped to the ground), seen only by its owner, gone after `[drops] lifetime`. No
  party loot rules needed.
- **Pickup** (F): the server moves the sender's drops within `[drops] pickup_range`
  (horizontal, its own positions; not while dead) into their `Inventory`, nearest
  first; a full inventory (`[inventory] slots`) leaves the rest on the ground with a
  notice. Items get a `uid` in the inventory (requests name items by it). Discard (two
  clicks in the I panel) deletes an item. Inventories live on the server and are lost
  on disconnect (persistence is milestone 5).
- **Client**: `LootDropVisual` (sack, a beam in the best item's rarity color, its name
  drawn on top), the "[F] Pick up" prompt and a feed of pickups/notices (`LootHud`,
  canvas layer 2, above the HUD), `InventoryPanel` (I: newest first, rarity color, kind,
  gear score, `Item.stat_lines`). A `--bot` picks up its drops when within 80% of reach.
  Counted in `SUMMARY loot` (server) and `SUMMARY client=N loot` lines; the smoke test
  checks drops and a pickup (with `drop_chance` 1).
- `ItemDatabase.validate()` checks the three files against each other; a unit test runs
  it on the real data. `tools\roll_loot.ps1 [-Table husk] [-Kills 50000]` prints what a
  table really drops.
- **Gear score** (`data/gear.cfg`, `GearScore`, New World's community-datamined
  curves): an item's main stat = `primary_base` (items.cfg, its value at GS 100) ×
  `factor(GS)`: ×1.0112 per whole 5 GS up to 500, then ×(1 + 0.0112 × 0.6667) per 5.
  Weapon/wing power 100 = the weapon file's damage, so an empty weapon slot (the
  class's plain weapon) is GS 100 and nothing is weaker without gear. **Armor**
  reduces hit damage by `armor / (armor + attacker_gs ^ 1.2)`, attacker_gs = the
  attacking player's weapon item GS (Wing Enhancement during a Wing ability; 100 with
  no item) or the enemy's `[stats] gear_score` (Husk 120). Affix values scale
  linearly (× GS/100).
- **Equip slots** (`Equipment.SLOTS`): Weapon 1, Weapon 2, Head, Chest, Legs, Wing
  Enhancement (item slot "wings"). Armor fits any class; weapons need the class's
  weapon list, Wing Enhancements their `class` (`Equipment.check`). A weapon item
  sits in the loadout slot of its type: equipping one sets that slot's weapon type
  (`BuildService.apply_weapons`; a type already in the other slot goes there,
  `Equipment.weapon_target`), and when the K panel changes the types, weapon items
  follow them or return to the bag (`check_weapon_change` / `weapons_changed`,
  `Equipment.sync_weapons`).
- **Equipping takes `[equip] time` (1 s)**: `_request_equip` → server checks →
  `PlayerState.start_equip` (`equip_left`, synced; refused mid-attack, mid-ability or
  mid-swap (`can_change_loadout`) or dead): walking only (no attack,
  block, dodge, swap, abilities; presses stay buffered), and no K panel changes
  meanwhile. `equip_left` counts down *after* the step's inputs, so on the step it
  ends nothing has started; `Player.equip_finished` (server) then makes the change
  (`LootSystem.finish_equip`). Dying cancels it ("Gear change interrupted").
- **Stats** (`Equipment.stats` → `Player.gear`, server; `bonus_max_health` reaches
  clients in snapshots): `Player.damage_multiplier` × weapon power of the weapon out
  (wing power for Wing abilities) × (1 + damage_pct); `World._crit_multiplier` rolls
  `crit_chance` when the tree doesn't crit; `World._after_armor` in `resolve_strike` /
  `_covered_hit` (not damage over time); `Player.block_stamina_multiplier` ×
  (1 − block_stamina_reduction); `_heal_player` × (1 + healing_pct); `_give_ember` ×
  (1 + ember_gain_pct); `Player.max_health()` = base + max_health (health is capped
  when it drops). `max_stamina` / `stamina_regen_pct` affixes are off (`slots=[]`)
  until stamina gear is synced sim state. Average gear score (inventory title):
  weighted by `[average] weights`, an empty weapon slot = GS 100.
- `SUMMARY gear equips= unequips=` (LootSystem) and `SUMMARY gear_combat gear_crits=
  armored_hits= armor_stopped=` (World); the smoke test checks an equip (its Husks
  drop only armor there, so any class can wear it).

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
  (leader). Q, E, R, X, K, Z, C and 1–9 are taken or reserved (abilities, weapon swap,
  the tree panel, Wing abilities, later).

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
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1            # 2 bots, 32 s: move, dodge, fight each other and Husks, block, die, respawn, abilities, swap, respec, statuses (on a Husk), a bleed tick, Spear, knockback on players and Husks, Ember gained and spent, Wing abilities, a Rebirth, projectiles thrown and one hitting, Husk loot dropped, picked up and equipped
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1 -Party     # same bots in a party: 0 hits, debuffs, forced moves or projectile hits on each other, Husk fights (and Ember, Wings, a Rebirth, projectile hits) still happen
```

Run `run_tests.ps1`, `smoke_test.ps1` and `smoke_test.ps1 -Party` before committing.

**Linux cloud sessions** (no PowerShell, no Godot installed): download
`Godot_v4.7.2-stable_linux.x86_64.zip` from the godotengine GitHub releases into the
scratchpad, run `--headless --import` once, then the same commands the scripts run:
`--headless res://tests/framework/run_tests.tscn` for tests, and for the smoke test a
headless server plus two `--bot` clients with the `--tune` list from `smoke_test.ps1`
(grep it out of the file so it stays in one place), then read the `SUMMARY` lines. For
frames, run a client with `xvfb-run -a <godot> --rendering-driver opengl3 -- --bot
--screenshot-dir=...` (an ALSA audio error there is harmless). Two bots quitting at
the same instant sometimes print `party_members=0` for one of them; that's quit
timing, not a party bug.
Alternatively, PowerShell 7 for Linux (`powershell-7.x-linux-x64.tar.gz` from the
PowerShell GitHub releases) runs the real `smoke_test.ps1`/`run_tests.ps1` with
`GODOT` set, after swapping the `find_godot.ps1` line for `$ProjectRoot`/`$Godot`
and `\` for `/` in the `build\smoke`, `build\tests` and `data\class_$Class.cfg` paths.
That also exercises the script's own argument quoting (a bare quote or space inside
one `--tune` breaks under `Start-Process`; Tuning now logs an error for it).
Both smoke scripts take `-Port N` (default 24599) so parallel runs (e.g. two worktrees)
don't collide. Within one checkout, run them one after the other: they share the
`build\smoke` log folder.

Game flags (after `--`): `--server`, `--port=N`, `--connect`, `--address=host[:port]`,
`--class=ID` (client: character class, default `fighter`; unknown = default),
`--bot` (auto-connect; repeats every 8 s: take turns attacking and blocking (the nearest
Husk within 15 m, else the nearest player), then both use abilities (guard up between; a
knockback ability first), then circle with weapon swap/jump/air dodge/ground dodge, a free
respec (odd cycles also learn new abilities like Rising Cut, or the capstones when there's
nothing new, as for the War Hammer; even cycles learn the built
capstones that fit, i.e. the Spear's Hold the Line and Finishing Thrust,
`BuildService._bot_learn_capstones`) and the next cycle's weapons
(the default loadout in the first cycle; then a different focus weapon each cycle:
Spear, Dual Axes, Broadsword; `BuildService.bot_weapons_for_cycle`); see
`World._bot_input`. On joining it slots its status abilities first, self-buffs before
`applies_status` ones, keeping one slot for a projectile ability
(`BuildService.bot_slot_status_abilities`: Broadsword Shield Wall + Opening Strike, Dual
Axes Bloodlust + Rampage, Spear Skewer + Perforate); it uses a self-buff (the first
ready one) as soon as its target is
within 2 m on its own turn or in the ability phase, then a hitting ability; the ability
phase's first press prefers a knockback ability, then a self-buff, then a status ability.
Wings (`World._bot_wing_input`, by role, `_bot_wing_role`, so any class works): a damage
buff (Wingbeat Surge) as its attack turn starts, a burst around it (Gale Burst,
Challenger's Roar) 1–2 s into that turn (after its heavy), a guard (Ember Mantle, Unbowed;
or a heal, Pyre Heart, when below 80% health) as its block turn starts, a dive (Diving
Strike, Meteor Drop) when the target is 3–7 m away; while a Rebirth is ready it only
spends Ember above the 50 threshold. At 7.6 s it also respecs its Wing tree: default
slots on even cycles, the other actives in Z on odd ones, plus the built Wing capstones
that fit (first in file order on even cycles, last on odd: Tempest Wings / Anchor,
Mantle of Renewal / Crushing Wingbeat), `BuildService.bot_respec_wings`.
Projectiles: it slots projectile abilities right after status ones (every class weapon)
and throws a ready one whenever its target is 3 m to 75% of the projectile's reach away
before the circling phase; see `World._bot_projectile_button`),
`--bot-party` (with `--bot`: the lower peer id invites the nearest player, and the bot
accepts any invite; it doesn't attack or use abilities (Wings included) until it's in a party, then
still swings at its ally when no Husk is near, which the server ignores; see
`PartySystem._bot_step`), `--verbose` (log positions every 2 s, server logs hits and
refused build changes), `--hitboxes` (start with hitboxes shown; F3 toggles),
`--mastery-panel` (open the K panel at start, for screenshot checks; `--mastery-panel=wings`
opens it on the Wings tab), `--inventory-panel` (open the I panel at start, same use),
`--perf-log` (print every frame slower than 50 ms with the time since launch, plus a
`SUMMARY perf` line with the worst frame and worst physics step; for chasing lag),
`--screenshot-dir=PATH` (save the game window every 0.25 s as `frame_<N>.png`, for
checking visuals; a relative path avoids trouble with the space in the project path; a
bot's camera then turns to where it aims, and with `--verbose` it prints
`[client] throws <kind> (frame N)` to find its throws),
`--quit-after=SECONDS` (prints `SUMMARY` lines, used by the smoke test),
`--tune=file/section/key=value` (repeatable; overrides a `data/` value for that run;
give the server and every client the same overrides; only keys that exist in the file
can be overridden, strings need no quotes). The smoke test uses `--tune` for low health
and a fast respawn so deaths happen within the run, and to switch on effects that are off
in the real data (Husk swings bleed, Broadsword and War Hammer heavies push) so its
status and force checks don't depend on bot luck, a 1 s Rebirth (`ember/rebirth/duration`)
so a reborn bot is back in the fight quickly, 2 s Javelin Cast / Boomerang Axe /
Shockwave cooldowns for more throws, Earthshaker on every heavy (`aftershocks=` on the
`SUMMARY juggernaut` line, no check), Skewer applying Taunted instead of Root so Husks get taunted
(counted, not checked), and a 6 m Hold the Line reach so pokes (`line_pokes=` on the
`SUMMARY abilities` line, no check) happen in most runs.

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

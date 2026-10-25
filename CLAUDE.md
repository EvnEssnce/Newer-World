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
- **Persistence goes through one module** (`game/persistence/persistence.gd`). SQLite in
  dev (the godot-sqlite GDExtension in `addons/`), Postgres later. Nothing else touches the
  database or writes SQL. Schema changes are new entries appended to
  `Persistence.MIGRATIONS`, never edits to shipped ones.
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
  tuning.gd          Autoload. Loads every res://data/*.cfg; the server sends its values to clients.
  net.gd             Autoload. ENet server/client setup, connection signals, ping.
  launch_args.gd     Command-line flags (after "--").
  code_version.gd    CodeVersion: a hash of the code files (not data/), or the one an export
                     packed in (code_version.txt). Unit tested. version_check.gd: VersionCheck
                     (/root/Main/VersionCheck), refuses a client on other code; see "Networking model".
  net_codec.gd       NetCodec: compact, lossless binary encoding for snapshots. Unit tested.
  position_history.gd  PositionHistory: a body's recent positions per tick (lag compensation). Pure.
  correction_smoothing.gd  CorrectionSmoothing: the local player's drawn offset after a correction. Pure.
  input_actions.gd   Key bindings, registered in code.
  aim_hold.gd        AimHold: aimed-zone abilities cast on key release (hold = marker). Pure.
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
  combat/aim_ray.gd          AimRay: the crosshair's line from position, aim yaw/pitch and
                             camera.cfg (shoulder offset); `cast` finds the aim point. Pure math,
                             unit tested. `World.aim_point(player)` (server, during the physics step).
  combat/beam_visual.gd      Client look of a beam attack (`beam_color`), drawn along the aim line: core, sheath, orb,
                             tip glow; from the predicted/interpolated PlayerState (`Player._show`).
  combat/shock_ring.gd       ShockRing: an expanding ground ring (Earthshaker): growth, swept band,
                             hit once. Pure logic, unit tested. shock_ring_visual.gd: its look
                             (band + ridge; also Upheaval's dust puff).
  combat/embedded_knives.gd  Knives embedded in targets (per-thrower cap, expiry, Recall).
                             Pure logic, unit tested.
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
  enemy/enemy_look.gd        EnemyLook: a kind's placeholder model built in code and its swing pose
                             (client); one per kind in enemy/looks/<kind>_look.gd (husk, dummy,
                             thorn, seer, crag), Husk's if missing.
  enemy/enemy_brain.gd       Enemy AI state machine (camp alerts, keep distance). Pure logic, unit tested.
  enemy/threat_table.gd      Threat per player, target choice, taunts. Pure logic, unit tested.
  enemy/enemy_params.gd      Enemy tuning from data/enemy_<kind>.cfg; validate() (a test runs it on
                             every kind).
  enemy/damage_meter.gd      Damage/DPS of one fight (the training dummy's readout). Unit tested.
  enemy/enemy_path.gd        EnemyPath: following a nav path, re-path rules. Pure, unit tested.
  enemy/enemy_navigation.gd  World/EnemyNav (server): navmesh baked at startup from layer 1,
                             re-baked in the background when an enemy-blocking wall goes up/down.
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
  gathering/gather_node_params.gd  One node kind (data/gathering.cfg). gather_node.gd: one node's
                             charges/respawn, reach, the F choice and crosshair pick (pure, unit tested).
  gathering/gathering_system.gd  World/Gathering: node state, gather requests, the busy lock,
                             yields into the bag; client node looks (gather_node_visual.gd), prompt.
  tradeskills/tradeskill_defs.gd, tradeskills.gd  Skill defs (data/tradeskills.cfg) and one
                             player's levels/XP, gather speed and bonus yield. Pure, unit tested.
  tradeskills/tradeskill_system.gd  World/Tradeskills: XP from gathers (and crafting later),
                             owner updates, level-up feed lines.
  progression/progression_defs.gd, progression.gd  Character level and per-weapon mastery
                             level (data/progression.cfg: caps, XP curves, tree points per
                             level) and one character's levels/XP. Pure, unit tested.
                             progression_system.gd: World/Progression (XP from kills and
                             gathers, owner updates and feed lines; see "Progression").
  crafting/craft_progress.gd The Forge panel's progress maths, cancel rules, XP line text. Pure.
  crafting/recipe_defs.gd    Recipes (data/recipes.cfg) and station kinds (data/stations.cfg);
                             crafting_rules.gd: can-craft checks and an atomic apply (a bag copy
                             first: a failed craft loses nothing); crafting_station.gd: reach, pick.
                             Pure, unit tested. crafting_system.gd: World/Crafting (server checks,
                             the busy lock, panel, prompt, bot); station_visual.gd: the Forge.
  persistence/persistence.gd The one database module (server): SQLite via godot-sqlite (made through
                             ClassDB, so it parses where the extension is missing), migrations in
                             `PRAGMA user_version`, accounts, characters (save parts as JSON text
                             columns; `encode`/`decode` keep ints and full-precision floats). Unit
                             tested on temporary databases (user://test_persistence/). Opened at
                             server start by AccountService (`--db=`).
  persistence/save_schedule.gd  SaveSchedule: when to save (a change saved `after_change` s
                             after the first unsaved one; everyone every `interval` s). Pure,
                             unit tested. save_service.gd: World/Saves (server), see "Saving".
  persistence/character_save.gd  CharacterSave: a character's name, class and the to_dict() of its
                             build, inventory, equipment and tradeskills; capture from live
                             objects, rebuild through the normal rules (`CharacterBuild.apply_saved`,
                             `Inventory.from_dict`), `drop_unknown_items`. Pure, unit tested.
  accounts/password_hash.gd  PasswordHash: PBKDF2-HMAC-SHA256, stored as one string
                             `pbkdf2_sha256$iterations$salt$key`. account_rules.gd: AccountRules,
                             name/password rules (data/accounts.cfg). Pure, unit tested.
  accounts/account_service.gd  /root/Main/Accounts (both sides): login, character list/create/
                             choose RPCs, sessions per peer, hashes on worker threads; bot login;
                             player names for every machine (player_names.gd: PlayerNames, the
                             peer → name table and "Player N" fallback; pure, unit tested).
  party/party_rules.gd       Parties, invites, ally rule. Pure logic, unit tested.
  party/party_system.gd      World/Party: party RPCs, server validation, client keys/HUD/bot.
  zones/zone_params.gd       One zone/summon kind (data/zones.cfg [zone_<id>]).
  zones/zone.gd              One placed zone: pulses, traps and re-arming, area test, wall
                             box vs segment. Pure logic, unit tested.
  zones/zone_system.gd       World/Zones: server placement, effects, decoys, wall bodies;
                             spawn/move/trigger/end events; client copies.
  zones/zone_visual.gd       Client look: disc, cloud, rain, trap, decoy, wall.
  status/status_def.gd       One status effect's tuning (data/status_effects.cfg).
  status/status_defs.gd      Every status, by index (what the network sends); validate().
  status/status_effects.gd   One owner's statuses: apply/stack/refresh, tick, queries,
                             cleanse, on-hit (Bloodlust), immunities, taunt source.
                             Pure logic, unit tested.
ui/                  connect_menu (client start screens: address, login/create account,
                     character list, create character with a class picker; pages built
                     in code), crosshair (screen-centre ticks + dot,
                     hidden under modal panels), hud (health/stamina/Ember bars with a
                     current/max health number, ability bar, Wing slots, weapon line, status
                     row, Rebirth banner, debug info, the XP bar along the bottom edge),
                     keybinds_panel (F1: the key list, bottom left, from InputActions),
                     equipment_summary (top-right gear box: average gear score, a drawn symbol
                     per equip slot tinted by rarity, gear stat totals from
                     `Equipment.Stats.summary_lines`; added by `Hud.setup_equipment(loot)`,
                     reads `LootSystem.equipment`),
                     mastery_panel (K: Class picker (test tool), equipped weapons, weapon trees
                     and a Wings tab, respec, slots; sized to the viewport, max 1440x840),
                     party_hud (party frames, invite prompt, party notices; built in code),
                     loot_hud (pickup prompt, loot feed, equip bar) and inventory_panel (I:
                     equipped cards + a bag grid sized to the viewport (max 1560x840; 40 slots
                     fit at 1080p), type/class filters and sort (client view only,
                     `InventoryPanel.bag_view`), comparisons with affixes
                     (`Item.stat_changes`), hover tooltips).
data/                Tuning files: network, movement, combat, camera, enemy_husk, enemy_dummy,
                     enemy_thorn, enemy_seer, enemy_crag (the camp kinds, design/enemies.md),
                     weapon_<id> (broadsword, spear, dual_axes; Juggernaut: halberd,
                     greataxe, war_hammer; Assassin: dual_talons, throwing_knives;
                     Ranger: longbow, crossbow, firebolts; Mage: great_staff, gauntlet;
                     Paladin: dual_shortstaffs, longstaff),
                     class_<id> (fighter, juggernaut, assassin, ranger, mage, paladin),
                     mastery (shared tree rules), mastery_<weapon>, wings_<class> (Wing
                     abilities), mastery_wings_<class> (Wing tree), ember (Ember + Rebirth),
                     loot (rarities + loot tables), items, affixes, gear (gear score curve,
                     armor, equip time), party, status_effects, projectiles, zones, navigation, gathering
                     (node kinds), tradeskills (skills, XP curve, gathering effects),
                     recipes (refining/crafting recipes), stations (station kinds),
                     testing (test-only switches: the in-game class change, tradeskill join_xp,
                     full tree points),
                     accounts (name/password rules, max characters, hash iterations),
                     name_filter (words names can't contain),
                     saving (periodic and after-change save delays), progression
                     (character/mastery level caps and XP curves, tree points per level) (.cfg).
design/              classes.md: class/weapon/ability design, then per-class implementation notes.
                     enemies.md: the enemy kinds and camps (build order 5.1).
assets/              CC0 art packs go here (Kenney, Quaternius, Mixamo).
addons/godot-sqlite/ godot-sqlite v4.9 (MIT, built for Godot 4.7.1): Windows and Linux x86_64
                     binaries only (`gdsqlite.gdextension` lists them). Other platforms: copy
                     their binaries from the release's addons.zip.
tests/               test_*.gd unit tests; framework/ holds the runner and TestCase.
tools/               PowerShell run scripts, unit test runner, smoke test.
```

## Networking model

- The server is peer 1. `World` exists at `/root/Main/World` on every machine, because
  RPCs are matched by node path. Player nodes are named by peer id under `World/Players`.
- `server_relay` is off: clients never hear from each other directly, only via snapshots.
- **Client → server**, every physics tick, `World._submit_inputs` (unreliable ordered,
  channel 1): the last `input_redundancy` inputs, each
  `[seq, move: Vector2, buttons: int, aim_yaw: float, aim_pitch: float, view_tick: int]`
  (`view_tick`: the server tick the client was drawing others at, `World.render_tick()`
  rounded; lag compensation only, not sim state). `move` is a world-space XZ
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
  (unreliable ordered, channel 2): `tick` and `NetCodec` bytes of `[players, enemies]`,
  built per recipient (`World._broadcast_snapshot`). The recipient's own entry is
  `Player.get_snapshot()`: `[peer_id, position, velocity, last_processed_seq,
  PlayerState.to_array(), Vector2(health, max_health)]` (max health includes gear; one
  Vector2 is the size of a float health alone); every other player's is
  `get_view_snapshot()`: `[peer_id, position, PlayerState.view_array(),
  Vector2(health, max_health)]` (same layout as `to_array()`, with what only the owner
  needs, such as stamina, cooldowns, Ember, buffers, held presses, equip time and
  charges, left at defaults: smaller, and private). Each entry is encoded once and
  reused for every recipient. `NetCodec` is lossless (same values and types back, so
  reconciliation compares exactly what the server had): a 1-byte tag per value, small
  ints in the tag, varints, whole floats as ints, 32-bit floats when exact, 1-byte zero
  vectors and same-value int arrays. A field that only drawing needs stays in
  `view_array()`; one only the owner needs is reset there.
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
  each unexpected one, and server-side input drops. After any correction the model
  and camera glide from where they were drawn (`CorrectionSmoothing`,
  `Player._draw_offset`; `[client] correction_smoothing` s, jumps over
  `correction_snap_distance` snap): drawing only, the body moves at once.
- **Code version check** (`/root/Main/VersionCheck`, `VersionCheck`, made by `Main` on
  both sides): a client sends `_hello(CodeVersion.current())` as it connects; a match
  emits `peer_verified` (the server then sends the tuning, and only a verified peer may
  log in: `AccountService._request_login`); a mismatch gets `_refused(server_version)`
  and a disconnect after it, and the address screen says "This game (version X) doesn't
  match the server's (version Y). Get the latest NewerWorld.zip from the host." (the
  connect page also shows "Game version X"). A peer that says nothing for `[server]
  version_timeout` s (network.cfg; a build from before the check) is disconnected.
  `CodeVersion` = 12 hex of SHA-256 over every `.gd`/`.tscn`/`.tres`/`.gdshader` file
  and `project.godot` outside data/, tests/, tools/, design/, assets/, addons/ and
  build/, with `\r` removed (~10 ms); an exported game reads `res://code_version.txt`
  instead, written by `tools/write_code_version.gd` in `export_client.ps1` just before
  exporting (gitignored, deleted after). **Never change VersionCheck's path, RPCs or
  their arguments**: old builds must still reach them. `SUMMARY version code=
  accepted= refused= timed_out=` (server; the smoke test checks both bots accepted and,
  in its restart phase, a `--fake-version` client refused with the message).
- **The server's tuning wins** (`Tuning.send_to_peer` on `VersionCheck.peer_verified`): every
  `data/*.cfg` value (with the server's `--tune` overrides) goes to a client as it
  connects (`var_to_bytes` + zstd, ~35 KB, reliable RPC on `/root/Tuning`); the client
  replaces its own (`Tuning.apply_packed`, its `--tune` ignored) and `Main` only makes
  the World after both the connection and the tuning (`_enter_world`). `Tuning.version`
  moves on every load; every class that caches tuning (`PlayerParams.current()`,
  `ItemDatabase`, `StatusDefs`, `GearScore`, `ClassDef`, `MasteryTree`, `EnemyParams`,
  `ProjectileParams`/`ProjectileVisual`, `ZoneParams`, `AimRay.tuned()`, `GatherNodeParams`, `TradeskillDefs`, `RecipeDefs`) rebuilds when it
  does: **a new cache must do the same**. Friends' builds only need the same code
  (the version check above enforces it).
- **Lag compensation** (`[lag_compensation]` in network.cfg): the server records every
  player's and enemy's position each tick (`PositionHistory`, `World._record_positions`,
  after the sim, before the snapshot) and tests a player's melee/beam/ally-support
  hitbox against where targets stood on that input's `view_tick`
  (`World._lag_position`, clamped to `max_rewind`; never back past a one-tick jump over
  `teleport_distance`: respawn, Blink). Only the touch test is rewound: blocks,
  parries, facing, i-frames, backstab arcs, knockback and the aim raycast use current
  state. Projectiles, zones, shock rings and enemy swings aren't rewound.
  `SUMMARY lag_comp rewound_tests= rewind_ticks_avg= saved_hits=` (~8 ticks on
  localhost: 0.1 s delay + snapshot spacing).
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
- **Gathering** (`World/Gathering`, `GatheringSystem`; nodes are `Marker3D`s under
  `World/GatherNodes` with `metadata/kind`, id = marker index on both sides; never in
  snapshots): client → server `_request_gather(node_id)`; server → all
  `_receive_all_nodes(bytes)` on join and `_receive_node_state(id, available)` on change.
  The server checks alive, range + `[gather] range_tolerance`, node available, bag room,
  then `PlayerState.start_gather(ticks)`: the **equip lock** (`equip_left`, walk-only, a
  server event; no new synced field). Leaving range, losing health, stagger/stun/force,
  death or the node running out cancels it (`cancel_equip`); the node keeps its charge.
  On finish: yield (+ `yield_bonus_hook`) into the bag as stacks (`LootSystem.give_resources`)
  and `gathered(peer, skill, kind, amount)`. **Tradeskills** (`World/Tradeskills`): wired in
  `World._ready`: `gathered` → `on_gathered` (XP), `time_multiplier_hook` /
  `yield_bonus_hook` → `gather_time_multiplier` / `bonus_yield`; server → owner
  `_receive_skills(dict)` and `_receive_level_up(skill, from, to)`; no client requests;
  `add_xp(peer, skill, xp)` for crafting; every gain also sends the owner
  `_receive_xp(skill, xp)`, a "+25 Mining XP" feed line. Saved with the character (`join_xp` only for a
  character with no saved tradeskills).
  **Crafting** (`World/Crafting`, `CraftingSystem`; stations are `Marker3D`s under
  `World/Stations`: one Forge at (-7, 0, 17), ~31 m from the Husk homes, out of their
  leash + reach; stateless): client →
  server `_request_craft(station_id, recipe_id, quantity)`; the server checks range +
  `[crafting] range_tolerance`, level, materials and bag room after the inputs go
  (`CraftingRules.check`), runs one busy lock of craft time × quantity (`start_gather`,
  same cancels as gathering), and on finish applies it atomically (inputs taken then,
  rechecked), grants XP (`TradeskillSystem.on_crafted`) and sends the bag + feed line.
  **The station panel must stay open:** closing it (Esc, F, its X, range, another panel,
  death) sends `_request_cancel_craft()`, and any move/jump/dodge input at the station
  cancels on the server (`Player.last_move`/`last_buttons`), and on the client any such
  input closes the panel once you've stood still with it open (`CraftProgress.move_closes`).
  A cancelled batch still makes its whole finished pieces (`CraftProgress.pieces_done`,
  "(2 of 5 made)"); inputs are only taken for what's made, at the
  end. Server → owner `_receive_craft_started(recipe, qty, ticks)` / `_receive_craft_ended`
  drive the panel's progress bar (then the predicted `equip_left`). The bot walks to the
  Forge on purpose once it has materials (`CraftingSystem.bot_trip`).
  Recipes have `output_kind` "item" (refining) or "gear": each piece is its own
  `CraftingRules.roll_gear` → `LootRoller.roll_item` (server RNG) at a gear score range and
  rarity weights from the crafter's level (`TradeskillDefs.gear_score_range` /
  `gear_rarity_weights`, `tradeskills.cfg [crafting]`: GS 100–110 at level 1 to 130–140 at
  100; Common 85% → 30%; never Legendary) and needs its own free bag slot. Recipe tiers
  1/4/8 (weapons) and 1/3/6 (Padded armor) add variety, not gear score. `SUMMARY crafting
  ... gear_made=`.
- **Accounts** (`/root/Main/Accounts`, `AccountService`, made by `Main` on both sides
  before any World; build order 3.2): the server opens the database at start (`--db=`,
  default `user://newer_world.db`; `:memory:` for the screenshot script, a fresh
  `build/smoke/restart.db` for the smoke test;
  quits if it can't). A client, once connected and holding the server's tuning, logs
  in, and only makes its World after choosing a character. Reliable RPCs: client →
  server `_request_login(account, password, create)`, `_request_create_character(name,
  class_id)`, `_request_play(character_id)`, `_request_delete_character(character_id)` (one
  of the account's, not while playing; answered with `_receive_characters`); server → that client `_receive_login(error,
  account, characters)`, `_receive_characters(error, characters)` (entries `{id, name,
  class_id}`), `_receive_play(error)`. **Names** (`AccountService.names`, a
  `PlayerNames`, peer id → character name, both sides; never in snapshots, so it
  doesn't depend on who is in view): when a peer chooses a character (just before its
  `_receive_play`) the server sends it `_receive_names({peer: name})` for everyone
  playing, itself included, and every other playing peer `_receive_name(peer, name)`;
  a playing peer leaving sends the rest `_receive_name_removed(peer)` (only to
  connected peers: `Net.is_peer_connected`). Clients emit `name_changed(peer)`.
  Nameplates, party frames and party notices draw `AccountService.player_name(node,
  peer)`: the name, or "Player N" until it arrives. The server checks `AccountRules`
  (data/accounts.cfg; names unique ignoring case in the schema), one login per account,
  that the character is the account's, and hashes with `PasswordHash` (PBKDF2,
  `[password] iterations`, ~0.3 s) on a `WorkerThreadPool` task polled in `_process`
  (the database stays on the main thread). Login failures say only "Wrong account name
  or password." `World._client_ready()` (no arguments) spawns
  `AccountService.character_of(peer)`'s class; a peer that hasn't chosen one is
  ignored. Logging out = disconnecting (the session dies with the peer). A new
  character is stored with its class's default build (then see "Saving"); an in-game
  class change doesn't touch the stored class, so the other class's saved build is
  refused on the next join (logged) and its gear goes back to the bag. `--bot`
  logs in alone (`start_bot`): account `--account=` (default `bot_<peer id>`, made if
  missing), character `--character=` (default "Bot" + the peer id as letters), made
  with `--class=`. `SUMMARY accounts logins= accounts_created= characters_created=
  plays= refused= characters_deleted=` (the smoke test checks every bot made both and played).
  **Name filter** (`data/name_filter.cfg`, `AccountRules.blocked_name`, account and character
  names): lower-cased, look-alike digits/symbols as letters, non-letters dropped, `allowed`
  words cut out; refused if it contains a `contains` word (also with repeats squeezed, for
  words of 4+ letters once squeezed) or is exactly a `whole` word: "That name isn't allowed."
- **Progression** (`World/Progression`, `ProgressionSystem`, both sides; build order 4):
  server only grants XP. A kill (`World._damage_enemy` → `on_enemy_killed`) gives every
  player in `Enemy.damaged_by` the enemy file's `[progression] kill_xp`, and its
  `mastery_xp` split by damage per weapon (`damaged_by[peer]` = weapon id → damage;
  `World._credited_weapon`: the weapon out when it landed, "" during a Wing ability;
  `Progression.mastery_split`); a gather (`gathered`) gives `[sources] gather_xp`.
  `grant` → server → owner `_receive_progress(dict)`, `_receive_xp(xp, mastery)` ("+50 XP
  +40 Spear" feed line), `_receive_level_up(weapon_id, from, to)` ("" = character);
  `save_changed`; `points_changed` → `BuildService.on_points_changed`. Clients: `local`,
  the HUD's XP bar (`Hud.setup_progression`). **Tree points from levels:**
  `BuildService.set_points` (join, after restoring the save; class change; level-up)
  puts `Progression.weapon_points`/`wing_points` into `CharacterBuild.set_point_limits`,
  which cuts trees over them (`MasteryTree.fit`, logged); `validate`/`can_add`/`prune`
  take the limit; the limits reach the owner in `_receive_build` (`to_dict(true)`), not
  saves. `data/testing.cfg [progression] full_points` = no limits (the smoke test).
  **Level bonus** (levels 21-30): Wing points past the Wing tree's budget (22, full at
  level 20) are class bonus points (`set_points` → `CharacterBuild.level_bonus_points`,
  sent to the owner; `Player.set_level_bonus`), each worth the class file's
  `[level_bonus] stat`/`per_point` (`ClassDef.level_bonus`, `level_bonus_text`):
  server-only `max_health` (Juggernaut, `Player.max_health`), `damage` (Fighter,
  `damage_multiplier`), `healing` (Paladin, `_heal_player`); sim (synced owner-only ints
  in thousandths, `PlayerState.set_level_bonus`, a server event) `move_speed` (Assassin,
  `bonus_move_multiplier` in `PlayerMovement`), `dodge_cost` (Ranger, `dodge_cost`),
  `ember_cost` (Mage, `ember_cost_of`: every Ember cost check and spend goes through it).
  K's Wings tab and the level-up line show it.
  `SUMMARY progression ... kills_credited= gathers= xp_granted= mastery_xp_granted=
  level_ups= mastery_level_ups= xp_lines=`.
- **Saving** (`World/Saves`, `SaveService`, server only, no RPCs; build order 3.3):
  `World._client_ready` loads the chosen character (`load_character`: Persistence +
  `drop_unknown_items`, logged) and rebuilds it through the normal paths:
  `ProgressionSystem.add_player(peer, save)` first (`CharacterSave.progression`, schema
  2's `progression` column; levels clamped to the current caps; its levels give the
  tree points), `BuildService.setup_player(player, class, save)` (class default +
  `restore_build`, then `set_points`; refused parts logged, `SUMMARY saves
  refused_parts=`), `LootSystem.add_player(peer, save)` (bag capacity from data/; saved
  gear the class can't wear or weapon items off the loadout go back to the bag, past
  capacity if need be), full health with the gear, `TradeskillSystem.add_player(peer,
  save)`; then `track`. Writes go through
  `Persistence.save_characters` (one transaction) on the main thread, from
  `CharacterSave.capture` of the live objects: everyone every `[save] interval` s
  (data/saving.cfg), a character `after_change` s after its first unsaved change (the
  `save_changed(peer)` signals: `BuildService.send_build` without an error, every
  `LootSystem._send_inventory`, every tradeskill or progression XP gain; `SaveSchedule` holds the
  rules), on disconnect (`Net.peer_leaving`, emitted just before `peer_left` so every
  system still has the peer's data) and at shutdown (`Main._save_before_quitting`:
  `--quit-after` or closing the window; a killed process loses at most `interval`).
  **An action under way isn't saved:** a save is the state before it (an equip still
  has the item in the bag, a gather has yielded nothing, a craft's inputs are taken at
  the end); leaving mid-craft keeps the inputs and loses the batch, finished pieces
  included. Not saved: health, Ember, cooldowns, statuses, position, party, ground
  drops. Logs `[server] loaded/saved <name> (<reason>): bag= equipped= skill_levels=
  skill_xp= fp=<CharacterSave.fingerprint>` (saves only on leave/shutdown unless
  `--verbose`); `SUMMARY saves loads= writes= periodic= change= leave= shutdown=
  failed= dropped_items= refused_parts=` (characters per reason).
- **Builds** (`World/Builds`, `BuildService`): `World._client_ready()` spawns the
  character chosen at login with its saved `CharacterBuild` (see "Accounts", "Saving"). Reliable RPCs: client → server `_request_mastery(weapon_id, nodes,
  slots)` (a whole tree allocation + Q/E/R ability ids: a free respec),
  `_request_wings(nodes, slots)` (the Wing tree allocation + Z/C ability ids) and
  `_request_weapons(weapons)`; server → client `_receive_build(build_dict, error)` after
  every request and on join. The server validates (class weapon list, mastery rules, not
  mid-attack/ability/swap) and puts what affects the sim (equipped weapon ids, slotted
  ability indices, Wing set and slots) into `PlayerState.set_loadout` / `set_wings`,
  server events, so it reaches the client through snapshots. Passive/upgrade nodes are
  server-only damage/stamina/damage-taken modifiers, never sim state.
- **Changing class in-game** (a test tool, `data/testing.cfg [class_change] enabled`;
  turn it off before playtests with other people): the K panel's Class picker sends
  `_request_class(class_id)`. The server refuses it unless enabled, a real other class,
  and `PlayerState.class_change_error()` is "" (alive, out of combat: `combat_ticks` 0,
  not mid-attack/ability/swap/gear change, roll, stagger or forced move), and
  `LootSystem.check_class_change` (bag room for the gear that must come off). Then a
  clean start: `PlayerState.reset_for_class_change` (full stamina, no statuses, Ember at
  resting, every cooldown and spare charge cleared, first weapon out; a server event),
  `Player.reset_class_state` (server-only counters, Ward, Phoenix Blessing), the new
  class's default `CharacterBuild` + `apply_to_state`, `LootSystem.class_changed`
  (`Equipment.slots_off_for_class`: other classes' weapons and Wing Enhancement back to
  the bag), full health, `_receive_build`. Zones and projectiles already out stay until
  they end. Counted in `BuildService.class_changes`.
- **On-floor is synced state**: `PlayerMovement` reads `PlayerState.on_floor` (set after
  each `move_and_slide`), never `body.is_on_floor()` directly, so a restored state
  carries it. Server-side teleports (respawn) should still land exactly on the ground.
- **Remote players**: drawn `interpolation_delay` seconds in the past, interpolated
  between snapshots on a render clock synced to server ticks. Roll and i-frame visuals
  come from the interpolated `PlayerState`. A teleport between two snapshots snaps
  instead of gliding (`PlayerState.ticks_since_teleport`).
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
  rebirth_cooldown, rebirth_charges, Z slot, C slot, equip_left, free_move_mask,
  charge_mask, spare_charges, decoy_active, beam_pitch, bonus_move_pm, bonus_dodge_cut_pm,
  bonus_ember_cut_pm (the level bonus, owner-only), Wing cooldowns by pool index without
  trailing zeros]`
  (`PACKED_WING_HEADER` = 15; new small ints can go in that header too; `beam_pitch` = the aim pitch in whole degrees while a beam runs, drawing-only: kept in `view_array()`, not compared in `matches()`); 35 =
  `attack_speed_carry` (float, Rampage: see "Attack speed" under Status effects); 36 =
  ammo, a `PackedInt32Array` `[spent slot0, spent slot1, timer slot0, timer slot1,
  attack_ammo]` (Throwing Knives magazine; `attack_ammo` = knives a partial heavy took;
  zeros in `view_array()`). `decoy_active` (owner-only) is set by the server while the
  player's decoy is out (`World.sync_decoy_flag`, a server event): Shadow Swap's
  `needs_decoy`.
  Append new fields at the end. **Snapshot size** (`SUMMARY net` on the server; the
  smoke test fails a snapshot over 1360 bytes, ENet's 1392-byte MTU less the RPC
  header): own entry ~200–240 bytes, each other player ~145–175, each Husk ~50–60;
  2 players + 2 Husks ~440–530 bytes, 4 players ~810, 6 players ~1,130 (Godot's Variant
  encoding was ~1.4 KB for 2 players). About 7 players in view fit one packet;
  interest management (only nearby players/enemies) is next for more.
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
  cause no corrections. **Server-steered** kinds (`bounces`: Ricochet, `homing_turn`:
  Seeker Spark) send `_receive_redirect(id, age, position, velocity)` (event type
  `EVENT_REDIRECT` 5) when the server changes their course (each bounce; homing every
  `HOMING_SYNC_ANGLE` of turn); clients rewind their copy to it like a TURN.
  **Embedded knives** (session 41): light/heavy knives (`embeds="embedded_knife"`) that
  damage a target stay in it (`EmbeddedKnives`, server; the `embedded_knife` status shows
  the count; at most 8 per thrower, 10 s; missed knives just drop). Recall
  (`recalls="embedded_knife"`) strikes each target once for its damage × that target's
  knives, then cosmetic `knife_recall` projectiles (`hits=false`) fly back.

## Zones and summons (AREA, SUMMON)

- Clients prewarm every zone look's materials once a camera exists
  (`ZoneSystem._prewarm_step`: one alpha-0 copy per visual type for 3 frames), so a first
  cast doesn't compile shaders mid-fight (Shield Wall froze on first use). Godot caches
  compiled shaders in `user://shader_cache`, which hides first-use hitches: to test one,
  use an empty user dir (an `override.cfg` with `application/config/use_custom_user_dir`).

- `data/zones.cfg` `[zone_<id>]` (every key explained there): radius/height, duration,
  `trigger` "pulse" (every `interval`, first after `first_pulse`), "trap" (armed after
  `arm_time`, the first hostile inside sets it off, then `rearms` or ends) or "none";
  `affects` "hostile"/"ally"; per pulse `damage` (like damage over time: no block,
  crit or armor), `heal`, a status; `decoy`; `wall` with width/depth; `visual`, color.
- **Server state only**, never in snapshots or the predicted sim. `World/Zones`
  (`ZoneSystem`, both sides) sends reliable `_receive_zone(id, kind, position, yaw,
  ticks_left)`, `_receive_zone_moved`, `_receive_zone_triggered`, `_receive_zone_end`
  to every connected player; clients draw a `ZoneVisual` and count down their own
  copy. Late joiners don't see zones placed before they joined (all last ≤ 30 s).
- **Placing**: an attack/ability's `zone` (kind), `zone_time` (s from its start),
  `zone_distance` (the max range, m, horizontal) → `Player.zone_placed` (server) →
  `ZoneSystem.server_place_for_attack`: it lands at `World.aim_point` (the crosshair)
  clamped to that range (sky or farther = max range along the crosshair's line), unless
  `zone_aimed=false` (Shield Wall, Sheltering Wings, Tripwire: straight ahead); the
  local player sees a marker during the windup (`ZoneSystem._update_marker`);
  a projectile's `zone_on_impact` where it stops
  (hit, wall or expiry; `ProjectileSystem.server_step`); a roll while a status has
  `roll_zone` (`World._roll_zone`, uses a stack; a `strip` kind (Fire Trail) is laid
  from the roll's start to its end when it ends: `Player.roll_ended`/`roll_start`,
  per-placement `Zone.width`/`depth`, sent as `_receive_zone`'s last arg `size`).
  Always snapped to the ground below.
- **Effects**: `ZoneSystem.server_step` (each tick after projectiles) →
  `World.zone_effect(zone, target)` for every target of the zone's side inside
  (`Zone.contains`: circle + height band, or the wall's box); traps hit the first
  hostile (enemies first). `World.trap_rearms`: the Trapper capstone (`trap_rearm`).
- **Decoys** (`decoy=true`): `World._enemy_targets()` hands enemies the decoy's
  position as its owner's while it lives, so Husks chase and swing at it (swings test
  real positions, so they hit nobody there). `World.on_decoy_ended`: Mirror Image
  (`decoy_burst`). **Stealth** is visual only: a `veils` status draws the owner faint
  (`Player.VEILED_ALPHA`) and hides its nameplate from others; its position is still
  in snapshots.
- **Walls** (`wall=true`): a server `StaticBody3D` on `ZoneSystem.WALL_LAYER` (16) and cut
  out of the enemies' navmesh while it stands (`EnemyNavigation.add_wall`/`remove_wall`),
  which enemies mask (`enemy.tscn` mask 17) and players don't; `ZoneSystem.wall_hit`
  stops projectiles not from the owner's side (`ProjectileSystem._collide`). Client
  projectile copies fly on until the server's end event.
- **Teleports** (Shadow Swap, `swap_places`): `World._shadow_swap` at ability start
  moves the player (and the swapped enemy/player) and calls `PlayerState.note_teleport()`
  (a server event, so prediction takes it without counting a correction).
- Kinds: Arrow Rain (Longbow), Smoke Bolt's `smoke` (Smoked: `blind` 0.7), Tripwire
  (trap: 30 damage + Root 2 s), Fire Trail (Burn), Ember Double (decoy), Shield Wall;
  Mage: Meteor Fall, Flame Wall (a box that isn't `solid`), Renewal Pulse (ally
  heal), Life Spore (an ally trap), Binding Embers.
- `wall=true` makes the area a box; only `solid=true` stops projectiles, and collides
  with enemies unless `blocks_enemies=false` (Sheltering Wings). `affects="both"`:
  allies get its heal, hostiles its damage and status (Sanctified Ground).
  A wall's area counts any body overlapping the box (`Zone.contains(point, body_radius)`,
  player/enemy `BODY_RADIUS`; a thin Flame Wall missed Husks standing in it); discs test
  the feet.
  Traps hit the first target of their `affects` side (allies for Life Spore).
- `SUMMARY zones spawned= pulses= affected= trap_triggers= decoys= walls=
  projectiles_stopped=` and `SUMMARY summons decoy_bursts= shadow_swaps=` (no checks;
  the bot slots zone abilities first, `BuildService.bot_slot_status_abilities`).

## Combat model

- Tap left click = light (fires on release), hold left click `heavy_hold_time` = heavy
  (fires while held). Hold right click = block. Attacks: windup → active (hitbox live)
  → recovery, all in ticks from the weapon file. A dodge or weapon/Wing ability press during a light/heavy windup **cancels** it (no damage, nothing released, knife ammo refunded); during its recovery it skips the rest; during the protected part (hit windows, projectile release, zone placement) it stays buffered (`PlayerState.attack_cancel_phase` is the one rule). Abilities can only be dodged in recovery (or during their windows with `channel_dodge`), and abilities never cancel abilities.
  Presses during an attack or roll are buffered. Facing starts at `aim_yaw` and tracks
  it at `turn_speed` (weapon file) for the whole attack; the facing aims at the
  crosshair's line at the attack's reach (`AimRay.attack_facing`, `AttackParams.aim_reach`,
  `camera.cfg [aim] melee_reach_fraction`/`melee_min_reach`; block still faces `aim_yaw`),
  so the hitbox sits under the crosshair. **Beams** (`aimed_beam`, default on for a box
  with `beam_color`) aim like projectiles: each live tick `World._beam_of` runs a capsule
  from `[beam] origin_height`/`origin_forward` (the projectile release point) toward
  `World.aim_point` (pitch included; `for_allies` lands on the ally under the crosshair
  for Mending Beam/Ward), `range` long, `width/2` thick (`MeleeHitbox.touches`); their
  facing heads for the crosshair line at the full range. Movement is slowed by
  `move_multiplier`.
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
  attack timeline (windup → hit windows → recovery; dodge cancels recovery, and the
  windows too for `channel_dodge` abilities (default on when `windows` > 1: Frenzy, Talon
  Spin, Vortex, Searing Ray...); a teleport or `needs_decoy` ability can't start while
  rooted / without a decoy (the press stays buffered, nothing spent); presses are
  buffered by `[abilities] buffer`). Cooldown starts with the ability and counts down
  for both weapons (`cooldowns`, per weapon slot × pool index). Variants:
  `windows`/`window_interval` (Frenzy: a target can be hit once per window),
  `shape="radial"` (Whirlwind Edge, Crashing Leap slam; with `arc` (degrees) a cone in
  front, `AttackParams.hitbox_arc`: Seismic Slam; the F3 debug draws the full circle), dash (`dash_distance`, moved in
  `PlayerMovement` like a dodge: Shield Charge, Crashing Leap, Lunge;
  `dash_direction="back"` dashes away from the facing, `"input"` the way the movement input
  points, backward with none: Vault; `"input_forward"` the same but forward with none;
  `teleport=true` moves the whole `dash_distance` at once on `dash_start`
  (`PlayerMovement.teleport`: `move_and_collide` on the world, climbs walkable slopes,
  stops at the first wall, settles onto the floor if it was on one; root blocks it; not a
  velocity burst): Blink, Ashstep; `dash_ease="in"` speeds up over the dash, same
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
- **Prerequisites** (session 41): a tree node may list `requires` (node ids, same or
  lower tier, any branch); learning needs them, unlearning cascades (`remove`/`prune`);
  `MasteryTree.check()` validates every tree at load and in a unit test (every upgrade or
  capstone aimed at one of its tree's abilities must require it); K shows "Requires X".
- **Mastery** (`data/mastery_<weapon>.cfg`, rules in `data/mastery.cfg`): two
  branches; a node of tier T needs `tier_requirements[T-1]` points in lower tiers of its
  branch; total ≤ `points` and the points the character's levels give (see
  "Progression"). Active nodes unlock abilities (a slot may only hold an
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
- **Shield Wall** (Broadsword Vanguard tier 2; redesigned in session 34): summons a
  wall of three tall shields 3 m ahead (`zone="shield_wall"`, see "Zones and summons"):
  4.5 × 0.5 × 2.5 m, 8 s, 18 s cooldown; enemies can't walk through, projectiles from
  outside the owner's party stop at it, the owner and party walk through. Not breakable
  yet. **Hostile players in PvP aren't blocked** (players' collision mask is shared).
  The old cover mechanic (`status_shield_wall`, `cover_depth`/`cover_width`,
  `World._shield_wall_holder` / `_covered_hit`, `shield_wall_covers=`) is still in the
  code but nothing applies that status any more.
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
  Every kind glows (a camera-facing halo and a short trail; optional `glow`, 0 = off;
  `ProjectileVisual.prewarm_looks` via `ProjectileSystem._prewarm_step`).
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
  **Aiming** (session 41): throws fly from the release point toward `World.aim_point`
  (the crosshair: `AimRay` from the last simulated input's `aim_yaw`/`aim_pitch`,
  `Player.last_aim_*`, rebuilt on the server, never sent by the client; it isn't sim
  state), pitch included (`ProjectileSystem.aimed_direction`, the same on the server and
  the local cosmetic copy). A kind's `pitch` is degrees above the aim line; spreads fan
  around the aim's heading; `aim_pitch=false` keeps a kind level (Shockwave); an aim point
  under `[aim] min_ahead` ahead goes along the ray. The camera is over the shoulder
  (`camera.cfg shoulder_offset`, read by the server too: restart both after editing).
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
- **Lag compensation** (see "Networking model"): a player's melee and beam hits test
  targets where its screen showed them; projectiles and enemy swings use current
  server positions.

## Classes

The Fighter's mechanics are in "Combat model" above. The other five classes'
implementation notes (Juggernaut: hyper armor, crits, Brace, Iron Hide, hooks;
Assassin: backstabs, Feint/Primed, Marked, knife magazine; Ranger: Running Shot,
charges, Loaded Chamber, Ignite; Mage: Ember-cost abilities, heals, Ward shields,
silence; Paladin: support keys, deflection, Guardian Link, Rebirth grants; plus each
class's Wings, `World` helper blocks, `SUMMARY` counters and models) are in
`design/classes.md` → "Implementation notes". **Read a class's section there before
changing its weapons, Wings or the shared rules it names** (crits, heals and shields,
charges are cross-class).

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
  `PlayerState.step`. Sim keys besides slow/root/stun/attack speed: hastes
  (`move_multiplier` > 1, times the strongest slow), `dodge_speed_multiplier`,
  `dodge_cost_multiplier`, `fall_gravity_multiplier`, `max_fall_speed` (a hover:
  Updraft) (Ranger Wings). `blind` (0..1) is
  a HUD haze for players and a per-swing miss chance for enemies
  (`StatusEffects.blind_amount`, `Enemy.swing_misses`). Slow scales walking speed and root stops walking/dodging/jumping/
  dashing in `PlayerMovement`/`can_dodge`. **Stun = stagger**: applying a stun staggers
  for its duration (same interrupt and "can't act"); the status entry is the name/timer
  and what a cleanse removes (`cleanse()` also ends the stagger). Enemies: stun =
  `brain.stagger`.
- **Attack speed** (`attack_speed` 1–2, `attack_speed_min_stamina` fraction; Rampage
  1.25 at ≥ 50% stamina; each stack adds `attack_speed - 1`, at most 2: Talon Storm):
  `StatusEffects.attack_speed(defs, stamina fraction)`. In
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
  3 s; Halberd Brace, see `design/classes.md`), **Steadfast** (force + stagger, 4 s; War
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
  `[tree] points` = 22 = the whole tree (every branch 11); the character level gives
  them: 3 at level 1 + 1 a level, so it's full at level 20, and levels 21-30 give a
  class bonus stat instead, see "Progression"): Fighter branches Bulwark and Fury. Same rules and free
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
  Anchor, 22 points): Gale Burst (20 Ember, 12 s: 4 m radial, 60 damage, knockback
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
  how hit events address it (peer ids are always positive). New markers go last, so
  existing ids don't move.
- **Kinds** (session 62, `design/enemies.md`): Husk (2, near (0, -15)), training dummy,
  and three camps far from the spawn, the Husks, the gather nodes and the Forge:
  **Thornling** (`thorn`, 2 east at (24, 0)), **Cinder Seer** (`seer`, 2 west at
  (-24, -6)), **Cragmaw** (`crag`, 1 north-east at (21, -23)). Each has its own loot
  table (`data/loot.cfg` `table_thorn` GS 110–150, `table_seer` 120–160, `table_crag`
  135–175, 2 items) and `[progression]` XP. `[stats] name` is the label's name
  (default: the kind capitalized). Every enemy is in every snapshot (no interest
  management): 8 now; `-Bots 6` measured the max snapshot before adding more.
- **Camps**: a marker's `metadata/camp` (a name). When an enemy starts fighting
  (IDLE → CHASE: `EnemyBrain.pulled`, cleared by `take_pulled`), `World._alert_camp`
  has its idle campmates `alert` (proximity threat on the same player, then chase).
  Husks have no camp. `SUMMARY enemy_kinds spawned=<kind:n,...> kills=<kind:n,...>
  camp_alerts= enemy_projectiles= enemy_projectile_hits=` (the smoke test checks
  every kind spawned).
- **Keep distance** (`[ai] keep_distance` m, `retreat_speed` m/s; optional): while its
  attack cooldown runs, an enemy nearer its target than that backs straight away,
  facing it (`EnemyBrain._back_away`): the Thornling's hit-and-run, the Seer's spacing.
  Past it a melee kind walks back in, so it circles the edge until its next swing.
- **Enemy projectiles**: an `[attack]` with `projectile` (and `shape="none"`): on its
  release tick `Enemy.projectile_released` → `World._on_enemy_projectile` →
  `ProjectileSystem.server_fire_enemy`, aimed at where the target stands as enemies
  see it (a decoy counts) + `[ai] aim_height`. Owned by the enemy id (< 0): hits
  players only, through `resolve_strike` (block, parry, i-frames, statuses), counted
  apart from players' throws (`enemy_projectiles=`). A blinded swing throws nothing.
- **Looks** (client): `EnemyLook.for_kind(kind)` loads `game/enemy/looks/<kind>_look.gd`
  (`build()` adds parts, `base_color()`, `pose(attack_tick)`, `label_height()`; helpers
  `windup_fraction`/`strike_fraction`/`recovery_fraction`, `add_box`, `material`).
  `Enemy` still colors the capsule (telegraph, hit flash, dead) and tilts/lays the body.
  Cosmetic only: every kind hits and is hit with the same capsule (`BODY_RADIUS`,
  `BODY_HEIGHT`), even the bigger Cragmaw.
- Enemy snapshot entries send yaw as a 32-bit float and health rounded up (drawing only).
- Optional `[ai] always_aware` (true on the training dummy): the enemy is never
  "unaware" for backstabs, so only rear-arc hits backstab it
  (`EnemyBrain.is_unaware_of`, used by `World._is_backstab`).
- **Server only**: each tick after the players, `Enemy.server_step` runs its
  `EnemyBrain` (IDLE wander → CHASE its threat target → ATTACK when within
  `attack_range` and off cooldown → back to CHASE; STAGGERED when hit by a staggering
  attack; RETURN home past `leash_range` or when nobody has threat, healing on
  arrival). Movement follows the navmesh (`EnemyPath` via `World/EnemyNav`, re-path every
  0.5 s, when the goal moves 1 m or the map changes; `[navigation]` in the enemy file,
  `data/navigation.cfg`); a swing only starts on a direct path (never through a wall);
  `SUMMARY nav`. The dummy never paths. Not predicted, so no
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
or Esc closes it), T/Y/N/L/Delete party (see below), F interact (pick up your loot in
reach, else gather a node, else use a station: nearest the crosshair within each), P
tradeskills, I
inventory (I or Esc closes it), F3 hitboxes, F1 shows/hides the keybinds list (bottom
left, `KeybindsPanel`: keys read from `InputActions`), Esc frees the mouse. Aimed area abilities
(their zone lands at the crosshair) cast when their key is **released**; holding shows
the marker; right click or Esc cancels (`AimHold`).
Panels that need the mouse join the `modal_ui` group: while one is visible, clicks and
wheel scrolls don't recapture the mouse. I and K close each other
(`InventoryPanel.hide_other_modals`); a closing panel recaptures the mouse only if no
other `modal_ui` panel is visible. 1–9 are reserved for later (consumables):
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
  clicks in the I panel) deletes an item. Inventories live on the server and are saved
  with the character (see "Saving"); ground drops aren't saved.
- **Client**: `LootDropVisual` (sack, a beam in the best item's rarity color, its name
  drawn on top), the "[F] Pick up" prompt and a feed of pickups/notices (`LootHud`,
  canvas layer 2, above the HUD), `InventoryPanel` (I: newest first, rarity color, kind,
  gear score, `Item.stat_lines`). A `--bot` picks up its drops when within 80% of reach.
  Counted in `SUMMARY loot` (server) and `SUMMARY client=N loot` lines; the smoke test
  checks drops and a pickup (with `drop_chance` 1).
- `ItemDatabase.validate()` checks the three files against each other; a unit test runs
  it on the real data. `tools\roll_loot.ps1 [-Table husk] [-Kills 50000]` prints what a
  table really drops.
- An affix may set `min_rarity` (a rarity id): lower rarities never roll it (and roll
  fewer affixes if the slot's pool runs short); `validate()` checks the id. Kindle is
  Epic/Legendary only (about +20–30% Ember gain).
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
- **Item icons** (`ui/item_icon.gd`, `ItemIcon`, drawn in code, rarity-tinted): bag and
  equipped cards, feed lines, the HUD gear box. Resources name theirs (`icon` in items.cfg,
  `ItemDatabase.ICONS`, checked by `validate()`); gear gets one from its slot, weapons
  crossed swords or a bow (`[weapon] ranged=true`: Longbow, Crossbow, Firebolts, Throwing
  Knives, Great Staff, Gauntlet). **Crafted gear** carries `Item.crafted` (set by
  `CraftingRules.roll_gear`): a gold "Crafted" and an anvil badge in the bag.
- **Resources** (`slot="resource"` in items.cfg, `max_stack`): stackable (`Item.count`;
  `Inventory.add_stack` fills stacks then new slots, `room_for`, `count_of`, `remove_count`);
  no rarity, no equip; loot tables can't name them. Three raw ones: Rustvein Ore, Pine
  Log, Thistle Fiber (from Rustvein Deposit, Windbent Pine, Thistlebrush nodes).
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
  weighted by `[average] weights`, every empty slot = GS 100 (the base), so gear only raises it.
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
(In a Linux cloud container: download the Godot 4.7 Linux build and PowerShell 7
(`pwsh`), set `GODOT` to the Godot binary, run `$GODOT --headless --import` once, then
`pwsh -File tools/run_tests.ps1` and `pwsh -File tools/smoke_test.ps1` work as below.)

```
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1          # server + you + a bot window
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -NoBot   # server + 2 player windows
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -Party   # the bot parties with you
powershell -ExecutionPolicy Bypass -File tools\run_server.ps1            # headless server only
powershell -ExecutionPolicy Bypass -File tools\host_playtest.ps1         # server + your window for friends over Tailscale (HOSTING.md)
powershell -ExecutionPolicy Bypass -File tools\export_client.ps1         # build\export\NewerWorld.zip for friends (needs export templates)
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1             # unit tests
powershell -ExecutionPolicy Bypass -File tools\roll_loot.ps1             # what a loot table drops over 50,000 kills
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1            # 2 bots, 32 s, then ~10 s of restart: make an account and character and log in (a fresh database file), move, dodge, fight each other and Husks, block (the bots' duel), die, respawn, abilities, swap, respec, statuses (on a Husk), a bleed tick, Spear, knockback on players (the duel, Husks) and enemies (Husks, the training dummy), Ember gained and spent, Wing abilities, a Rebirth, projectiles thrown and one hitting, Husk loot dropped, picked up and equipped, characters saved (periodic, after changes, on leaving), snapshots under one packet; then a second server on the same database file: the first bot (account smoke_keeper, character Keeper) logs in again and must come back exactly as last saved (fingerprint), and is saved as that server shuts down
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1 -Class assassin   # same, as Assassins (or -Class juggernaut / ranger / mage / paladin)
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1 -Party     # same bots in a party: 0 hits, debuffs, forced moves or projectile hits on each other, Husk fights (and Ember, Wings, a Rebirth, projectile hits) still happen
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1 -Bots 6    # more bots (not with -Party): same checks for each, and snapshots must still fit one packet
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
and `\` for `/` in the `build\smoke`, `build\tests`, `data\class_$Class.cfg` and
`data\weapon_$_.cfg` paths.
That also exercises the script's own argument quoting (a bare quote or space inside
one `--tune` breaks under `Start-Process`; Tuning now logs an error for it).
Both smoke scripts take `-Port N` (default 24599) so parallel runs (e.g. two worktrees)
don't collide. Within one checkout, run them one after the other: they share the
`build\smoke` log folder.

Game flags (after `--`): `--server`, `--port=N`, `--connect`, `--address=host[:port]`,
`--fake-version=X` (claim code version X: tests the version check),
`--db=PATH` (server: the database, default `user://newer_world.db`; `:memory:` = fresh,
gone at exit), `--class=ID` (client: the class the create-character screen offers first;
a `--bot`'s class when it makes its character; default `fighter`, unknown = default),
`--account=NAME` / `--character=NAME` (`--bot`: who it logs in as; see "Accounts"),
`--menu-preview=login|characters|create` (show that start screen with sample data and
never connect; with `--screenshot-dir` the start screens save as `menu_<N>.png`),
`--bot` (auto-connect; repeats every 8 s: take turns attacking and blocking (the nearest
Husk within 15 m, else the nearest player; the heavy starts once within 2.2 m or 0.7 s
into the turn, `World._bot_attack_turn`; after the duel, against a Husk the guard stays
down until a Husk's hit has knocked it back and a bleed has ticked on it, `_bot_invites_husk_hit`), then both use abilities (guard up between; a
knockback ability first), then circle with weapon swap/jump/air dodge/ground dodge, a free
respec (odd cycles also learn new abilities like Rising Cut, or the capstones when there's
nothing new, as for the War Hammer; even cycles learn the built
capstones that fit, i.e. the Spear's Hold the Line and Finishing Thrust,
`BuildService._bot_learn_capstones`) and the next cycle's weapons
(the default loadout in the first cycle; then a different focus weapon each cycle:
Spear, Dual Axes, Broadsword; `BuildService.bot_weapons_for_cycle`); see
`World._bot_input`; it aims like a player, with the crosshair line (shoulder offset) through its target, so attack facing points at it. On joining it slots its status abilities first, self-buffs before
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
before the circling phase; see `World._bot_projectile_button`.
Scheduled so the smoke checks never hang on luck: **the duel** (from 3 s after launch,
instead of the first ability phase and circling: the bots have just joined at full
health and the Husks are still on their way; not with `--bot-party`; `World.BOT_DUEL_*`):
the bots target each other, nothing else pressed; the lower peer id heavies (once in
reach) and taps lights into the other's raised guard (a guard break and a knocked-back
player every run), then from 5.8 s the other lowers its guard and is killed twice (a
Rebirth, its first death, then a respawn: `_bot_execute_input`); over after two kills /
the respawn, at 10 s at the latest; **the first
gather** right after joining, the nearest node however far
(`GatheringSystem.bot_first_move`); **Forge trips** from cycle 1's circling (14 s), the
higher peer id's a cycle later (`CraftingSystem.bot_first_trip_cycle`), so both never
miss the same fight, nor the first Husk fights; after its first craft **it pushes the training dummy** 7 m from the Forge
(a pushing heavy, else a knockback ability, else it swaps; `World._bot_dummy_input`)),
`--bot-party` (with `--bot`: the lower peer id invites the nearest player, and the bot
accepts any invite; it doesn't attack or use abilities (Wings included) until it's in a party, then
still swings at its ally when no Husk is near, which the server ignores; see
`PartySystem._bot_step`), `--verbose` (log positions every 2 s, server logs hits and
refused build changes), `--hitboxes` (start with hitboxes shown; F3 toggles),
`--mastery-panel` (open the K panel at start, for screenshot checks; `--mastery-panel=wings`
opens it on the Wings tab), `--inventory-panel` (open the I panel at start, same use), `--tradeskills-panel` (the P panel), `--crafting-panel` (the nearest station's panel),
`--bot-aim-pitch=DEG` (the bot's aim pitch, up = positive; default 0),
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
in the real data (Husk swings bleed, Broadsword, War Hammer and Dual Talons heavies push) so its
status and force checks don't depend on bot luck, a 1 s Rebirth (`ember/rebirth/duration`)
so a reborn bot is back in the fight quickly, 400-health Husks (they die, for loot
and gear, but most heavies land on a live one), every class's heavy pushing (0 m knockback keys in the
real data; Mage and Paladin heavies too), the Paladin's Shortstaffs heavy applying
Exposed (an empty `applies_status` in the real data), a 1.5 s Shield Wall (a long one kept Husks off the bots), 2 s Javelin Cast / Boomerang Axe /
Shockwave cooldowns for more throws, Earthshaker on every heavy (`aftershocks=` on the
`SUMMARY juggernaut` line, no check), Skewer applying Taunted instead of Root so Husks get taunted
(counted, not checked), and a 6 m Hold the Line reach so pokes (`line_pokes=` on the
`SUMMARY abilities` line, no check) happen in most runs.

To check visuals without a person, use `tools\screenshot_run.ps1 -Dir <relative dir>
[-Seconds N] [-Port N] [-Class ID] [-Resolution WxH] [-ClientArgs ...] [-Tune ...]` and
read the saved frames. **Never let a launch take the developer's focus** (they work in
other apps meanwhile): the script runs the server headless with its log in a file (no
console window) and the windowed `--bot` client with a temporary `override.cfg`
(`display/window/size/no_focus=true`, gitignored, deleted once the client is up), so
it still renders but can't be focused. Don't start windowed or console processes any
other way. **Agents' shells have no console**, so any console program they start
(`powershell -File ...`, Godot's `_console.exe`) opens a new, focused console window
(it minimized the developer's fullscreen game). So: run the tool scripts **in-process**
from the PowerShell tool (`Set-ExecutionPolicy -Scope Process Bypass -Force;
& .\tools\smoke_test.ps1 -Port N`), never `powershell -File`/`Start-Job`; the scripts
start every console Godot with `Start-Process -WindowStyle Hidden` (a hidden console
can't take focus). `run_local_test.ps1` and `run_server.ps1` are the developer's and
still open visible windows on purpose. (Verified 2026-10-13: tests, a screenshot run and
a smoke run in-process opened no visible console and never took focus.) Never screenshot the desktop: it captures the developer's screen.

Every script that dot-sources `tools\find_godot.ps1` (run, smoke, tests, screenshots,
roll_loot) first runs `--headless --import` (~3 s), which registers new `class_name`
scripts after a pull, merge or fresh worktree; without it scripts that use them fail to
parse ("Could not find type ..."). Run it by hand only when launching Godot another way.
`--check-only --script` gives false "Tuning not found" errors because it skips autoloads;
use the smoke test instead.

## Export and hosting

- `export_presets.cfg` has a "Windows Desktop" preset (one exe with the pack embedded,
  `include_filter="data/*, code_version.txt"`: `data/*.cfg` aren't Godot resources;
  tests/tools/design excluded). `tools\export_client.ps1` writes `code_version.txt`
  (see "Code version check"), exports to `build\export\` and zips it; it
  needs Godot's export templates (installed from the editor). The zip holds the exe
  and the godot-sqlite DLL exported beside it (session 55: the exe ran as a headless
  server).
- Playtests with friends: `HOSTING.md` (Tailscale node sharing, firewall rule,
  `tools\host_playtest.ps1`: a visible server console + the developer's window, prints
  the Tailscale address; `-NoClassChange`). The developer's script: never run it from
  an agent.
- A dedicated server export should use the "Dedicated Server" preset; `main.gd`
  treats the `dedicated_server` feature tag like `--server`.

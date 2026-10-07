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
  player/player_state.gd     Stamina, dodge, attacks, facing, input buttons. Pure logic, unit tested.
  player/player_params.gd    Player tuning converted to ticks/radians, loaded once.
  combat/attack_params.gd    One attack's tuning (phases, damage, hitbox).
  combat/melee_hitbox.gd     Box hitbox vs capsule test. Pure math, unit tested.
ui/                  connect_menu (client start screen), hud (health/stamina bars, debug info).
data/                Tuning files: network, movement, combat, camera, weapon_sword (.cfg).
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
  `PlayerState.BUTTON_*` bits: jump and attack are sent while held, dodge only on the tick
  it's pressed (the sim buffers it). Tap vs hold (light vs heavy) is decided inside the
  sim from the held bit. `aim_yaw` is the camera yaw; attacks face it. New actions
  (block) get new bits.
- **Server**: queues inputs per player (validated, bounded by `max_input_buffer`) and
  simulates at most `max_inputs_per_tick` per tick. **One input = one sim step**; a
  player with no queued input doesn't move. That keeps server and client in lockstep.
- **Server → each client**, `snapshot_rate` times per second, `World._receive_snapshot`
  (unreliable ordered, channel 2): `tick` and every player's
  `[peer_id, position, velocity, last_processed_seq, PlayerState.to_array(), health]`.
  Snapshots also drive spawning/despawning on clients: new id → spawn, missing id → remove.
- **Local player**: applies each input immediately and remembers the predicted position
  and `PlayerState` per seq. On a snapshot, if the server's position or state for
  `last_processed_seq` differs from the prediction, it restores the server's position,
  velocity and state and replays unacknowledged inputs ("corrections" on the HUD; should
  stay 0 on localhost).
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

- Attacks: windup → active (hitbox live) → recovery, all in ticks from the weapon file.
  A dodge can cancel recovery only. Presses during an attack or roll are buffered.
  Facing locks to `aim_yaw` for the whole attack; movement is slowed by `move_multiplier`.
- **Hits are server-only.** After each server sim step with a live hitbox, `Player` emits
  `attack_stepped`; `World._on_attack_stepped` tests `MeleeHitbox.hits` against every
  other player's current server position. Each target is hit at most once per attack
  (`Player.attack_results`). A target in i-frames "evades" (reported once) but can still
  be hit later in the same active window.
- Health is server-owned, outside `PlayerState` (clients don't predict damage), sent in
  snapshots. Hit events go to clients via reliable `World._receive_hit`
  (`HIT_DAMAGED` / `HIT_EVADED` / `HIT_DEFEATED`) for damage numbers and the red flash.
- No death yet: at 0 health the server refills it and reports `HIT_DEFEATED`.
- No lag compensation yet: hits use targets' current server positions, while the
  attacker sees them `interpolation_delay` in the past.
- Only the sword exists; `PlayerParams.from_tuning` reads `data/weapon_sword.cfg`.

## Running

Godot was installed with winget; there is no `godot` on PATH. `tools/find_godot.ps1`
locates it (override with the `GODOT` env var). PowerShell blocks scripts by default, so
run them with `-ExecutionPolicy Bypass`:

```
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1        # server + 2 client windows
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -Bot   # second client is a bot
powershell -ExecutionPolicy Bypass -File tools\run_server.ps1            # headless server only
powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1             # unit tests
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1            # 2 bots: move, dodge, air dodge, fight; server must resolve hits; 0 corrections
```

Run both `run_tests.ps1` and `smoke_test.ps1` before committing.

Game flags (after `--`): `--server`, `--port=N`, `--connect`, `--address=host[:port]`,
`--bot` (auto-connect; repeats every 6 s: fight the nearest player, then circle with
jump/air dodge/ground dodge; see `World._bot_input`), `--verbose` (log positions every 2 s,
server logs hits), `--hitboxes` (start with hitboxes shown; F3 toggles),
`--screenshot-dir=PATH` (save the game window every 0.25 s, for checking visuals),
`--quit-after=SECONDS` (prints `SUMMARY` lines, used by the smoke test).

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

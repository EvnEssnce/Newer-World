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
- **Tests** (GUT, not installed yet) for systems that don't depend on feel: loot rolls,
  damage formulas, crafting outputs, inventory rules. Combat feel is playtested by hand.
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
  world/world.gd     Server sim loop + snapshots; client input sending, prediction, interpolation.
  player/player.gd   One player; server/local/remote roles (see below).
  player/player_movement.gd  Shared deterministic movement step.
ui/                  connect_menu (client start screen), hud (debug overlay).
data/                Tuning files: network.cfg, movement.cfg, camera.cfg.
assets/              CC0 art packs go here (Kenney, Quaternius, Mixamo).
tests/               GUT tests (none yet).
tools/               PowerShell run scripts and the smoke test.
```

## Networking model

- The server is peer 1. `World` exists at `/root/Main/World` on every machine, because
  RPCs are matched by node path. Player nodes are named by peer id under `World/Players`.
- `server_relay` is off: clients never hear from each other directly, only via snapshots.
- **Client → server**, every physics tick, `World._submit_inputs` (unreliable ordered,
  channel 1): the last `input_redundancy` inputs, each `[seq, move: Vector2, jump: bool]`.
  `move` is a world-space XZ direction (camera rotation already applied), length ≤ 1.
- **Server**: queues inputs per player (validated, bounded by `max_input_buffer`) and
  simulates at most `max_inputs_per_tick` per tick. **One input = one movement step**; a
  player with no queued input doesn't move. That keeps server and client in lockstep.
- **Server → each client**, `snapshot_rate` times per second, `World._receive_snapshot`
  (unreliable ordered, channel 2): `tick` and every player's
  `[peer_id, position, velocity, yaw, last_processed_seq]`. Snapshots also drive
  spawning/despawning on clients: new id → spawn, missing id → remove.
- **Local player**: applies each input immediately (`PlayerMovement.step`) and remembers
  the predicted position per seq. On a snapshot, if the server's position for
  `last_processed_seq` differs from the prediction by more than `RECONCILE_TOLERANCE`,
  it rewinds to the server state and replays unacknowledged inputs ("corrections" on the HUD).
- **Remote players**: drawn `interpolation_delay` seconds in the past, interpolated
  between snapshots on a render clock synced to server ticks.
- Players don't collide with each other (layer 2, mask 1). The world is layer 1.
- Anything that changes movement must change `PlayerMovement.step`, which both the server
  and the prediction run. Keep it deterministic and free of `Input` reads.

## Running

Godot was installed with winget; there is no `godot` on PATH. `tools/find_godot.ps1`
locates it (override with the `GODOT` env var). PowerShell blocks scripts by default, so
run them with `-ExecutionPolicy Bypass`:

```
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1        # server + 2 client windows
powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -Bot   # second client is a bot
powershell -ExecutionPolicy Bypass -File tools\run_server.ps1            # headless server only
powershell -ExecutionPolicy Bypass -File tools\smoke_test.ps1            # automated: 2 bots must see each other move
```

Game flags (after `--`): `--server`, `--port=N`, `--connect`, `--address=host[:port]`,
`--bot` (auto-connect and walk in circles), `--verbose` (log positions every 2 s),
`--quit-after=SECONDS` (prints `SUMMARY` lines, used by the smoke test).

After adding a `class_name` script outside the editor, run
`<godot_console.exe> --headless --import` once so Godot registers the class.
`--check-only --script` gives false "Tuning not found" errors because it skips autoloads;
use the smoke test instead.

## Export notes (for later)

- `data/*.cfg` aren't Godot resources: add `data/*` to the export preset's
  "include non-resource files" filter, or exported builds won't find tuning files.
- The dedicated server export should use the "Dedicated Server" preset; `main.gd`
  treats the `dedicated_server` feature tag like `--server`.

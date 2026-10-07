# Progress

## Current milestone

**1. Networked combat slice.** Movement, stamina and dodge roll are networked. Next up:
attacks, block, one enemy.

## Session log

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

- Godot 4.7.2, git, private GitHub repo (`EvnEssnce/newer-world`), folder layout, docs.
- Dedicated server (`--headless -- --server`), client connect screen.
- Server-authoritative movement, client prediction + reconciliation, snapshot
  interpolation for other players. Hand-tested with two windows: smooth.
- Smoke test (`tools/smoke_test.ps1`).

## Next

1. Hand-playtest the air dodge.
2. Milestone 1, one session each:
   - Light and heavy attacks (sword) with server-side hitbox detection against other
     players, respecting i-frames. Damage and timings in `data/combat.cfg`.
   - Health, hit reactions, death/respawn.
   - Block (stamina drain on hit).
   - One enemy type with server-driven AI.
   - Swap the capsule for a CC0 character with Mixamo idle/run/roll animations
     (download the packs yourself; Mixamo needs an Adobe login).

## Known issues / notes

- Movement and combat tuning are read separately by server and client. If they run
  different `data/*.cfg` files, prediction will constantly correct. Later: the server
  could send its values on connect.
- Clients send input every physics tick (60/s) and get full snapshots of every player
  (including their stamina). Fine for 50 players on a LAN; add interest management
  and delta compression before a public playtest.
- No render smoothing after a correction yet: a big correction snaps the local player.
- Holding Space keeps jumping (jump is sent as "held").
- Dodge momentum stops abruptly at the end of the roll (ground deceleration takes over).
  May want a recovery phase; judge in playtest.
- This repo has a local git `user.name`/`user.email` (no global identity configured).

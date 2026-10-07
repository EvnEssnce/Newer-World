# Progress

## Current milestone

**1. Networked combat slice.** Movement, stamina, dodge and sword attacks are networked.
Next up: death/respawn and hit reactions, block, one enemy.

## Session log

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

1. Hand-playtest right-click heavy and attack aim tracking.
2. Milestone 1, one session each:
   - Death/respawn and hit reactions (stagger on heavy hits?).
   - Light attack combo chain (New World-style 3-hit string)?
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
- Dodge recovery into movement was judged smooth in playtest (no recovery phase needed).
- No lag compensation for hits: the server checks targets' current positions, while
  the attacker sees them ~100 ms in the past. Fine on LAN; matters over the internet.
- Hit events arrive before the attacker's swing is drawn on other clients (remote
  players are drawn 100 ms in the past, hit events aren't delayed).
- Attacks pass through crates (the hitbox ignores world geometry).
- Placeholder sword swing/flash/damage-number constants live in `player.gd` (cosmetic
  only, to be replaced by real animation and VFX).
- This repo has a local git `user.name`/`user.email` (no global identity configured).

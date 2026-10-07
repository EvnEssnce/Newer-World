# Progress

## Current milestone

**1. Networked combat slice.** Movement networking is in place; combat isn't started.

## Session log

### 2026-10-07: Project setup and networked movement

Done:
- Installed Godot 4.7.2 (winget). Set up git, `.gitignore`, `.gitattributes`, folder
  layout, `CLAUDE.md`, this file.
- Dedicated server: `--headless -- --server`. Client connect screen with address field.
- Server-authoritative movement: clients send inputs, the server simulates and sends
  snapshots at 20 Hz. Client-side prediction with reconciliation for your own player,
  interpolation for everyone else.
- Placeholder world (ground plane, three crates), capsule players with a "nose" showing
  facing, third-person orbit camera, debug HUD (ping, snapshots, corrections).
- Tuning in `data/network.cfg`, `data/movement.cfg`, `data/camera.cfg`.
- `tools/smoke_test.ps1`: two headless bot clients must see each other move. Passing:
  each client sees the other move about 46 m in 8 s, with 0 prediction corrections on localhost.

Not yet verified by a person: two **windowed** clients played by hand. Run
`tools\run_local_test.ps1` (or `-Bot`) and check that movement looks smooth in both
windows.

## Next

1. Hand-check `run_local_test.ps1`: both windows see each other move smoothly.
2. Create the private GitHub repo and push (needs `gh` or the GitHub website; see below).
3. Milestone 1, one session each, e.g.:
   - Replace capsules with a Quaternius/Kenney character plus Mixamo idle/run animations,
     driven by the networked velocity.
   - Stamina + dodge roll with i-frames, all values in `data/combat.cfg`.
   - Light/heavy attacks with server-side hitbox detection.
   - Block. Then one enemy type (server-driven AI).
4. Install GUT when the first non-feel system (damage formula) arrives.

## Known issues / notes

- Movement tuning is read separately by server and client. If they run different
  `movement.cfg` files, prediction will constantly correct. Later: the server could
  send its movement values on connect.
- Clients send input every physics tick (60/s) and get full snapshots of every player.
  Fine for 50 players on a LAN; add interest management (only nearby players) and
  delta compression before a public playtest.
- No render smoothing after a correction yet: a big correction snaps the local player.
  Revisit if corrections show up over real internet latency.
- Holding Space keeps jumping (jump is sent as "held", not "just pressed").
- No git identity was configured globally; this repo has a local `user.name`/`user.email`.

## Pushing to GitHub

`gh` isn't installed. Either install it (`winget install GitHub.cli`, then
`gh auth login` and `gh repo create newer-world --private --source . --push`), or create
an empty private repo on github.com and run:

```
git remote add origin https://github.com/<you>/newer-world.git
git push -u origin main
```

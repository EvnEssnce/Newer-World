# Progress and plan

The one planning document: what we're building, where it stands, the build order from
here, and what's outstanding. `CLAUDE.md` describes the architecture; `design/classes.md`
holds the class/weapon/ability design. Read both this file and `CLAUDE.md` at the start
of every session.

**At the end of every session:** add a short entry to the session log (what was done,
tests/smoke results, what needs a playtest), tick off or reorder the build order, and
update the outstanding lists. Keep entries short; details belong in commits and
`CLAUDE.md`.

---

## 1. The brief

**Newer World** (working title) is a small online action RPG with combat, gathering,
crafting, loot and movement modeled on New World: Aeternum, with low-poly graphics. The
target is 10–50 players per server instance with persistent characters. It is
deliberately not a true MMO: no territory wars, no server-wide trading post economy, no
housing, no large-scale open-world events. PvE is the main focus; PvP is minor.

### Decisions that stand

- **Engine:** Godot 4.7, GDScript. Client and headless dedicated server from one project.
- **Networking:** server-authoritative from the start. The server decides hits, loot,
  inventory and crafting; clients predict only their own movement.
- **Persistence:** SQLite in development behind one persistence module, Postgres before
  launch. Nothing else touches the database.
- **Art:** CC0 placeholder packs (Kenney, Quaternius) and Mixamo animations. Paid art
  waits until the game is fun with ugly art.
- **IP:** mechanics can be borrowed; names, art, UI layouts and item names are original.
- **Budget:** the developer's Claude Pro subscription. No paid services until an
  always-on server is needed (see "Costs").
- **Changed since the original brief:**
  - **No attributes** (STR/DEX/...). Builds come from mastery trees and gear; gear
    stats change combat numbers directly. Phoenix/fire-themed attributes may come later.
  - **Classes** (fixed per character) own their weapons and **Wing** abilities, fuelled
    by **Ember**, with an automatic **Rebirth**. Six classes are designed in
    `design/classes.md`; the Fighter and Juggernaut are built.
  - **Gear score follows New World's curves** (session 28): main stats ×1.0112 per 5
    GS (slower above 500), armor mitigation = armor / (armor + attacker GS^1.2).
  - **Equip slots:** Weapon 1, Weapon 2, Head, Chest, Legs, Wing Enhancement. Armor
    fits any class; weapons and Wing Enhancements are class-locked. Equipping takes 1 s.
  - **Tests** use a small in-repo runner (`tests/framework/`), not GUT.

### Systems in scope

| System | What it means | Status |
|---|---|---|
| Combat | Action combat: light/heavy, block, dodge with i-frames, stamina, hitbox melee | Built |
| Weapons | Two equipped, swap key, abilities on cooldowns, mastery trees | Built (6 weapons) |
| Classes & Wings | Class-locked weapons, Wing abilities, Ember, Rebirth | Fighter, Juggernaut, Assassin built (Assassin: decoy/stealth Wings not yet) |
| Loot | Loot tables, rarity tiers, rolled stats, gear score ranges | Built |
| Inventory | Equipment slots, item weight, durability | Slots built; weight and durability not |
| Gathering | Ore, wood, fiber, hide nodes; tool requirements; respawn timers | Not started |
| Crafting | Tradeskill XP curves, refining chains, recipes, stations | Not started |
| Persistence | Accounts, character saves | Not started |
| Progression | Character level, weapon mastery levels (1 point per level, cap 20) | Not started (all points free) |
| Zone | Mob camps, node spawns, a town with crafting stations | Test map only |

---

## 2. Where we are

| Milestone (original build order) | Status |
|---|---|
| 1. Networked combat slice | **Done** (session 9; developer: "the combat loop is great") |
| 2. Loot loop | **Built** (sessions 10, 27, 28); needs its playtest |
| 3. Gathering and crafting | Not started |
| 4. Second weapon and weapon swap | **Done**, and well past it: Fighter (Broadsword, Spear, Dual Axes) and Juggernaut (Halberd, Greataxe, War Hammer), all abilities and capstones, Wings, statuses, forced movement, projectiles, parties, enemy threat (sessions 11–25) |
| 5. Persistence | Not started |
| 6. One zone, then playtest with real people | Not started |

**Session 32:** the **Assassin** class (Dual Talons, Throwing Knives, two of four Wing
abilities), unplaytested; see §4.

**Latest state (session 28):** Husks drop personal loot; F picks it up; I opens the
inventory with equipped gear; gear changes damage, crits, armor, max health, block
stamina, healing and Ember. A training dummy (6,000 HP, DPS readout) stands at z = +18
(session 30). 450 unit tests; the real `smoke_test.ps1` (run with PowerShell 7 on Linux,
session 31) passes for Fighter, Fighter in a party and Juggernaut with 0 prediction
corrections.

---

## 3. Build order from here

Rule from the brief: **don't start a step until the one before it works** (built, tested
and playtested). Each numbered item is roughly one session with one testable goal.

### Step A: Close out Milestone 2 (loot loop)

1. **Playtest** sessions 27–28 and 30 (no code; checklist in §4). Fix what the
   playtest finds. Then Milestone 2 is done. (The smoke scripts themselves were run in
   session 31 with PowerShell 7 on Linux, which found and fixed a quoting bug in the
   loot `--tune`; a Windows run is still worth doing once.)
   - Item weight and durability are in the brief but not built: durability goes with
     repairs in Step D; weight is an open decision (§4).

### Step B: Wave 3 combat feedback (decided in session 26, in this order)

2. **Done (session 30).** **Training dummy:** a new enemy kind (`data/enemy_dummy.cfg`), 6,000 HP, never moves
   or attacks, heals after a few seconds idle; one marker on the far side of the test
   map from the Husks; a DPS readout above it. No loot table. (Helps tune everything
   after it, including gear.)
3. **Juggernaut weight** (Greataxe and War Hammer only; the Halberd stays the light
   option): longer windups/recoveries, and **hyper armor**: can't be staggered (still
   takes damage) during the windup and swing of their heavies and big abilities. Likely
   `armor_start`/`armor_end` attack keys checked where the server staggers a player
   (`apply_stagger` callers); decide whether it also resists knockback.
4. **Earthshaker:** the every-3rd-heavy aftershock becomes one **expanding ring** around
   the user (hits each target once), not a forward wave. The **Shockwave** ability stays
   a single forward wave, a bit **wider** (`projectile_shockwave` `hit_radius`/`length`).
5. **Small ones:** **Hooked** only applied when the Warden capstone is learned;
   **Shatter** cooldown 12 → ~6 s; **Meteor Drop** rises slower (~30% longer climb, same
   fast crash); **Upheaval** animation reads as slamming the ground, not a swing.
6. **Shield Wall redesign** (the cover-allies version is hard to use): summon a wall of
   three tall shields in front that blocks enemies' movement. The first `SUMMON`: a
   server-spawned obstacle with spawn/despawn events to clients (like projectiles).
   Decided: blocks **only enemies** (the user and allies walk through; treat hostile
   players as blocked unless that's hard), **stops hostile projectiles** (yours and
   allies' pass), about **3 m in front**, **4.5 m wide × 2.5 m tall**, lasts **8 s**,
   **18 s** cooldown, **doesn't move** once placed, not breakable yet but shaped so it
   **can take health later**.
   - Playtest steps 2–6 together.

### Step C: Network headroom (before any test with more than 2 players)

7. **Snapshot size:** with 2 players + 2 Husks a snapshot already reaches ~1.41–1.45 KB,
   over ENet's 1392-byte MTU; a third player always goes over. Add **interest
   management** (only nearby players/enemies) and **delta compression** (send what
   changed since the last acknowledged snapshot). Measure with a 6–10 bot stress run.
   Probably 2 sessions. Every later step adds players, enemies or state, so this comes
   first.

### Step D: Milestone 3, gathering and crafting

Brief: two or three node types, one refining step, one crafting station, tradeskill XP.

8. **Stackable resources in the inventory** (ore, wood, fiber, hide; stacks with a max
   size) and **gathering nodes**: server-side nodes with a hit count, a tool requirement
   (pickaxe, axe, sickle, skinning knife as tool items or a simple "has the tool" rule),
   a gather time (walk-only lock like equipping), respawn timers, all in `data/`.
   Gathering key: decide (F is pickup; maybe F on a node too).
9. **Tradeskills:** XP curves per skill (`data/tradeskills.cfg`), XP from gathering,
   higher skill = faster gathering or more yield. Pure logic + tests.
10. **Refining and a crafting station:** one refining chain (ore → ingots), recipes in
    `data/recipes.cfg`, a station object in the world, a crafting panel; the server
    checks materials, station range and skill. Pure recipe logic + tests.
11. **Crafted gear:** recipes that output gear through `LootRoller` (gear score range
    from skill, rarity chance), so crafting feeds the same items as loot. Durability and
    repair (with materials) if decided in §4.
    - Playtest Milestone 3.

### Step E: Milestone 5, persistence

12. **Persistence module:** SQLite through one module (a Godot SQLite GDExtension such as
    godot-sqlite; check it supports 4.7), schema for accounts and characters, migrations.
    Pure save/load of `CharacterBuild`, `Inventory`, `Equipment`, tradeskills (unit
    tested with a temporary database).
13. **Accounts and character select:** simple login (name + password hash), create a
    character (class picker instead of `--class`), choose it on connect.
14. **Saving:** save on change and periodically; load on join; survive a server restart
    (the brief's "done" check). Add a smoke check that restarts the server mid-run.

### Step F: Progression (needed by the class design; not in the original milestones)

15. **Character level and XP** (from kills and gathering), Wing tree points from level,
    **weapon mastery XP** per weapon (1 point per level, cap 20, as in
    `design/classes.md`). Today every tree has its points from the start. Pure logic +
    tests; saved through the persistence module.

### Step G: Milestone 6, one zone, then real people

16. **Enemy navigation:** navmesh steering (Husks get stuck on crates today).
17. **More enemies and camps:** 2–3 new enemy kinds with their own loot tables and gear
    score ranges (today everything drops GS 100–140), placed as camps.
18. **The zone:** a small map built from CC0 packs: mob camps, gathering node spawns, a
    town with crafting stations, spawn points.
19. **Internet readiness:** lag compensation for hits (rewind targets by the attacker's
    interpolation delay), render smoothing after corrections, the server sending its
    tuning on connect.
20. **Art pass basics:** a CC0 character with Mixamo idle/run/roll/attack animations
    in place of the capsule (download the packs yourself; Mixamo needs an Adobe login).
21. **Playtest with real people:** host on the developer's PC over Tailscale (free), or a
    Hetzner CX23 billed by the hour (§7).

### Class track (fits after Step E, or between steps when the developer wants)

Order from `design/classes.md`: ~~Assassin~~ (built in session 32 except Ember Double,
Shadow Swap, Ricochet and Recall, which need decoys/stealth/new projectile kinds)
→ **Ranger** → **Mage** → **Paladin**. Each class is about 2–3 sessions (weapons,
trees, Wings, models), plus the systems it needs:
- `SUMMON` (built in step 6 for Shield Wall), `AREA` ground effects and traps (Ranger,
  Mage), **stealth** (Assassin), **updraft hover** (Wings), weapon abilities that cost
  Ember (Mage), and the Paladin's Rebirth hooks (already in `PlayerState`).
- Each new class needs items in `data/items.cfg` (its weapons and a Wing Enhancement)
  and loot table weights.

### Later / unscheduled

- Stamina gear stats (Ferocity, Rage): make max stamina and stamina regen synced
  `PlayerState` values, then switch the affixes back on (`slots` in `affixes.cfg`).
- Light attack combo chain (New World-style 3-hit string)?
- Salvage, item levels beyond GS 140, perks with effects (not just stats).
- Exports: `data/*` in the export filter; the "Dedicated Server" preset.

---

## 4. Outstanding work

### Needs a hand playtest (`run_local_test.ps1`)

**Loot (session 27):**
- Kill Husks: do drops read well (sack, beam, name, rarity colours)? Is the 2.5 m pickup
  reach right?
- The F prompt and the pickup feed; the I panel (scroll, Discard twice, I/Esc close,
  mouse comes back).
- With the bot (`-Party` too): you only see your own drops.

**Gear (session 28):**
- Equip armor: is ~20% less damage from a full set noticeable? Is 1 s to equip right?
- Equip a weapon type you don't have out ("Replace ..."), then change weapons in K: the
  item should follow its type or return to the bag.
- A Wing Enhancement: Wing abilities hit a bit harder; Kindle gives more Ember.

**Training dummy (session 30):** walk to z = +18 (past Crate3): does the "You: N dmg
N DPS N s" readout above it read well and match what you dealt (bleed ticks too)? Does
it heal and stand back up 4 s after you stop? It drops nothing.

**Assassin (session 32, `run_local_test.ps1 -Class assassin`):**
- Talons feel: is a 0.28 s light too fast/too weak? Pounce's reach and hop; Talon Spin;
  Hook Talon's 2 m pull; Eviscerate on a low Husk.
- Backstabs: hit a Husk that's chasing the bot (or from behind): with Unseen Strike
  learned (K, Predator capstone) every one should say "Critical!".
- Feint: Feint a Husk mid-swing (or the bot while it blocks): the next hit crits.
- Talon Storm (Tempest capstone): a long combo of lights should visibly speed up.
- Knives: light/heavy throws, Fan of Knives, Pinning Knife slow, Venom Coat poison
  ticks; Marked Blade then a Talon hit (+50%); Endless Flurry (every 5th throw fans).
- Wings: Ashstep distance and feel; Plumage Flash's cone and Dazzled.
- Models: claws on the fists, knives in the hands (no throw animation beyond the swing).

**Still unseen from Wave 3:** the War Hammer's Breaker capstone breaking a real guard.

**Run on Windows once:** `smoke_test.ps1`, `-Party` and `-Class juggernaut`. Session 31
ran the real scripts under PowerShell 7 on Linux; Windows PowerShell 5.1 builds the
command line the same way, but hasn't been tried with the fixed loot `--tune`.

### Decisions to confirm (the defaults that were built)

Loot and gear:
- F takes every drop of yours in reach at once (no loot window); no pickup while
  defeated; a discarded item is deleted, not dropped.
- Damage over time counts as damaging an enemy (you get a loot roll); a Husk that walks
  home and heals forgets who hit it.
- Armor rating grows on the same gear score curve as weapons (the source only gives the
  weapon formula); affix values still grow linearly with gear score.
- Armor doesn't reduce damage over time (bleed).
- Average gear score: empty armor slots count 0, a plain weapon counts 100.
- While equipping you walk at full speed; a stagger doesn't interrupt it; raising max
  health doesn't heal you.
- New affixes **Tend** (healing received) and **Kindle** (Ember gained); Ferocity and
  Rage (stamina) are off until stamina is synced.
- The bot never equips weapons (it picks weapons per cycle in the K panel).

Assassin (session 32):
- Backstab = from the rear 180°, **or any hit on an enemy that isn't targeting you**
  (idle or fighting someone else): in a party the non-tank backstabs constantly.
- The Predator capstone crits backstabs instead of "hits from behind ignore block"
  (blocks only cover the front 120°, so that was already true).
- Feint reads blocks, guard breaks and dodges (players) or an enemy mid-swing (Husks
  never block or dodge); Primed lasts 4 s and is used by the next hit even if that hit
  is blocked.
- Marked's bonus needs a melee hit (a knife doesn't use it); Venom Coat's poison also
  rides on Talon hits (it's "your next 5 hits", like Bloodlust).
- Festering Wounds cuts healing on players only (Husks don't heal from anything it
  covers); Endless Flurry's free fan uses no cooldown.
- Plumage Flash: Dazzled is −25% damage dealt (the design's "aim and turn speed
  reduced" has no equivalent on enemies yet) plus a Slow.
- Both Wing capstones and two Wing abilities wait for decoys/stealth (`effect="none"`).

Open questions for coming steps:
- **Item weight / encumbrance:** in the original brief. Build it (and how: a carry
  limit that slows you?) or drop it?
- **Durability:** gear wears down on death/use and is repaired with materials (needs
  crafting)? Or skip?
- **Gathering key:** F for nodes too, or a separate key?
- **Mage vs Paladin "Great Staff":** the design calls the Paladin's the Longstaff; confirm
  before the class track reaches them.

### Known issues

Gameplay:
- Husks steer straight at their target (no navmesh): a crate between you and a Husk can
  stall it (step 16).
- A heavy's hitbox can hit both Husks at once when they stand together.
- Attacks pass through crates (hitboxes ignore world geometry).
- Projectiles fly flat (no aim pitch); no impact effect; rarely a thrower sees its own
  throw twice.
- Statuses only tick while a player's inputs arrive (keeps prediction exact; a lagging
  player's bleed pauses). Bloodlust survives a weapon swap.
- Blocked hits never push; bodies pass through each other when knocked back.
- Crashing Leap's height is cosmetic (can't reach ledges). F3 draws Vortex at its base
  3.5 m even with Maelstrom. Hold the Line has no poke animation.
- Newly equipped weapons start with cooldowns at 0.
- The greataxe model is mostly hidden behind the body from the follow camera.
- A drop scattered next to a crate can land inside it (still picked up from beside it).
- Holding Space keeps jumping (jump is sent as "held").
- Builds, inventories and gear are lost on disconnect (Step E).

Networking:
- Snapshots exceed the MTU at worst with 2 players + 2 Husks (Godot warns "above the
  MTU"); a third player always does (step 7).
- No lag compensation; hit events arrive before the attacker's swing is drawn on other
  clients; no render smoothing after a correction (step 19).
- Server and client read tuning separately: different `data/*.cfg` files mean constant
  corrections (step 19: send tuning on connect).
- About 1 smoke run in 20 shows a few (≤4) small unexpected corrections on flat ground
  (~0.1 m sideways, identical `PlayerState`, so it's in the physics step). The smoke
  test tolerates ≤5; run with `--verbose` for details.
- When 9 bots quit at once the server had one ~100 ms tick (disconnect handling).

Testing:
- Bot-luck smoke checks still fail about 1 run in 10: "no hit landed on a guard", "no
  Husk / no player was moved by force". Rerun once; a second failure is real.
- Linux cloud runner only: two bots quitting at the same instant sometimes print
  `party_members=0` for one of them (quit timing, not a party bug).

Housekeeping:
- Placeholder swing/flash/damage-number constants live in `player.gd` (cosmetic, to be
  replaced by animation and VFX).
- This repo has a local git `user.name`/`user.email` (no global identity configured).

---

## 5. How to work in this repo

- One testable goal per session ("dodge roll with i-frames, tunable from one config
  file", not "work on combat"). The developer is on Claude Pro: keep sessions focused,
  don't re-explore the codebase (read `CLAUDE.md` and this file instead).
- Every tuning value goes in `data/*.cfg` with a comment (what it does, units); the
  developer tunes feel by editing those files.
- Tests for anything that isn't feel (loot, damage formulas, crafting outputs, inventory
  rules, stamina/dodge rules); feel is playtested by hand. Run the unit tests and both
  smoke tests before committing (see `CLAUDE.md` "Running"; Linux cloud sessions have
  their own notes there).
- Git from the first commit, private GitHub repo (`EvnEssnce/Newer-World`).

---

## 6. Session log

Full entries for sessions 1–28 are in git history: `git show 5cc5148:PROGRESS.md` (session 30: `git show 8f18730:PROGRESS.md`).

| # | Date | What |
|---|---|---|
| 1 | 2026-10-07 | Project setup; dedicated server; networked movement with prediction |
| 2 | 2026-10-07 | Stamina and dodge roll with i-frames |
| 3 | 2026-10-07 | Dodge feedback; air dodge |
| 4 | 2026-10-07 | Neutral dodge rolls forward |
| 5 | 2026-10-07 | Light and heavy sword attacks, server hit detection, health |
| 6 | 2026-10-07 | Attack feedback: camera-tracked swings, shorter reach |
| 7 | 2026-10-07 | Death, respawn, stagger; `--tune` |
| 8 | 2026-10-07 | Block and guard break; on-floor synced |
| 9 | 2026-10-07 | First enemy (Husk); **Milestone 1 done** |
| 10 | 2026-10-07 | Items and loot rolls (Milestone 2, part 1) |
| 11 | 2026-10-07 | Parties and the ally rule (Wave 1B) |
| 12 | 2026-10-07 | Abilities, weapon swap, mastery trees, the Fighter (Wave 1A); **Milestone 4 done** |
| 13 | 2026-10-08 | Wave 1 fixes; startup lag (ENet throttle off); `--perf-log` |
| 14 | 2026-10-08 | Status effects (Wave 2A) |
| 15 | 2026-10-08 | Forced movement, Rising Cut, the Spear (Wave 2B) |
| 16 | 2026-10-08 | Wave 2 feedback: dodge cooldown, Shield Charge groups, Vault |
| 17 | 2026-10-08 | Shield Charge impact radius; Vault facing |
| 18 | 2026-10-08 | Ember, Wings and Rebirth (Wave 2D) |
| 19 | 2026-10-08 | Feather projectiles (Wave 2C); Wave 2 complete |
| 20 | 2026-10-08 | Wave 2 feedback (plan) |
| 21 | 2026-10-08 | Broadsword stab, Boomerang Axe visuals |
| 22 | 2026-10-08 | Crashing Leap aimed by pitch; Diving Strike shape |
| 23 | 2026-10-09 | Spear Skewer and Perforate |
| 24 | 2026-10-09 | Finishing Thrust, Hold the Line, Rampage, Shield Wall; enemy threat |
| 25 | 2026-10-09 | The Juggernaut: Halberd, Greataxe, War Hammer, Wings, crits |
| 26 | 2026-10-09 | Wave 3 playtest feedback (Step B's plan) |
| 27 | 2026-10-09 | Loot drops, F pickup, I inventory (Milestone 2, part 2) |
| 28 | 2026-10-10 | Equipping gear: 6 slots, New World gear score, armor, 1 s equip (Milestone 2, part 3) |
| 29 | 2026-10-10 | Merged the project handoff into this file; one build order (docs only) |
| 30 | 2026-10-10 | Training dummy: stationary enemy, idle reset, per-player DPS readout (branch `training-dummy`) |
| 31 | 2026-10-10 | Merged `training-dummy` and the loot branch; smoke tests run with PowerShell 7 on Linux; fixed the loot `--tune` quoting (it parsed as `{}`, so no drops) and made Tuning log unparseable overrides |
| 32 | 2026-10-10 | The Assassin: Dual Talons (backstabs, Feint/Primed, Talon Storm), Throwing Knives (knife projectile, poison, Marked, Festering Wounds, Endless Flurry), Wings Ashstep and Plumage Flash, models, items. 460 tests; smoke (Fighter, -Party, Juggernaut, Assassin, Assassin -Party) passes on Linux/PowerShell 7 with 0 corrections (the -Party "party of 2" line is the known Linux quit race) |

---

## 7. Costs

| Stage | Cost |
|---|---|
| Building Steps A–G locally | $0 beyond Claude Pro ($20/mo) |
| Playing with friends | $0: host on the developer's PC, connect over Tailscale's free plan or a forwarded port |
| Always-on playtest server | Hetzner CX23, €5.49/mo, billed hourly; delete after a playtest |
| Live, 50 players at once | about $70–90/mo: Hetzner CCX13 (€42.99) + DigitalOcean managed Postgres ($15.15) + backups |
| Steam release | $100 one time, refunded after $1,000 in revenue |

Prices as of October 2026; Hetzner raised prices twice in 2026, so check before
ordering (OVH's Rise-1 at ~$64/mo is the alternative, with game-focused DDoS
protection). Bandwidth is an estimate: about 10–30 KB/s per player with interest
management. Paid anti-cheat can be skipped because the server decides every hit and
loot roll. Hold off paying for anything until the game is fun to play with friends.

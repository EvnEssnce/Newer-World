# Progress and plan

The one planning document: what we're building, where it stands, **the build order**,
and what's outstanding. `CLAUDE.md` describes the architecture; `design/classes.md`
holds the class design and per-class implementation notes; `HOSTING.md` is how to
host a playtest with friends. Read this file and `CLAUDE.md` at the start of every
session.

**At the end of every session:** add a one-line entry to the session log (what was
done, tests/smoke results, what needs a playtest), update the build order, and update
the outstanding lists. Keep it short; details belong in commits and `CLAUDE.md`.

---

## 1. The brief

**Newer World** (working title) is a small online action RPG with combat, gathering,
crafting, loot and movement modeled on New World: Aeternum, with low-poly graphics. The
target is 10–50 players per server instance with persistent characters. It is
deliberately not a true MMO: no territory wars, no server-wide trading post economy, no
housing, no large-scale open-world events. PvE is the main focus; PvP is minor.

### Decisions that stand

- **Engine:** Godot 4.7, GDScript. Client and headless dedicated server from one project.
- **Networking:** server-authoritative. The server decides hits, loot, inventory and
  crafting; clients predict only their own movement.
- **Persistence:** SQLite in development behind one persistence module, Postgres before
  launch. Nothing else touches the database.
- **Art:** CC0 placeholder packs (Kenney, Quaternius) and Mixamo animations. Paid art
  waits until the game is fun with ugly art.
- **IP:** mechanics can be borrowed; names, art, UI layouts and item names are original.
- **Budget:** the developer's Claude Pro subscription. No paid services until an
  always-on server is needed (§7).
- **Classes** (fixed per character, no shared weapons) own their weapons and **Wing**
  abilities, fuelled by **Ember**; Mages spend Ember instead of mana. **Rebirth** is
  automatic (5 s, back at 30% health, 50 Ember, 5 min cooldown). Respecs are free.
- **No attributes** (STR/DEX/...): builds come from mastery trees and gear; gear stats
  change combat numbers directly. Phoenix-themed attributes may come later.
- **Gear score follows New World's curves**: main stats ×1.0112 per 5 GS (slower above
  500), armor mitigation = armor / (armor + attacker GS^1.2). Equip slots: Weapon 1,
  Weapon 2, Head, Chest, Legs, Wing Enhancement; weapons and Wing Enhancements are
  class-locked.
- **Tests** use a small in-repo runner (`tests/framework/`), not GUT.

### Systems in scope

| System | What it means | Status |
|---|---|---|
| Combat | Light/heavy, block, dodge with i-frames, stamina, hitboxes, animation canceling | Built |
| Weapons | Two equipped, swap key, abilities on cooldowns, mastery trees | Built (15 weapons) |
| Classes & Wings | Class-locked weapons, Wing abilities, Ember, Rebirth | All six classes built (stealth is visual only) |
| Loot | Loot tables, rarity tiers, rolled stats, gear score ranges | Built |
| Inventory | Equipment slots, item weight, durability | Slots and resource stacks built; durability skipped, weight later (session 45) |
| Networking | Prediction, snapshots, lag compensation, server tuning on connect | Built; not yet tested over the internet |
| Gathering | Ore, wood, fiber, hide nodes; tool requirements; respawn timers | Built (Milestone 3): ore, wood and fiber nodes with charges and respawn timers; no tool items; hide waits for animals |
| Crafting | Tradeskill XP curves, refining chains, recipes, stations | Built (Milestone 3): 8 tradeskills, one refining step per resource, the Forge, 21 gear recipes |
| Persistence | Accounts, character saves | Built: database module (session 49), accounts and character select (50), saving (51) |
| Progression | Character level, weapon mastery levels (1 point per level, cap 20) | Built on branch `progression` (sessions 54, 57, 58): levels (character cap 30) and saving, XP from kills and gathering, mastery XP per weapon, an XP bar, tree points from levels; needs a hand playtest |
| Zone | Mob camps, node spawns, a town with crafting stations | Test map only |

---

## 2. Where we are

| Milestone (original build order) | Status |
|---|---|
| 1. Networked combat slice | **Done** (session 9) |
| 2. Loot loop | **Done** (sessions 10–41; playtested) |
| 3. Gathering and crafting | **Done** (sessions 45–48: built, playtested, two rounds of feedback; on main since session 52) |
| 4. Second weapon and weapon swap | **Done**, and far past it: six classes, 15 weapons, Wings, statuses, forced movement, projectiles, zones, parties, enemy threat (sessions 11–37) |
| 5. Persistence | **Done** (session 49: the database module; 50: accounts and character select; 51: saving; hand checked and on main since session 52) |
| 6. One zone, then playtest with real people | Internet readiness built (session 43); Husk navmesh done (session 42); the rest is items 1, 5 and 6 |

All six classes are built and have had a hand playtest; four rounds of playtest feedback
(sessions 26, 41, 41, 42) are built and approved. Gathering, tradeskills, refining and
crafted gear (Milestone 3), accounts with saved characters (Milestone 5) and
progression (levels, mastery, points from levels; awaiting its hand playtest) are on main.
846 unit tests; the smoke tests pass for every class with 0 prediction corrections.

---

## 3. Build order

Rule from the brief: **don't start an item until the one before it works** (built,
tested and playtested). Each sub-item is roughly one session with one testable goal.
(Session log entries before session 44 use the old step letters A–G.)

1. **Playtest with real people** (developer first, then one session of fixes).
   - **Developer's setup** (`HOSTING.md`): install Tailscale, share the PC with a
     friend. Export templates are installed and `tools\export_client.ps1` works
     (session 55).
   - **First playtest done (session 56):** one friend over Tailscale at ~104 ms ping;
     not laggy or rough, performed very well. Their correction count wasn't checked.
   - **Next playtest: 2–3 friends.** Ask each to read "Prediction corrections" in the
     HUD's debug lines (next to Ping) before quitting; check the rest of the session 43
     list (§4).
   - **Fix session** for what it finds. Candidate already known: projectile lag
     compensation if leading shots feels bad. (The build check is done, session 61:
     a friend on another build is refused with a message naming both versions;
     re-send the zip after code changes.)
2. **Done: Milestone 3, gathering and crafting** (sessions 45–48; on main since
   session 52). Brief: two or three node types, one refining step, one crafting station,
   tradeskill XP. Decided (§4): F gathers, no durability, no item weight yet, no tool
   items.
   1. **Done (session 45).** **Resources and nodes:** Rustvein Ore, Pine Log and Thistle
      Fiber in stacks of 100; 9 nodes on the test map with charges and respawn timers;
      F = interact; a gather is a walk-only lock (the equip lock); `data/gathering.cfg`.
      Hide waits for animals.
   2. **Done (session 45).** **Tradeskills:** 8 skills, cap 100, XP = 100 × level^1.5;
      each gathering level is −0.4% gather time and +0.5% bonus chance; P panel;
      `data/tradeskills.cfg`.
   3. **Done (session 46).** **Refining and a station:** Rustvein Ingot, Pine Plank,
      Thistle Linen (3 raw → 1, fiber 4 → 1; 2 s; 30 XP); the Forge; crafting panel with
      1/5/Max; the server checks materials, range and skill; `data/recipes.cfg`,
      `data/stations.cfg`.
   4. **Done (session 46).** **Crafted gear** through `LootRoller`: 21 recipes (every
      class weapon at Weaponforging 1/4/8, Padded armor at Armorcraft 1/3/6); GS 100–110
      at level 1 to 130–140 at 100; Rare/Epic odds grow with level; no Legendaries.
      Wing Enhancement recipes and durability/repairs deferred.
   5. **Done (sessions 47–48).** **Playtest and feedback:** gathering feel and speed and
      the P panel approved. Built from the feedback: "+25 Mining XP" feed lines, a
      progress bar in the Forge panel, crafting only while the panel is open (moving
      closes it; a cancelled batch keeps its finished pieces), one Forge at (-7, 0, 17)
      away from the Husks (the bot walks to it), crafted gear marked, and an icon per
      item.
3. **Done: Milestone 5, persistence** (sessions 49–51; hand checked, on main since
   session 52).
   1. **Done (session 49, branch `persistence` off `milestone-3`).** **Persistence module:**
      godot-sqlite v4.9 (built for 4.7.1; runs on 4.7.2) in `addons/godot-sqlite`
      (Windows + Linux binaries); `Persistence` (`game/persistence/`): schema v1
      (accounts, characters with JSON columns), migrations by `user_version`, account and
      character create/find/list/load/save/delete, saving everyone in one transaction;
      `CharacterSave` captures and rebuilds `CharacterBuild` (through the mastery rules),
      `Inventory` (stacks, uids), `Equipment` and tradeskills. Nothing calls it yet.
   2. **Done (session 50, agent; hand checked).** **Accounts and character select:**
      (`game/accounts/`: PBKDF2-SHA256 hashes on a worker thread, 310,000 iterations;
      name/password rules in `data/accounts.cfg`; `AccountService` at `/root/Main/Accounts`;
      login, character list and create screens with a class picker; the server spawns the
      chosen character's class; `--db=`; bots log in by themselves) name + password hash
      login, create a character (class picker instead of `--class`), choose it on connect.
   3. **Done (session 51, agent; hand checked).** **Saving:** (`World/Saves`,
      `SaveSchedule`, `data/saving.cfg`: everyone every 60 s, a character 3 s after its
      first unsaved change, on disconnect and at shutdown; an equip or craft under way
      isn't saved: the save is the state before it) on change and periodically; load on
      join; survive a server restart (the smoke test restarts the server on the same
      database file and checks the first bot comes back exactly as saved).
4. **Progression:** character level and XP (kills, gathering), Wing tree points from
   level, weapon mastery XP per weapon (1 point per level, cap 20, as in
   `design/classes.md`). Pure logic + tests; saved through the persistence module.
   1. **Done (session 54, branch `progression`).** **Levels and saving:**
      `ProgressionDefs` + `Progression` (`game/progression/`, `data/progression.cfg`):
      character level (cap 20, XP 400 × L^1.5) and a mastery level per weapon type (cap
      20, XP 200 × L^1.5), 1 Wing point per character level and 1 tree point per mastery
      level after the first; saved with the character (schema 2: a `progression`
      column; old databases migrate on open); `World/Progression` holds them on the
      server. Nothing grants XP and the trees still get full points.
   2. **Done (session 57, branch `progression`).** **XP sources:** a kill gives every
      contributor the enemy's `[progression] kill_xp` (Husk 50) and `mastery_xp` (40)
      split over the weapons that dealt their damage (`Enemy.damaged_by` now holds
      damage per weapon; Wing abilities count for none); each gather gives 15
      (`[sources] gather_xp`). The owner gets its progression, "+50 XP  +40 Spear"
      feed lines and level-up lines; an XP bar along the bottom edge with "Level N
      X / Y XP" left of the health bar. Smoke checks XP, a level-up and Keeper's saved
      level surviving the restart (with 20x cheaper curves).
   3. **Done (session 57, branch `progression`).** **Points from levels:** a weapon tree
      gets 3 points at mastery level 1 + 1 per level (full 19 at 17), the Wing tree 2 +
      1 per character level (full 12 at 11). A build over that is cut when the
      character joins (`MasteryTree.fit`: slotted abilities kept first; logged);
      level-ups raise the limits at once. K shows "Points: 3 / 3 (of 19)", greys out
      what doesn't fit, and Default sends as much of the default as fits.
      `data/testing.cfg [progression] full_points` (off; the smoke test turns it on).
      (Session 58 tried one shared pool from the character level instead; reverted the
      same day: per-weapon mastery points were intended.)
   4. **Hand playtest** of 4.2–4.3 and session 60 (§4). `progression` was
      fast-forwarded into main in session 61, before this playtest.
5. **Content for a zone (Milestone 6).**
   1. **More enemies and camps:** 2–3 new enemy kinds with their own loot tables and
      gear score ranges (everything drops GS 101–140 today), placed as camps.
   2. **The zone:** a small map from CC0 packs: mob camps, gathering node spawns, a
      town with crafting stations, spawn points.
6. **Art pass basics:** a CC0 character with Mixamo idle/run/roll/attack animations in
   place of the capsule (the developer downloads the packs; Mixamo needs an Adobe
   login). Then the Milestone 6 playtest with real people.

**When needed (not in the order): network headroom.** Before a session with more than
~6 players together: **interest management** (only nearby players/enemies in each
snapshot; clients must hide rather than treat a missing id as "left"; party frames need
members' health from elsewhere), then maybe a string table for weapon ids / Wing set
(~28 bytes per other player) or delta compression. Today ~7 players in view fit one
packet (§4, Known issues).

**Later / unscheduled**
- Stamina gear stats (Ferocity, Rage): make max stamina and stamina regen synced
  `PlayerState` values, then switch the affixes back on (`slots` in `affixes.cfg`).
- Light attack combo chain (New World-style 3-hit string)?
- Salvage, item levels beyond GS 140, perks with effects (not just stats).
- A "Dedicated Server" export preset (`main.gd` already treats the feature tag like
  `--server`), for hosting on a rented machine (§7).

**Done so far** (details in the session log and git): Milestones 1, 2 and 4; the
Fighter (sessions 12–24), Juggernaut (25), Assassin (32), Ranger (33), zones and summons
(34), Mage (35), Paladin (36) and their leftovers (37); snapshot compression (38); the
in-game class picker (40); four rounds of playtest feedback (sessions 26–42: panels,
HUD, crosshair aiming, aimed zones and beams, teleports, knife ammo, animation
canceling, tree prerequisites, Juggernaut hyper armor, Shield Wall redesign, the
training dummy); Husk navmesh pathing (42); internet readiness and hosting setup (43);
Milestone 3, gathering and crafting (45–48); Milestone 5, persistence (49–51).

---

## 4. Outstanding work

### Needs a hand playtest

**Session 43, with friends over Tailscale (build order item 1):** first run (session
56, one friend, ~104 ms): the export ran and connected, and play felt smooth, not laggy.
Still to check at the 2–3 friend playtest: the HUD's correction count stays low for
each friend; hits land on what you see at their ping (compare with
`[lag_compensation] enabled=false` in `data/network.cfg`); no visible jerks after
corrections; a tuning edit on your side reaches them after a server restart; names on
party frames (session 53; nameplates showed names in the session 56 playtest).

**Progression (sessions 57–58, branch `progression`):** a new character's K panel shows
"Points: 3 / 3 (of 19)" and its Wings 3 / 3 (of 22); Husk kills give "+50 XP  +40 <weapon>" feed
lines and fill the XP bar at the bottom edge; a level-up line, then one more point in K;
leave and rejoin keeps the level. Whether 8 Husks per level and the start points feel
right. Turn `data/testing.cfg [progression] full_points` on to compare. Also: the keybinds list
(bottom left, F1 hides it); deleting a character (two clicks); a blocked name refused.
**Session 60:** the K Wings tab's class bonus line (turn on `full_points` and play a
level 21+ character, or trust the feed line); Mending Beam healing you while it heals an
ally, Renewal Pulse healing you from outside; Sapping Pulse, then a light or heavy on a
sapped Husk: a bigger number and a green heal (the smoke bots never followed up in
time, so this path is untested).

**Never reported in a playtest** (spot-check when convenient; most need `-NoBot` or a
capstone learned in K): the War Hammer's Breaker capstone breaking a real guard;
Headsman's Verdict crits; Maelstrom's 7 m Vortex; Tempest Wings' wall stun (Gale Burst
next to a crate); Pyre Heart drawing a Husk's aggro; Second Wind and Second Step (two
rolls / Ashsteps); Ricochet; Seeker Spark (watch for kinks from course corrections);
Tripwire and Smoke Bolt; Kindle Life; Mirror Aegis reflecting projectiles.

### Decisions to confirm (defaults that were built)

Say "keep" or what to change.

- **Loot and gear:** F takes every drop in reach at once (no loot window), not while
  defeated; a discarded item is deleted. Damage over time earns a loot roll; a Husk that
  walks home and heals forgets who hit it. Armor grows on the weapon gear score curve;
  affixes grow linearly. Armor doesn't reduce damage over time. While equipping you walk
  at full speed, a stagger doesn't interrupt it, and raising max health doesn't heal.
- **Assassin:** Feint reads blocks, guard breaks and dodges (players) or a Husk
  mid-swing; Primed lasts 4 s and is used even by a blocked hit. Marked's bonus needs a
  melee hit; Venom Coat's poison rides on Talon hits too. Festering Wounds cuts healing
  on players only; Endless Flurry's free fan uses no cooldown. Dazzled = −25% damage
  dealt + `blind` 0.6 (60% white haze on players, 60% misses for Husks) + a Slow.
- **Ranger:** no charged-shot mechanic (the Longbow heavy is the full draw); no crossbow
  magazine (the light bolt's long recovery is the reload); Loaded Chamber = 2 s since
  your previous shot. Overheat has no lockout; Quick Reload's slow rides on any weapon's
  next hit. Ignite uses up the stacks even if the hit is blocked. Running Shot covers the
  Longbow's lights and heavies only.
- **Zones:** zone damage works like damage over time (no block, crit, armor or backstab).
  Mirror Image became a burst as the decoy ends (decoys can't be hit). Late joiners
  don't see zones placed before they joined.
- **Mage:** Clear Mind = an ability within 3 s of landing a heavy refunds its Ember (no
  charge meter); Wildfire Spread = your Burn zones grow 15% per pulse up to 2×. Mending
  Beam doesn't heal you; Ward shields you too. Ward absorbs hits only (not damage over
  time or zones), and a fully absorbed hit still staggers. Silence does nothing to Husks.
- **Paladin:** Rush to Aid and Guardian's Leap go straight ahead (no ally targeting);
  Guardian Wing links allies in a 12 m line. Spinning Staves and Staff Spin deflect
  projectiles from any direction. Phoenix Blessing's extra Rebirth is taken back after
  30 s if unused; Kindle Life raises at 30% health without using their Rebirth.
  Guardian Link moves 30% of hit damage (not damage over time or zones).
- **Charges and knives:** a spare charge lets you reuse something while its cooldown
  runs (a Wing spare doesn't restart it). Embedded knives have no visual.

- **Progression (sessions 54, 57, 58):** character level cap **30** (session 58; weapon
  mastery cap 20); XP curves 400 × L^1.5 (character, ~756,000 XP to 30: about 15,000
  Husks, so later enemies must give more) and 200 × L^1.5 (each weapon, ~135,000 to 20).
  A new character starts with **3 points per weapon tree and 3 Wing points**, then 1 a
  mastery level (that weapon's tree) and 1 a character level (Wings): at level 1 each
  weapon keeps at least one of its default abilities, usually two, and Wing abilities
  stay slotted. **The Wing tree costs 22 (every branch 11; session 60: capstones 4,
  tier-3 passives 3) and its budget is the whole tree, full at level 20.** Levels 21–30
  give a **class bonus** point each instead (10 at 30): Juggernaut +20 max health,
  Fighter +1% damage, Assassin +1% movement speed, Ranger −2% dodge stamina, Mage −2%
  Ember cost, Paladin +2% healing per point. A weapon tree is full at mastery 17. Husk: 50 character XP and
  40 mastery XP per kill (8 kills to level 2), 15 XP per gather; the training dummy
  gives none. Every contributor gets the whole kill XP (like loot); mastery XP is split
  by damage per weapon, and damage over time and projectiles count for the weapon out
  when they land. Only kills give mastery XP (not damage to players or the dummy). A
  build over its points is cut automatically on join (no message beyond the K panel);
  existing characters come back cut to their levels' points. Unknown weapon ids in a
  save are kept (a renamed weapon starts over).
- **Mage (session 60):** Mending Beam heals you 75% of each pulse (beam on an ally or not)
  and Renewal Pulse 75% when you're outside it; Ward (a shield) unchanged. **Sapping
  Pulse** replaces Life Spore (Siphon tier 2): 4 m pulse, 50 damage, Sapped 6 s; your
  next light or heavy on a sapped target (projectiles too, not abilities) deals +40%
  and heals you half of that hit. Lifeweaver now heals, Siphon damages and drains.
- **Names (session 58):** a blocked-word list (`data/name_filter.cfg`) for account and
  character names: words refused anywhere, short ones only as the whole name, and an
  allowed list ("Peacock", "Dickens", "Annalise"). A refused name says only "That name
  isn't allowed." Deleting a character takes two clicks on Delete and can't be undone.

**Decided for Milestone 3 (session 45):**
- **Gathering key: F**, the same as loot pickup (one interact key; the prompt says
  which it will do).
- **Durability: skipped** for now (can come later as its own step if the economy
  needs a material sink).
- **Item weight: later**, once a town with storage exists (item 5), not in Milestone 3.
- **No tool items:** everyone can gather every node type; tradeskill level decides
  speed and yield (and later which tiers you can gather).

### Known issues

Gameplay:
- A heavy's hitbox can hit both Husks at once when they stand together. Attacks pass
  through crates (hitboxes ignore world geometry).
- No projectile impact effect; rarely a thrower sees its own throw twice.
- Statuses only tick while a player's inputs arrive (keeps prediction exact; a lagging
  player's bleed pauses). Bloodlust survives a weapon swap.
- Blocked hits never push; bodies pass through each other when knocked back.
- Crashing Leap's height is cosmetic (can't reach ledges). F3 draws Vortex at its base
  3.5 m even with Maelstrom. Hold the Line has no poke animation.
- Newly equipped weapons start with cooldowns at 0.
- The greataxe model is mostly hidden behind the body from the follow camera.
- A drop scattered next to a crate can land inside it (still picked up from beside it).
- Holding Space keeps jumping (jump is sent as "held").
- Gathering: nodes don't collide with anything.
- Saving (session 51): a killed server (Ctrl+C, a crash) loses up to `[save] interval`
  (60 s); closing it normally or `--quit-after` saves everyone. Leaving mid-craft loses
  that batch's finished pieces (inputs kept). Health, Ember, cooldowns, position and
  ground drops aren't saved. After the in-game class change (test tool) the other
  class's build is saved but refused on the next join (the stored class didn't change).
- Accounts (session 50): no login attempt limit and no timeout for a connection that never
  logs in; the in-game class change (test tool) doesn't change the stored class; no
  character delete or rename on the start screens.
- Hostile players in PvP walk through Shield Wall (players share one collision mask).

Networking:
- Snapshots fit one packet up to about 7 players in view (6 bots: max ~1,130 of 1,360
  bytes); more needs interest management ("network headroom" above).
- Lag compensation covers melee, beams and ally support only: projectiles, zones, shock
  rings and the beam's aim raycast use current positions. It favours the attacker: at
  high ping a target can be hit just after reaching cover (capped at `max_rewind`
  0.35 s). Untested with real latency (localhost rewinds ~8 ticks).
- The code version check (session 61) can't tell an old exe (from before it) apart
  from a silent connection: those get "Disconnected from server." after 10 s
  (`[server] version_timeout`), not the message. Exports from now on get the message.
- Hit events arrive before the attacker's swing is drawn on other clients.
- About 1 smoke run in 15–20 shows a few (≤4) small unexpected corrections, mostly at
  seq 7–8 right after spawning (server y 0.0008 on the floor, predicted 0.0; identical
  `PlayerState`, so it's in the physics step). The smoke test tolerates ≤5; `--verbose`
  logs them.
- When 9 bots quit at once the server had one ~100 ms tick (disconnect handling).

Testing:
- The smoke test's former luck checks (guard hit, player/enemy knockback, death +
  respawn, bleed tick, gather) are now scheduled by the bot (session 53): a failure there
  is real. Untested on Linux and with `-Bots 6` (duel pairs come from each bot's nearest
  player and may not match up). "An enemy was moved by force" can be met by the
  training-dummy push, not only a Husk.
- Linux only: two bots quitting at the same instant sometimes print `party_members=0`;
  `-Bots 6` on 4 cores needs the server to quit later (seconds + 8) or late clients miss
  their summaries.

Housekeeping:
- Placeholder swing/flash/damage-number constants live in `player.gd` (to be replaced
  by animation and VFX).
- This repo has a local git `user.name`/`user.email` (no global identity configured).

---

## 5. How to work in this repo

- One testable goal per session ("dodge roll with i-frames, tunable from one config
  file", not "work on combat"). The developer is on Claude Pro: keep sessions focused,
  don't re-explore the codebase (read `CLAUDE.md` and this file instead).
- Every tuning value goes in `data/*.cfg` with a comment (what it does, units); the
  developer tunes feel by editing those files.
- Tests for anything that isn't feel; feel is playtested by hand. Run the unit tests and
  both smoke tests before committing (`CLAUDE.md` "Running"; Linux cloud sessions have
  their own notes there).
- Git from the first commit, private GitHub repo (`EvnEssnce/Newer-World`).

---

## 6. Session log

Full entries: sessions 1–28 in `git show 5cc5148:PROGRESS.md`, 29–43 in
`git show 0b998f0:PROGRESS.md`.

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
| 11 | 2026-10-07 | Parties and the ally rule |
| 12 | 2026-10-07 | Abilities, weapon swap, mastery trees, the Fighter; **Milestone 4 done** |
| 13 | 2026-10-08 | Fixes; startup lag (ENet throttle off); `--perf-log` |
| 14 | 2026-10-08 | Status effects |
| 15 | 2026-10-08 | Forced movement, Rising Cut, the Spear |
| 16 | 2026-10-08 | Dodge cooldown, Shield Charge groups, Vault |
| 17 | 2026-10-08 | Shield Charge impact radius; Vault facing |
| 18 | 2026-10-08 | Ember, Wings and Rebirth |
| 19 | 2026-10-08 | Feather projectiles |
| 20 | 2026-10-08 | Wave 2 feedback (plan) |
| 21 | 2026-10-08 | Broadsword stab, Boomerang Axe visuals |
| 22 | 2026-10-08 | Crashing Leap aimed by pitch; Diving Strike shape |
| 23 | 2026-10-09 | Spear Skewer and Perforate |
| 24 | 2026-10-09 | Finishing Thrust, Hold the Line, Rampage, Shield Wall; enemy threat |
| 25 | 2026-10-09 | The Juggernaut: Halberd, Greataxe, War Hammer, Wings, crits |
| 26 | 2026-10-09 | Wave 3 playtest feedback (plan) |
| 27 | 2026-10-09 | Loot drops, F pickup, I inventory |
| 28 | 2026-10-10 | Equipping gear: 6 slots, gear score, armor, equip time |
| 29 | 2026-10-10 | One planning file (docs only) |
| 30 | 2026-10-10 | Training dummy with DPS readout |
| 31 | 2026-10-10 | Merges; smoke tests on Linux with PowerShell 7; `--tune` quoting fix |
| 32 | 2026-10-10 | The Assassin |
| 33 | 2026-10-10 | The Ranger; `blind` |
| 34 | 2026-10-10 | Zones and summons; Shield Wall redesign; Ranger and Assassin zone abilities |
| 35 | 2026-10-10 | The Mage; Ember-cost weapon abilities |
| 36 | 2026-10-10 | The Paladin; class track complete |
| 37 | 2026-10-10 | Charges, Updraft hover, Ricochet, Seeker Spark, embedded knives and Recall |
| 38 | 2026-10-11 | `NetCodec` snapshots (~1.4 KB → ~0.5 KB for 2 players), `view_array()` |
| 39 | 2026-10-11 | Everything merged into main; 517 tests |
| 40 | 2026-10-11 | In-game class picker (test tool) |
| 41 | 2026-10-13 | Back on Windows; loot/gear/class playtests; feedback rounds A2 and A3 (panels, HUD, crosshair aiming, aimed zones, teleports, beams, knife ammo, Recall, tree prerequisites, Earthshaker ring, animation canceling); hidden-console tool scripts; 620 tests |
| 42 | 2026-10-14 | Playtest approved A3; round A4 (melee facing to the crosshair, hold-to-aim, projectile glow, channel dodge, hyper armor, Husk navmesh), bots aim with the crosshair, beams aim like projectiles; approved; 682 tests |
| 43 | 2026-10-14 | Internet readiness: server tuning on connect, lag compensation, correction smoothing; `HOSTING.md`, host and export scripts (export untested); 698 tests; smoke default, `-Party`, Mage pass, 0 corrections |
| 44 | 2026-10-14 | Docs: one build order here; class implementation notes moved from `CLAUDE.md` to `design/classes.md`; old `PLAYTEST.md` (Wave 3 checklist) removed |
| 45 | 2026-10-14 | Milestone 3 started on branch `milestone-3` (decided: F gathers, no durability, item weight later, no tool items). Two agents: 2.1 stackable resources + gathering nodes (`game/gathering/`, `data/gathering.cfg`, equip lock reused), 2.2 tradeskills (`game/tradeskills/`, `data/tradeskills.cfg`, P panel); merged (5 keep-both conflicts in `world.gd`), gathering wired to tradeskill XP/speed/bonus; smoke checks gathering and XP. 732 tests; smoke default, `-Party`, Juggernaut, Ranger, Mage pass, 0–1 corrections |
| 46 | 2026-10-15 | Milestone 3 session 2.3 by an agent: refining recipes (`data/recipes.cfg`, `data/stations.cfg`, `game/crafting/`), the Forge (two markers so the smoke bot reaches one), crafting panel, refining XP; smoke checks a craft. Merged clean into `milestone-3`; 747 tests; smoke default ×2, `-Party`, Mage pass. Then session 2.4 (crafted gear: 21 recipes, GS and rarity by Weaponforging/Armorcraft level, no Legendaries) merged clean: 757 tests; smoke default, `-Party`, Assassin, Ranger, Mage pass first time; Juggernaut and Paladin passed on rerun (known force and status luck checks, and one missed craft). Milestone 3 built on `milestone-3`, needs its playtest |
| 47 | 2026-10-15 | Milestone 3 playtest: gathering and the P panel approved. Feedback built by two agents and merged clean on `milestone-3`: XP feed lines, a progress bar in the Forge panel, crafting only with the panel open (moving cancels), one safe Forge at (-7, 0, 17) with the bot walking to it, crafted gear marked, and an icon per item (`ui/item_icon.gd`, `icon`/`ranged` keys). 768 tests; smoke all classes and `-Party` pass (default and Paladin on rerun: force and bleed luck checks) |
| 48 | 2026-10-15 | Milestone 3 feedback 2 (main session): any move/jump/dodge closes the Forge panel (after you've stood still with it open), and an interrupted batch keeps its finished pieces ("(1 of 4 made)"; `CraftingSystem._make` shared by finish and cancel). 770 tests; smoke default, `-Party`, Ranger pass (the Ranger run made 1 of 4, 1 of 3, 1 of 2 after hits) |
| 49 | 2026-10-15 | Persistence 3.1 on branch `persistence` (off `milestone-3`, so saves cover resources, tradeskills and crafted gear): godot-sqlite v4.9 added (Windows/Linux binaries), `Persistence` + `CharacterSave` (`game/persistence/`), `Inventory.to_dict/from_dict`, `CharacterBuild.apply_saved`. 785 tests (14 new, on temporary SQLite files); smoke default and `-Party` pass, 0 corrections. Nothing to playtest yet |
| 50 | 2026-10-15 | Persistence 3.2 by an agent on `persistence`: accounts and character select. `PasswordHash` (PBKDF2-HMAC-SHA256 over Godot's HMAC, RFC vectors in tests, salt + iterations in the stored string), `AccountRules` (`data/accounts.cfg`), `AccountService` (`/root/Main/Accounts`: login/create/play RPCs, hashes on worker threads, one login per account), start screens (address → login → characters → create with a class picker; `--menu-preview` for screenshots), `World._client_ready()` spawns the chosen character's class, `--db=` (smoke and screenshot servers use `:memory:`), bots log in alone (`--account=`/`--character=`). 801 tests; smoke default and `-Party` pass first time (new accounts check), 0 corrections. Needs a hand check of the login screens (§4) |
| 51 | 2026-10-15 | Persistence 3.3 by an agent on `persistence`: saving. `World/Saves` (`SaveService`) loads the chosen character on join through the normal rules (build, bag, gear back to the bag if unwearable, tradeskills; unknown items dropped and logged) and saves through `Persistence.save_characters`: every 60 s, 3 s after a character's first unsaved change (`SaveSchedule`, `data/saving.cfg`; `save_changed` signals from Builds/Loot/Tradeskills), on disconnect (new `Net.peer_leaving`) and at shutdown. Equips/crafts under way aren't saved (the state before them). Smoke test: a database file, `SUMMARY saves` check, then a restart phase (second server on the same file, Keeper logs in again: same `CharacterSave.fingerprint`, saved at that server's shutdown). 809 tests; smoke default ×2 pass, `-Party` passed on the third run (known luck checks: `party_members=0` quit timing, then "no Husk moved by force"), 0 corrections. Needs the saving hand check (§4) |
| 52 | 2026-10-16 | Main fast-forwarded to `milestone-3`, then (after the developer's hand checks of the login screens and saving passed) to `persistence`; both pushed. Docs: Milestones 3 and 5 marked done here |
| 53 | 2026-10-16 | Two parallel agent sessions, merged clean into main. **Character names:** a server-sent peer → name table (`PlayerNames` in `AccountService`, reliable RPCs on play/leave, never in snapshots) for nameplates, party frames and party notices, "Player N" until a name arrives; `Net.is_peer_connected` shared with PartySystem. **Deterministic smoke checks** (bot-only, the game unchanged): a duel 3 s after launch (guard break, knockback, a Rebirth and a respawn), a training-dummy push after the first craft, a first gather on joining, staggered Forge trips, guard down against Husks until knocked back and a bleed has ticked, heavies wait for reach; branch runs default ×5, `-Party` ×2, Juggernaut, Paladin all passed first time. On merged main: 815 tests; smoke default and `-Party` pass first time, 0 corrections. Nameplates/party frames with friends: check in the playtest |
| 54 | 2026-10-16 | Progression 4.1 on branch `progression`: `ProgressionDefs`/`Progression` (`game/progression/`, `data/progression.cfg`: character level and per-weapon mastery, caps 20, XP curves, tree points per level), saved with the character (`CharacterSave.progression`, migration 2 adds the `progression` column), `World/Progression` holds them on the server; no XP granted yet. 827 tests (12 new: curves, level-ups, caps, points, clamped saves, a schema-1 database migrating); smoke default and `-Party` pass first time, 0 corrections. Nothing to playtest yet |
| 55 | 2026-10-16 | Export: templates installed by the developer; `export_client.ps1` now also zips the godot-sqlite DLL (exported beside the exe, left out of the zip before). The exported exe ran as a headless server (database opened, port listening). `build\export\NewerWorld.zip` made for friends |
| 56 | 2026-10-16 | First playtest with a friend over Tailscale (~104 ms ping): no lag or roughness, performed very well; character names showed on nameplates. Corrections on their side not checked; next playtest with 2–3 friends |
| 57 | 2026-10-16 | Progression 4.2 and 4.3 on branch `progression`. **XP:** kills (`[progression] kill_xp`/`mastery_xp` in enemy files; `Enemy.damaged_by` holds damage per weapon, `Progression.mastery_split`) and gathers give XP through `ProgressionSystem.grant` (owner RPCs, feed lines, `save_changed`, `points_changed`); `Hud.setup_progression` draws the XP bar. **Points:** `MasteryTree` validate/can_add/prune take a points limit, `fit` cuts an allocation to it; `CharacterBuild.set_point_limits` (limits go to the owner with the build, not into saves); `BuildService.set_points` on join, class change and level-up; K panel shows the limit; `testing.cfg [progression] full_points`. 835 tests (8 new, one over every real class: abilities kept at level 1); smoke default and `-Party` pass first time (Keeper saved at level 3 and 4 and came back the same); one party run had 1 correction on one client, and a screenshot run had 1 (a rerun had 0). Checked the XP bar and K panel in screenshots |
| 58 | 2026-10-18 | Feedback on 4.2–4.3, branch `progression`. **One point pool:** the character level (cap 30) gives 12 + 2.5 a level (`[points]`), shared by the Wing tree and every weapon tree (`CharacterBuild.set_point_pool`, `point_limit` = spent + left; `MasteryTree.fit_order`); mastery levels give none; every node cost and tier gate doubled, weapon tree budget 30, Wing 24, so level 30 fills Wings + 1.5 branches in two weapons (developer chose this over per-class rates). **HUD:** a 10 px XP bar; the controls line became a keybinds list bottom left (`KeybindsPanel`, keys from `InputActions`, F1 hides). **Characters:** Delete on the character list (two clicks; `_request_delete_character`, ownership checked). **Names:** `data/name_filter.cfg` + `AccountRules.blocked_name` (look-alikes, squeezed repeats, whole-only short words, an allowed list). 838 tests (pool sharing, level 1 and 30 on the real data, the filter); smoke default and `-Party` pass first time, 0 corrections; HUD, K panel and character list checked in screenshots |
| 59 | 2026-10-18 | Reverted session 58's point pool at the developer's request (per-weapon mastery points were intended, not a bug): session 57's point rules, node costs and tree budgets are back (files restored from 69ffc3f); the character level cap stays 30. Kept from session 58: the XP bar, the keybinds list, character delete, the name filter. 837 tests; smoke default and `-Party` pass first time, 0 corrections |
| 60 | 2026-10-18 | Wing trees cost 22 (all branches 11) with 3 Wing points at level 1, so they fill exactly at level 20; levels 21–30 give class bonus points (`[level_bonus]` in class files, `ClassDef.level_bonus`, `Player.set_level_bonus`; move speed, dodge and Ember cost as owner-only synced ints in `PlayerState`, header 12 → 15). Mage: Mending Beam `self_heal` 22.5, Renewal Pulse zone `owner_heal` 120, Sapping Pulse replaces Life Spore (status `sapped`: `mark_attacks="light_heavy"`, `mark_heal` 0.5; `_marked_scale` + `_heal_from_mark`; `SUMMARY mage mark_heals=`). 841 tests (level bonus, synced fields, real Wing trees at 20); smoke default, `-Party` and `-Class mage` pass, 0 corrections; mark heals didn't happen in two Mage runs (bots didn't follow up on a sapped Husk), so that path needs a hand check |
| 61 | 2026-10-25 | Main fast-forwarded to `progression` (sessions 54–60) at the developer's request, before the progression hand playtest. **Code version check:** `CodeVersion` (a hash of the code files, not data/; an export packs `code_version.txt`, written by `tools/write_code_version.gd` in `export_client.ps1`) and `VersionCheck` (`/root/Main/VersionCheck`, two RPCs that never change): a client says its version on connect, the server sends the tuning only on a match (and only then allows login), else refuses with a message naming both versions; a silent connection (a pre-check build) is dropped after `[server] version_timeout` 10 s. The connect page shows "Game version X". 846 tests (5 new); on Linux with PowerShell 7: smoke default passes (version checks: 2 accepted, the `--fake-version` client refused), `-Party` passes everything but the known Linux `party_members=0` quit timing (also on the unchanged code, 2 of 2 runs); a pre-check build against the new server was dropped after 10 s with no errors; the refusal screen checked in a screenshot. Hand check: export, change a script, host, and connect the old exe (message) |

---

## 7. Costs

| Stage | Cost |
|---|---|
| Building everything above locally | $0 beyond Claude Pro ($20/mo) |
| Playing with friends | $0: host on the developer's PC over Tailscale's free plan (`HOSTING.md`) |
| Always-on playtest server | Hetzner CX23, €5.49/mo, billed hourly; delete after a playtest |
| Live, 50 players at once | about $70–90/mo: Hetzner CCX13 (€42.99) + DigitalOcean managed Postgres ($15.15) + backups |
| Steam release | $100 one time, refunded after $1,000 in revenue |

Prices as of October 2026; Hetzner raised prices twice in 2026, so check before
ordering (OVH's Rise-1 at ~$64/mo is the alternative, with game-focused DDoS
protection). Bandwidth is an estimate: about 10–30 KB/s per player with interest
management. Paid anti-cheat can be skipped because the server decides every hit and
loot roll. Hold off paying for anything until the game is fun to play with friends.

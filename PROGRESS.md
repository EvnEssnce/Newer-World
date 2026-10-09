# Progress

## Current milestone

**2. Loot loop.** Enemy drops with rarity and rolled stats, inventory, equipping gear
that changes the player's numbers.

Milestone 1 (networked combat slice) is **done**: on 2026-10-07 the developer
playtested fighting Husks alongside the bot and called the combat loop great, with
Husks behaving as expected.

## Session log

### 2026-10-09 (23): Spear Skewer and Perforate (Wave 3, first part)

Session 22's work was playtested by the developer ("these all look great") and
pushed. Then Wave 3 started with the rest of the Spear's abilities (data only, plus a
visual):
- **Skewer** (`weapon_spear.cfg`, Lancer tier 2): a narrow 3 m thrust, 90 damage,
  roots for 1.5 s, 12 s cooldown. First ability to apply Root.
- **Perforate** (Impaler tier 2): 5 thrusts 0.13 s apart, 30 damage each, each its own
  hit window adding a stack of bleed (cap 5), 11 s cooldown.
- Both are in the Spear's default allocation (7 of 19 points), not its default slots.
  Bots slot them first (status abilities), so a bot's Spear now has Skewer, Perforate
  and Javelin Cast on Q/E/R.
- Perforate's look: the spear thrusts once per hit window
  (`Player._repeated_thrust_pose`). Skewer uses the normal heavy thrust.

Tests: 354 passed (no new logic: root, bleed and multi-window abilities already have
tests). Smoke: default and `-Party` passed, 0 corrections; the server logs showed
Skewer rooting a Husk and a player, and Perforate stacking bleed on a Husk.

**Needs a hand playtest:** Skewer's root on a Husk (it should stop moving but still
swing), Perforate's thrusts and bleed numbers, slot them in K.

**Next (Wave 3):**
- The Spear capstones are still placeholders (`effect="none"`): **Finishing Thrust**
  (more damage vs targets below 30% health) needs the *target's* health in the damage
  path (`_strike_player`, `strike_enemy`, projectiles): today `damage_scale` is worked
  out once per attacker, not per target. **Hold the Line** (auto-poke while blocking)
  is bigger.
- Dual Axes **Rampage** (attack speed buff above 50% stamina) and Broadsword **Shield
  Wall** (ALLY) are the Fighter's other unbuilt abilities.
- Enemy threat (for taunts), then the Juggernaut.

### 2026-10-08 (22): Crashing Leap aimed by pitch, Diving Strike shape (items 1 and 2)

Done (session 20's list is now complete):
- **Crashing Leap aimed by camera pitch** (`weapon_dual_axes.cfg`: `dash_aim_pitch`,
  `aim_full_pitch=0`, `aim_zero_pitch=35`, the camera's `max_pitch`). Level or looking
  down = 4 m; looking up shortens it linearly; at the camera's top pitch it goes
  straight up (0 m). Inputs now carry `aim_pitch` as a 5th element (server checks it's
  finite and clamps to ±90°; bots send 0). The fraction is the length of
  `ability_dir` at the start, so `to_array()` is unchanged. `PlayerState.step` and
  `PlayerMovement.step` take `aim_pitch` as an optional last argument.
- **Diving Strike shape** (`wings_fighter.cfg`): `dash_ease="in"` (speed ramps up,
  same 5 m; `AbilityParams.dash_speed_at`), `leap_peak=0.3` (rises steeply, long
  swoop down; `AbilityParams.leap_lift`, now used for every leap), and the hit window
  moved into the swoop: windup 0.55 → 0.35 s, active 0.12 → 0.25 s (from about 1.8 m
  in until just after landing). The Broadsword stab now plays during the swoop.
- New ability keys documented in `weapon_broadsword.cfg`'s key list.

Tests: 354 passed (new: pitch mapping, aimed dash distance and sync, eased dash
distance, leap curve). Smoke: default and `-Party` both passed, 0 corrections. (Running
the two in parallel in one checkout makes `-Party` fail: they share `build\smoke`.)

**Needs a hand playtest** (`run_local_test.ps1`) of session 20's four items:
- Crashing Leap: does looking up feel right for shortening it? (Tune
  `aim_full_pitch`/`aim_zero_pitch`.) Note the cosmetic leap height doesn't change.
- Diving Strike: rise and swoop, hits along the swoop (Husks), Broadsword stab.
- Boomerang Axe's right axe leaves the hand; Opening Strike's stab.

Next after the playtest: Wave 3 in `design/classes.md` (see session 19's **Next**).

### 2026-10-08 (21): Broadsword stab, Boomerang Axe visuals (items 4 and 3 below)

Done (client visuals only, `player.gd` and `ProjectileSystem._process`):
- **Broadsword stab:** `_sword_pose` now returns a `Vector3` like `_spear_pose` (z =
  meters pulled back, negative = forward) and moves `SwordPivot` along it. Opening
  Strike draws the level sword back 0.35 m and thrusts it 0.6 m forward
  (`SWORD_THRUST_*`); Diving Strike with the Broadsword out does the same angled down
  at the landing (`SWORD_DIVE_*`). Heavy attacks keep the overhead chop.
- **Boomerang Axe:** only the right axe swings, and it's hidden while that player's
  axe projectile is in flight (any projectile with `visual="axe"`), back when it's
  caught or ends. `ProjectileSystem` calls `Player.set_axe_thrown` every frame from
  the visible copies, so other players see it on the render clock too.

Tests: 349 passed. Smoke: default and `-Party` both passed (0 corrections). Bot
screenshots showed the right axe gone while the Boomerang Axe was out. The sword stab
wasn't caught clearly on screen (the bot's camera is behind it): check it by hand.

Left from session 20's list: items 1 (Crashing Leap aimed by pitch) and 2 (Diving
Strike shape). Then a playtest of all four.

### 2026-10-08 (20): Wave 2 playtest feedback (items 3 and 4 done in session 21)

Done: Vault's peak height 0.8 → 1.6 m (`weapon_spear.cfg` `leap_height`; cosmetic).

To do (developer feedback, with the plan):
1. **Crashing Leap aimed by camera pitch.** Looking level or down = full distance (4 m);
   looking up shortens it; looking straight up (or the camera's max pitch) = straight
   up, 0 m. Diving Strike and Vault keep their fixed distances.
   - **Needs a protocol change:** inputs carry only `aim_yaw`. Add `aim_pitch` (5th
     input element, validated on the server), passed into `PlayerState.step`.
   - At ability start, store the distance fraction in the length of `ability_dir`, which
     is already synced, so `to_array` doesn't change. Make sure `PlayerMovement`'s dash
     uses that length instead of normalizing.
   - New ability keys, e.g. `dash_aim_pitch=true`, `aim_full_pitch` (deg, full distance
     at or below) and `aim_zero_pitch` (deg, 0 at or above; check `camera.cfg`
     `max_pitch`).
   - Unit test the mapping. The cosmetic leap height stays.
2. **Diving Strike shape:** rise steeply first, then swoop down and forward.
   - **Horizontal:** a new `dash_ease="in"` option (speed ramps up over the dash; the
     total distance stays exact and deterministic).
   - **Height:** a new `leap_peak` key (fraction of the dash where the cosmetic height
     peaks, e.g. 0.3) instead of the symmetric parabola.
   - **Damage during the swoop:** windup covers the rise; the hit window (radial) is
     active during the late, horizontal part of the dash, not only on landing.
3. **Boomerang Axe visuals:** only one axe swings, and that axe leaves the hand
   (hidden) while its projectile is in flight, reappearing when caught or ended. The
   client's projectile system knows the owner's in-flight projectiles.
4. **Broadsword stab:** Opening Strike, and Diving Strike while the Broadsword is out,
   use a forward thrust like the Spear's. `_sword_pose` returns only rotation; it needs
   a forward offset like `_spear_pose`.

Then run tests and smoke, commit, and get a playtest.

### 2026-10-08 (19): Feather projectiles (class build Wave 2C); Wave 2 complete

Built by an agent, merged into main with no conflicts.

Done:
- **Projectiles** (`data/projectiles.cfg`, `game/combat/projectile*.gd`):
  - Simulated on the server with a swept hit test, so fast ones can't tunnel.
  - Speed, gravity, lifetime, hit radius, pierce, walls, guard-stops, boomerang return.
  - Hits resolve like melee: i-frames evade, a guard facing the throw blocks, allies are
    ignored, statuses/force/Ember apply. **Riposte parries projectiles** from the front.
  - Network: one reliable spawn event, plus turn/end events; every machine flies it
    with the same math. Nothing in snapshots.
  - The thrower sees their own throw instantly (a cosmetic copy the server confirms).
  - Feather-shaped visuals (tapered vane, quill, streak), coloured per kind.
  - Any attack or ability can fire one: `projectile`, `projectile_time`,
    `projectile_count`, `projectile_spread`.
- **Javelin Cast** (Spear): 110 damage, slows 3 s, 9 s cooldown. 28 m/s with a slight
  drop (about 22 m reach). Stopped by walls and guards.
- **Boomerang Axe** (Dual Axes): 65 per hit, 8 s cooldown. Flies 9 m out, returns to
  you as you move, hits each target once per leg, cuts through groups.
- Both are learned by default but **not slotted**: put them on Q/E/R in the K panel.
- Tests: 349. Smoke after merge: default 2 of 2 passed, `-Party` 1 of 1 (the agent:
  3 of 4 and 3 of 3; new flake "no player was moved by force" when every Husk hit
  was blocked).

Needs a hand playtest (`run_local_test.ps1`; two windows with `-NoBot` for PvP checks):
- **Javelin:** range, speed, drop, Slow on a Husk, stops on crates and the ground.
- **Boomerang:** returns as you move; hits going out and coming back.
- **Defense vs throws:** blocking facing the throw, Riposte, dodging through.
- **Corrections:** stay 0 while throwing.

Known gaps:
- Projectiles fly flat (no aim pitch).
- No impact effect.
- In rare cases the thrower could see their own throw twice.

**Next:** Wave 3 in `design/classes.md`: the rest of the Spear (Skewer, Perforate), enemy
threat (for taunts), then the Juggernaut. Also the queued task to make the smoke
test's luck-based checks reliable, and snapshot size (interest management / delta
compression) before playtests with more than 2 people.

### 2026-10-08 (18): Ember, Wings and Rebirth (class build Wave 2D)

Built by an agent, merged into main with no conflicts.

Done:
- **Ember** (`data/ember.cfg`):
  - A 0–100 meter (cap read in one place, for upgrades later), synced sim state.
  - Fills from damage dealt (0.08/pt), taken (0.05/pt) and healing done (0.05/pt).
  - After 6 s out of combat it settles to 50 at 4/s. Wing abilities spend it
    (predicted).
- **Wing slots on Z / C**, unchanged by weapon swaps. Wing tree (Bulwark / Fury, 12
  points) in the K panel's new Wings tab.
- **Fighter Wing abilities:**
  - Ember Mantle (25 Ember, −40% damage taken for 4 s).
  - Wingbeat Surge (25, +20% damage for 6 s).
  - Pyre Heart (30, heals 200 over 5 s; green numbers).
  - Diving Strike (20, 5 m leap, 2.5 m slam).
  - Both capstones work: Mantle of Renewal heals half the damage Ember Mantle prevents;
    Crushing Wingbeat makes Surge hits stagger.
- **Rebirth** (automatic): die with ≥ 50 Ember and Rebirth ready → 5 s in place
  (fire column, banner), back at 30% health, spends 50 Ember, then a 5 min cooldown
  (shown on the HUD). Hooks are ready for the Paladin (extra charges, cooldown cuts).
- **Healing exists now:** `World._heal_player` (also feeds Ember).
- **Merge fix:** the smoke run gives Diving Strike a 0.5 m knockback (off in the real
  data), so a Husk gets moved in nearly every run.
- **Snapshots** are close to ENet's 1392-byte packet size: about 524 bytes per player.
  A third player already goes over it, so interest management / delta compression is
  needed before bigger tests.
- Tests: 325. Smoke after merge: default 4 of 5 passed (fail: "no status applied to a
  Husk", bot luck), `-Party` 2 of 2. Corrections 0.

Needs a hand playtest (`run_local_test.ps1`):
- **Z and C:** the four Wing abilities (feel, numbers, Diving Strike distance).
- **The Ember bar:** fills in fights, settles back to 50; are the gain rates right?
- **Rebirth:** die above 50 Ember → Rebirth in place; die below → normal respawn.
- **K panel → Wings tab:** learning nodes, Z/C slots, capstones.

### 2026-10-08 (17): More playtest fixes

Developer playtest: Shield Charge still hit only one Husk (the second usually stood a
step away from the first contact), and Vault always faced forward.

Done:
- **Shield Charge impact:** a new `impact_radius` key (2.5 m). When a `max_targets`
  attack stops on contact, everything within that radius of you is hit too
  (`AttackParams.radial_copy`, `World._hit_targets`).
- **Vault faces where it goes:** the character turns to the vault direction as it
  starts (sim yaw, so other players see it too).
- **Dodge cooldown** 0.2 → 0.3 s.
- Tests: 289. Smoke: default 3 of 3 passed, `-Party` 2 of 2.

### 2026-10-08 (16): Wave 2 playtest feedback

Developer playtest: Opening Strike, Bloodlust and Hamstring work well; Hamstring's slow
is clearly visible.

Done:
- **Dodge cooldown:** a new `[dodge] cooldown` (0.2 s) after a roll before the next one.
  A press during it is buffered. It's synced state (`to_array()` index 31).
- **Shield Charge hits a group:** it still stops at its first contact, but now hits
  everything its hitbox touches at that moment (all staggered, ready for Rising Cut).
  Hitbox width 1.4 → 2.2 m so two targets side by side both get hit.
- **Bloodlust bug fixed:** it used one charge per *target* hit, so a swing through the
  two Husks at the camp used 2 charges, and each Husk ended with 2 bleed stacks. Now
  it's one charge per swing (per hit window), and every target that swing hits bleeds.
  4 swings = 4 stacks.
- **Spear:**
  - **Vault** goes the way you're moving (backward with no input) and has i-frames
    during its dash (0.05–0.4 s). New ability keys `dash_direction="input"`,
    `iframe_start`, `iframe_end`.
  - **Heavy:** same hitbox width as the light (0.8 m). The thrust animation now pushes
    the tip to the end of the hitbox, so the heavy (3.2 m) visibly reaches 0.4 m
    further than the light (2.8 m). This applies to every Spear thrust.
- Fixed a broken `weapon_spear.cfg` from the last session: a PowerShell edit had
  rewritten it in the wrong encoding, so Godot couldn't parse it. Restored from git.
- Tests: 287. Smoke: default 3 of 4 passed (the fail was the known guard flake),
  `-Party` 3 of 3.

Needs a hand playtest:
- Vault in each direction, and taking a Husk swing mid-vault (it should show
  "Evaded").
- Shield Charge into both Husks, then Rising Cut.
- Bloodlust on one Husk: it should reach "Bleed x4".
- The Spear heavy thrust's reach; the new dodge rhythm.

Next: Wave 2's second pair (feather projectiles; Ember, Wing slots and Rebirth).

### 2026-10-08 (15): Forced movement, Rising Cut and the Spear (class build Wave 2B)

Built by a parallel agent, merged into main on top of Wave 2A. The merge had 11
conflicting files; both sides were kept everywhere. The synced state is now: statuses
at index 27, forced movement at 28–30.

Done:
- **Forced movement:**
  - Knockback, pull, push along facing and launch, on players (predicted, a server
    event) and Husks (server-only).
  - Being moved interrupts like a stagger.
  - Never on allies, targets in i-frames, or blocked/evaded/parried/fatal hits.
  - Walls stop it.
  - `is_force_immune()` hook for the Juggernaut later. Limits in `combat.cfg` `[force]`.
- **Rising Cut** (Broadsword, Keen Edge tier 2): staggers; a target that was already
  staggered is launched 0.9 m up and pushed 0.8 m back. It chains from Shield Charge,
  guard breaks or Riposte.
- **Spear** (third Fighter weapon), Lancer and Impaler trees:
  - Reach: light 2.8 m, heavy 3.2 m.
  - Lunge: 4.5 m dash + thrust.
  - Low Sweep: wide, 3 m knockback + 0.5 s stagger.
  - Vault: 5 m backward dash.
  - Skewer, Javelin Cast and Perforate come later.
- **K panel:** "Equipped weapons" pickers to choose which two of the three you carry.
- **Merge fixes:**
  - The bot now rotates its focus weapon every cycle (default → Spear → Dual Axes →
    Broadsword). Before, the Dual Axes never came out and the status checks always
    failed.
  - The smoke test runs 32 s (four cycles).
  - `--tune` now takes strings without quotes.
  - New keys that are off in the real data and on in the smoke run: Husk
    `applies_status` (bleed) and Broadsword heavy `force_distance`.
- Unit tests now wait for a real physics frame. This fixed the occasional unknown
  unit-test failure (a dash test used a varying frame delta).
- Tests: 283. Smoke after merge: default 5 of 6 passed (the fail was "no Husk was moved
  by force"), `-Party` 3 of 3.

Needs a hand playtest (`run_local_test.ps1`):
- **K panel:** equip the Spear with the weapon pickers, then swap with X.
- **Spear:**
  - Reach.
  - Lunge distance.
  - Low Sweep knockback on Husks.
  - Vault backward.
- **Rising Cut:** use it after a Shield Charge stagger; the target should pop up.
- **Getting knocked back:** add `--tune=enemy_husk/attack/force_distance=2` to the
  server and client. Walls should stop you, nothing should rubber-band, and corrections
  should stay 0.
- **Tuning:** Low Sweep distance and duration, Rising Cut height, `[force]` limits.

Known gaps:
- Vault has no i-frames.
- Blocked hits never push.
- Bodies pass through each other when knocked back.

### 2026-10-08 (14): Status effects (class build Wave 2A)

Built by a parallel agent, merged into main. Wave 2B (forced movement + Spear) is still
in progress.

Done:
- **Status effects** (`data/status_effects.cfg`, `game/status/`):
  - Defined: bleed, slow, root, stun, Exposed, Empowered (damage up), Warded (damage
    reduction), Bloodlust.
  - They work on players (predicted where they change movement or actions) and on Husks
    (server-only).
  - Allies never debuff each other. Death clears them. Stun reuses stagger.
  - Bleed shows dark-red damage numbers and can kill.
- **New Fighter abilities:**
  - **Opening Strike** (Broadsword): Exposed, +25% damage taken for 6 s. It's learned by
    default but not slotted; use the K panel.
  - **Bloodlust** (Dual Axes): your next 4 hits within 8 s each add a bleed stack.
  - **Hamstring** (Dual Axes): 60% speed for 3 s. It now fills the axes' R slot.
- **HUD:** a status row for you, and a status line under other players and Husks.
- **Smoke test** now runs 24 s (three bot cycles; two left too little room for the
  status checks). Bloodlust is tuned to last 30 s in the smoke run only.
- Tests: 257. Smoke after merge: default 5 of 6 passed (the fail was the old guard
  check), `-Party` 3 of 3.

Needs a hand playtest (`run_local_test.ps1`):
- Slot Opening Strike and hit a Husk: it should show "Exposed" and take bigger numbers.
- Use Bloodlust on the axes, then hit Husks: they should show "Bleed xN" with ticks.
- Hamstring: the target should visibly slow.
- Tuning to judge: bleed 10/s per stack (max 5), slow 60%, Exposed +25%, cooldowns
  12 / 14 / 9 s.

Known gaps:
- Root, stun, Empowered and Warded exist, but nothing applies them yet (Wave 2D/3).
- Statuses only tick while the player's inputs arrive (keeps prediction exact; a lagging
  player's bleed pauses).
- Bloodlust survives a weapon swap.

### 2026-10-08 (13): Wave 1 playtest fixes; startup lag found

Playtest verdict (developer): ability timing, feel and distances are good as they are.

Done:
- **Startup lag fixed.** Cause: ENet's packet throttle. While clients start up, ping
  spikes and ENet drops bursts of unreliable packets (several in a row, enough to beat
  input redundancy), so the server skipped inputs and the client got corrections.
  In a 9-bot stress test: 24 skipped inputs and 24 corrections in one bot's first few
  seconds. Throttle now off (`core/net.gd`): 0 skipped inputs in 2 reruns; 1
  correction, which was the known flat-ground issue below.
- **K panel:** Esc now closes it like K. Closing it (either key) recaptures the mouse.
  Scrolling the panel no longer hides the cursor: wheel scrolls never capture the
  mouse, and no click does while a panel is open (`modal_ui` group).
- `--perf-log` flag: logs frames slower than 50 ms and the worst physics step. With 9
  bots, the server's worst physics step was 9–14 ms (limit at 60 ticks/s: 16.7 ms).
- Tests: 211. Smoke: default 3 of 3 passed, `-Party` 3 of 3.

Needs a hand playtest:
- Launch with `run_local_test.ps1`: is the startup lag gone?
- K panel: scroll it, close it with Esc.

### 2026-10-07 (12): Abilities, weapon swap and the Fighter (class build Wave 1A)

Built by a parallel agent from `design/classes.md`, merged into main after Wave 1B and
the loot work.

Done:
- **Class:** Fighter only (`data/class_fighter.cfg`), from `--class=` (default fighter).
  The server rejects weapons outside the class list.
- **Weapons:**
  - The sword is now the **Broadsword** (`weapon_broadsword.cfg`, same feel).
  - New **Dual Axes** (`weapon_dual_axes.cfg`): faster, weaker lights, blocked hits cost
    1.6× stamina.
  - **X swaps** (0.35 s; buffered; not mid-attack, ability or roll).
- **Abilities on Q/E/R:**
  - Broadsword: Whirlwind Edge (hits all around), Shield Charge (dash, stops at and
    staggers the first target), Riposte (parry stance: a frontal hit is negated with
    "Parried!" and you counter, Husks included).
  - Dual Axes: Frenzy (up to 4 hits), Crashing Leap (4 m leap, area slam). The third
    axes slot stays empty until Wave 2.
  - Cooldowns keep running while a weapon is holstered.
- **Mastery trees** (`data/mastery*.cfg`):
  - 2 branches per weapon, tier gates, 19 points (no XP yet).
  - Free respecs any time except mid-action.
  - Active nodes unlock abilities. Passives and upgrades are server-side damage/stamina
    modifiers. Capstones are placeholders.
  - **K** opens the tree panel.
- **HUD:** ability bar with cooldowns, plus a weapon line.
- **Bot and smoke test:** the bot uses abilities, swaps and respecs (8 s cycle). The
  smoke test runs 16 s and requires ability hits, swaps and a build change.
- Tests: 211 after the merge. Smoke: default 4 of 4 passed, `-Party` 4 of 4.

Needs a hand playtest (`run_local_test.ps1`):
- **Broadsword:** Q/E/R, especially Riposte against a Husk swing.
- **Dual Axes** (swap with X): Frenzy, Crashing Leap.
- **Swap:** how 0.35 s feels.
- **K panel:** learn/unlearn, tier gates, moving abilities between slots.
- **Corrections** should stay 0.
- **Tuning:** `data/weapon_*.cfg` and `data/mastery*.cfg`.

Known gaps:
- Mastery allocations are lost on reconnect (persistence is milestone 5).
- Crashing Leap's height is visual only, so it can't reach ledges.
- Newly equipped weapons start with cooldowns at 0.
- Snapshots grew by about 30 values per player.

### 2026-10-07 (11): Parties and the ally rule (class build Wave 1B)

Built by a parallel agent from `design/classes.md`, merged into main.

Done:
- **Parties:**
  - Invite the player nearest your crosshair (**T**), join (**Y**), decline (**N**),
    leave (**L**), kick (**Delete**, leader only).
  - Up to 5 members; invites expire after 30 s; invite range 20 m (`data/party.cfg`).
  - The server validates everything; pure rules in `PartyRules`.
- **Ally rule:** `World.are_allies(a, b)` is the single source of truth. Party members
  can't damage, stagger or block-drain each other. Enemies are unaffected.
- **HUD:** party frames with health (left), an invite prompt, cyan nameplates for party
  members.
- **Testing:**
  - `--bot-party` bots party up.
  - `smoke_test.ps1 -Party` requires a party to form and 0 ally hits.
  - `run_local_test.ps1 -Party` gives you a bot that joins your party.
- Tests: 131. Smoke after merge: default 8 of 9 passed (the 1 fail is likely the known
  "no hit landed on a guard" flake), `-Party` 3 of 3.

Needs a hand playtest (`run_local_test.ps1 -Party`):
- Invite/join/leave flow.
- The bot's swings pass through you while partied.
- Layout and colours of the party frames.
- Key choices.

### 2026-10-07 (10): Items and loot rolls (milestone 2, session 1)

Done (pure logic and data; nothing in the game world yet, so no shared files touched
besides two small helpers in `core/tuning.gd`):
- Rarity tiers (Common, Rare, Epic, Legendary: 0–3 bonus stats), 7 items (Iron Broadsword, Iron
  Hatchets for Dual Axes, five Padded armor pieces), 6 bonus stats (affixes), and the
  Husk loot table: 60% drop chance, gear score 100–140.
- `LootRoller` (seeded, server-side), `Item` (plain data for network/saves),
  `ItemDatabase` with `validate()`.
- `tools\roll_loot.ps1`: 50,000 Husk kills in about a second. Rarity and item spread
  match the weights; Legendary is about 1 in 345 kills.
- Tests: 90 (14 for loot, including one that validates the real data files).

Developer decisions after the first sim run:
- Removed the Uncommon tier, so rarities are Common 0 / Rare 1 / Epic 2 / Legendary 3
  bonus stats. Weapons, hands and chest have 3+ eligible affixes, so their Legendaries
  are full. **Still open:** head, legs and feet only have 2 eligible affixes, so their
  Legendaries roll 2 (same as Epic).
- Husk rarity weights set to Common 78 / Rare 18 / Epic 3.3 / Legendary 0.7 (% of drops).
- Affix names: Blaze (damage), Sear (crit), Hearth (max health), Ferocity (max stamina),
  Rage (stamina regen), Scorch (block stamina cost). Ids in `affixes.cfg` unchanged.

### 2026-10-07 (9): First enemy (Husk)

Done:
- Husk: a slow, heavy-hitting melee enemy, fully server-controlled. Two of them at a
  camp ~15 m north of spawn. They wander, notice players within 8 m, chase, and swing
  (0.6 s windup telegraphed by glowing red, 120 damage, 0.3 s stagger on hit). Roll and
  block work against them as against players.
- Players hit Husks with the same attacks; heavies stagger them (interrupting their
  windup). 600 health; dead Husks respawn at the camp after 10 s. Pulled more than 25 m
  from camp, a Husk walks home and heals.
- All values in `data/enemy_husk.cfg`. Camps are `Marker3D`s in `world.tscn`.
- The bot fights the nearest Husk within 15 m (else you), so you can fight Husks
  together, which is milestone 1's "done" check.
- Tests: 76 (11 for the enemy brain). Smoke test: Husks and bots must hit each other;
  0 corrections across 5 runs. Visuals checked from game frames (telegraph, club,
  labels).

Needs a hand playtest (milestone 1 check): fight the Husks with the bot (or a second
person). Is it fun? Tune `data/enemy_husk.cfg`.

### 2026-10-07 (8): Block

Controls changed (developer's choice, New World layout): **tap left click = light,
hold left click = heavy, hold right click = block.**

Done:
- Block: frontal arc (120°) blocks hits; blocked hits cost stamina
  (`block_stamina_damage` per attack) instead of health. Slower movement and stamina
  regen while blocking; the guard faces the camera. Attacking or rolling drops the
  guard, and it comes back if right click is still held.
- Guard break: heavy attacks always break a guard (`breaks_block`), and so does any hit
  with more stamina damage than the blocker has. Guard break = 1.2 s stagger (raised
  from 0.8: at 0.8 the stagger ended before the attacker could follow up after a heavy).
- "Blocked" / "Guard broken!" labels; placeholder shield raises when blocking.
- Fixed a real prediction bug: the client didn't restore the body's on-floor flag when
  reconciling, so a correction that moved you into the air made the replay drift. The
  flag is now part of `PlayerState`.
- Bots take turns: one attacks (heavy, then two lights) while the other blocks. Smoke
  test (now 12 s) requires blocks and guard breaks too. `--verbose` logs unexpected
  corrections and dropped inputs.
- Tests: 65.

Needs a hand playtest: block feel, guard break length, stamina cost of blocked hits,
and whether heavies should always break guard.

### 2026-10-07 (7): Death, respawn and stagger

Done:
- Death at 0 health: the player drops (grey, face down), can't act or be hit. A
  "Defeated / Respawning in N" banner counts down; after 5 s (`[death] respawn_time`)
  they respawn at a random spawn point with full health and stamina.
- Stagger: heavy hits stagger the target for 0.4 s (`stagger` per attack in
  `weapon_sword.cfg`; light is 0). Interrupts their attack or roll; presses during it
  are buffered. Body tilts back while staggered.
- `--tune=file/section/key=value` launch option to override tuning for one run.
- Fixed two sources of false prediction corrections: respawning in mid-air (now on the
  ground) and two snapshots acknowledging the same input. Corrections caused by server
  events (stagger/death/respawn) aren't counted.
- Tests: 51 (11 new for stagger/death). Smoke test runs with 300 health and 0.5 s
  respawn: 1–2 deaths and respawns per run, 0 corrections.

Needs a hand playtest: respawn time, stagger length, whether light hits should stagger.

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

Milestone 2, one session each. Checked against `design/classes.md` (another session is
building its Wave 1 in parallel: 1A ability framework/weapon swap/Fighter, 1B parties):
1. **Done (session 10):** items and loot rolls, pure logic + tests: item definitions,
   rarity tiers, rolled stats, gear score ranges, Husk loot table, all in `data/`, plus a
   script that rolls 50,000 drops and prints the real rarity distribution. **No
   attributes** (design decision): gear stats are things like damage %, armor, max
   health/stamina, crit. Weapon items name a weapon type (class-locked; attack timings
   stay in 1A's `data/weapon_<name>.cfg`, not in loot data).
2. **After Wave 1 merges** (touches `world.gd`, HUD): dead Husks drop **personal** loot
   (everyone who damaged it gets their own server roll, so no party loot rules); pick up
   with **F**, inventory screen on **I** (Wave 1 uses Q/E/R/X/K/Z/C).
3. **After 1A merges:** equipping armor and weapons changes your numbers, built on 1A's
   weapon slots, with gear bonuses feeding the same modifier path as mastery passives.

Later / unscheduled:
- Light attack combo chain (New World-style 3-hit string)?
- Swap the capsule for a CC0 character with Mixamo idle/run/roll animations
  (download the packs yourself; Mixamo needs an Adobe login).

## Known issues / notes

- Husks steer straight at their target (no navmesh), so a crate between you and a
  Husk can stall it. Fine for the open test area; add navigation before real zones.
- A heavy's hitbox can hit both Husks at once when they stand together.

- About 1 smoke run in 20 shows a few (≤4) small unexpected corrections on flat ground
  (~0.1 m sideways), not near any server event. Cause unconfirmed; the server logged no
  dropped inputs in 12 runs that tried to catch it. Smoke test tolerates ≤5. Run with
  `--verbose` to get the details if it shows up in play. Seen again on 2026-10-08: one
  ~9 cm position mismatch with an identical `PlayerState`, so it's in the physics step,
  not the sim state.
- The occasional unit-test failure under load was `test_abilities` dash tests using a
  varying frame delta; fixed in Wave 2B (the runner waits for a physics frame). If a
  unit test still fails now and then, note its name.
- Smoke checks that depend on the bots' fights going a certain way still fail about 1
  run in 10: "no hit landed on a guard" and "no Husk was moved by force".
- When 9 bots quit at once, the server had one ~100 ms tick (disconnect handling).
  Harmless now; look at it if mass disconnects matter later.

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

# Playtest checklist (Wave 3: sessions 24–25)

Everything built since the last approved playtest, on branch `wave3-merge`. Tick what
works, and write notes on the `Feedback:` lines (numbers to change, what felt wrong).
Hand the file back and I'll turn it into fixes.

**How to run**
- Fighter: `powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -Party`
- Juggernaut: `powershell -ExecutionPolicy Bypass -File tools\run_local_test.ps1 -Class juggernaut -Party`
  (the bot is always a Fighter; `-Party` makes it join you: press T near it, or Y)
- Two players / ally tests: add `-NoBot` for two windows you control.
- New abilities are learned by default but **not slotted**: put them on Q/E/R in **K**.
- **Capstones** (tier 4) aren't in the default builds: spend points in K to reach them
  (a branch's tier 4 needs 6 points in its lower tiers).
- F3 shows hitboxes.

---

## All classes: enemy threat (Husks)

- [X] With one player, Husks behave as before (notice you, chase, swing, go home when leashed).
- [X] Two players (or you + bot) on one Husk: it switches to whoever is doing more damage, without flickering back and forth.
- [X] When a Husk's target dies, it goes after the other player who hurt it (it used to walk home).
- [ ] Healing draws aggro: Pyre Heart (Fighter Wing) while a Husk is on your partner pulls it toward you.

Feedback:

--- I couldn't verify that Pyre Heart drew aggro with the test, but for now its fine if your test had it succeed

## Fighter

### Broadsword: Shield Wall (Vanguard tier 2)
- [ ] Cast it, then hold block: an ally standing right behind you (2.5 m deep, 1.8 m wide) is covered from hits in front of you; they see "Blocked", you lose the stamina.
- [ ] Works against Husk swings and projectiles (Javelin) too.
- [ ] Box size and 6 s duration feel right.
- Tip: easiest with `-NoBot` (two windows). The Fighter bot also uses Shield Wall, so you can stand behind it.

Feedback: Shield Wall did not seem to block hits accurately for allies

### Spear: Hold the Line (Lancer capstone)
- [X] While blocking with the Spear, a Husk (or hostile player) stepping into your reach (2.6 m) gets poked: 40 damage + Slow 2 s.
- [X] At most once per target every 2 s; never pokes allies.
- [X] Reach and frequency feel right (there's no poke animation yet, only the damage number).

Feedback: Feels good!

### Spear: Finishing Thrust (Impaler capstone)
- [X] Spear hits on a Husk below 30% health do noticeably more (up to +60% near 0), Javelin Cast included.

Feedback:This also seems to work well, might need to add a 3rd husk with 6,000 HP to effectively test numbers

### Dual Axes: Rampage (Berserker tier 2)
- [X] Light and heavy attacks are faster (1.25×) for 8 s while stamina is at least half; normal speed below half.
- [X] Hits still land reliably while hasted; no corrections on the HUD.
- [X] Remote players' hasted attacks don't look too jumpy (watch the bot use it).

Feedback:

--- Also looks great!

## Juggernaut

General:
- [X] Class loads, both starting weapons (Halberd, War Hammer) work, X swap, the K panel shows all three trees and the Wings tab.
- [X] Models and swings read well (known: the Greataxe is mostly hidden behind the body from the camera).
- [X] Overall feel: slower and heavier than the Fighter, but not sluggish.

Feedback: Doesn't feel as slow or heavy as I would expect, maybe need to slow down animations and give some i-frames

### Halberd (default Q/E/R: Hooking Pull, Wide Reap, Crowd Sweep)
- [ ] Light (reaching sweep) and heavy (overhead chop, breaks blocks) feel.
- [ ] Hooking Pull: 5.5 m line, drags the target 4.5 m toward you, marks it Hooked.
- [ ] Wide Reap: huge sweep (3.6 m × 6 m).
- [ ] Pole Vault: 6 m vault forward, knockback on landing.
- [ ] Brace: knockback-immune 3 s; a Husk/player hitting you while dashing, or in the first 1 s, gets staggered.
- [ ] Cleaving Arc: overhead chop that applies Exposed.
- [ ] Crowd Sweep: pushes everything in front back 4 m.
- [ ] Capstone **Caught on the Hook** (Warden): your next hit on a target you Hooked staggers it.
- [ ] Capstone **Headsman's Verdict**: heavy on an already-staggered target shows "Critical!" (1.5×). *Never fired in bot runs.* Try: Clout a Husk with the War Hammer, swap, heavy with the Halberd.

Feedback: I like the weapon overall, feels very light for a tank weapon but I Like it as a ligher option

### Greataxe (default Q/E/R: Vortex, Charging Chop, Grounding Blow)
- [ ] Light (wide cleave) and heavy (big chop) feel.
- [ ] Vortex: 3 spinning hits that pull enemies inward (3.5 m).
- [ ] Charging Chop: 6 m run, then a chop.
- [ ] Grounding Blow: slam, Slow 3 s around you.
- [ ] Executioner's Swing: big bonus on targets below 30% health.
- [ ] Iron Hide: 6 s, less damage the more enemies are near (−8% each, up to −40%).
- [ ] Hurl: throws the axe ~15 m, Slow 5 s (no pickup: it's a fixed slow).
- [ ] Capstone Maelstrom: Vortex pulls from twice as far (7 m). *Never seen in play.*
- [ ] Capstone Red Tide (Bloodied): damage builds with each hit (+3% per stack, up to 8), drops 2.5 s after you stop hitting.

Feedback: Really like this weapon & playstyle

### War Hammer (default Q/E/R: Seismic Slam, Clout, Upheaval)
- [ ] Light and heavy feel (heavy: 240 damage, long stagger, slow; doesn't break blocks by default).
- [ ] Seismic Slam: 90° cone in front, knocks down and back.
- [ ] Clout: single target, stun 1.5 s.
- [ ] Shatter: target takes +15% damage per stack (2 stacks).
- [ ] Upheaval: launches everything around you.
- [ ] Shockwave: a wave rolling along the ground ~10 m, staggers, passes through targets. Look and reach OK?
- [ ] Steadfast: can't be knocked back, staggered or stunned for 4 s.
- [ ] Capstone Earthshaker: every 3rd heavy sends out a wave.
- [ ] Capstone Breaker: heavies break a blocking player's guard. *Never seen in play* (needs `-NoBot` or the bot blocking).

Feedback: Upheaval animation should better illustrate its hitting the ground, and not just swinging down. Shatter should have a lower cooldown if its effect can stack. Earthshaker should send out the shockwave in all directions. (ring around the user).

### Juggernaut Wings (default Z: Gale Burst, C: Challenger's Roar)
- [ ] Gale Burst (20 Ember): knocks everything around you back 3.5 m.
- [ ] Challenger's Roar (25): Husks within 8 m switch to you (Taunted 4 s) and are slowed.
- [ ] Meteor Drop (30): 6 m leap up, crash launches everything where you land. Arc looks good?
- [ ] Unbowed (25): immune to knockback, stagger, stun, slow, root for 4 s.
- [ ] Capstone Tempest Wings: a Husk knocked into a wall/crate is stunned 1.5 s. *Never fired in bot runs.* Try Gale Burst next to a crate.
- [ ] Capstone Anchor: each Husk the Roar taunts gives you a stack of Defiant (−6% damage taken).
- [ ] Ember costs and cooldowns feel right next to the Fighter's Wings.

Feedback: Meteor Drop looks amazing, lets slow down the animation on the way up a little bit. Otherwise this class feels awesome right now.

---

## Design calls the agents made (keep or change?)

Mark each **keep** or **change** (and how).

Threat and immunities:
- [**keep**] Healing gives full threat to every enemy fighting the player you healed.
- [**keep**] Unbowed also blocks taunts.
- [**keep**] Steadfast blocks stuns as well as staggers.

Fighter:
- [**keep**] One wide swing that hits both a Shield Wall holder and the ally behind costs the holder stamina twice.
- [**keep**] Rampage stops speeding you up mid-attack if stamina drops below half.
- [**keep**] Bots now slot self-buffs first (they no longer use Hamstring or Shield Charge).

Juggernaut:
- [**keep**] Brace's "charge" = an attacker who is dashing, or any melee hit in the first 1 s of bracing.
- [**change** - Only once capstone is unlocked] Hooked is applied even without the capstone (a visible mark that does nothing alone).
- [**keep**] Hooking Pull hooks everything its line touches on contact, not just one target.
- [**keep**] Crits only on targets staggered *before* the hit; crit = 1.5× damage.
- [**keep**] Challenger's Roar is a 0-damage hit: a guard facing you blocks it, Husks show "0".
- [I don't know what this is refering too] Defiant only counts taunts from the Roar itself.
- [**keep**] An interrupted heavy doesn't count toward Earthshaker's every-3rd.
- [**keep**] Wall stun never comes from pulls, and also stuns players (PvP).
- [**keep**] Shattered is 2 stacks × 15% (Exposed is 1 × 25%).

Other notes:

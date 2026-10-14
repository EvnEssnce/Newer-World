# Classes, Weapons, Abilities and Upgrade Trees

The design for all six classes (written 2026-10-07; everything in it was built in
sessions 12–37, except progression: every tree has all its points today). Ability names
are original to this project. Numbers here are the design's starting points; the real
values are in `data/*.cfg`. The last part, "Implementation notes", says how each class
was actually built, including where it differs from the design.

## How the pieces fit

The brief (`PROGRESS.md`) says each character carries **two weapons with a swap
key, and each weapon has abilities on cooldowns and a mastery tree**. Classes sit on top of
that:

| Layer | Belongs to | Gives you | Progresses through |
|---|---|---|---|
| **Class** | Character | Which weapons you can equip, plus your Wing abilities | Character level |
| **Weapon** | Weapon type | Light/heavy attacks, a pool of weapon abilities | That weapon's mastery level |
| **Wings** | Class | Class abilities (the phoenix half) | Wing tree, from character level |

- **Class** is picked when the character is created and **can't be changed**. Weapon lists
  are strict: each weapon belongs to exactly one class, and no other class can equip it.
- **No attributes** (strength, dexterity and so on) for now. Builds come from the trees.
  Phoenix/fire-themed attributes may be added later.
- **Weapons.** You equip 2 of your class's weapons and swap with a key. Each weapon has
  light and heavy attacks plus **3 ability slots**, filled from a pool of about 6 abilities
  that you unlock in its mastery tree. Abilities run on cooldowns.
- **Wings.** Every class has **2 Wing ability slots** that stay the same when you swap
  weapons. They're fuelled by **Ember** (see below) and also have short cooldowns.
- **Ember.** This is the phoenix resource and the main thing that sets this game apart from
  New World. It works like this:
  - **Cap:** 100 by default. Upgrades earned through progression raise it.
  - **Resting level:** 50. Out of combat, Ember settles back to 50: it refills if you're
    below and drains if you're above. So every fight starts with 50.
  - **Gaining Ember:** dealing damage, taking damage and healing all add to it.
  - **Spending Ember:** Wing abilities cost Ember. **Mage weapon abilities also cost Ember**
    (Mages have no mana), so Mages need a higher Ember gain rate. Tune it once both exist.
- **Rebirth (all classes).** When you die with at least **50 Ember**, you rise again
  **automatically** after a **5 second** rebirth animation, in place, with **30% health**,
  instead of waiting for the respawn timer. It spends the 50 Ember and has a **5 minute
  cooldown**. This creates the main Ember decision in a fight: spend it on Wings now, or
  keep 50 in reserve so you can come back. Paladin abilities can shorten allies' Rebirth
  cooldowns and grant temporary extra Rebirths.
- **PvE first.** The game is balanced for fighting enemies. PvP is a much smaller focus, so
  taunts and threat are worth building, and party members never damage each other.

### Tree shape (weapon mastery and Wings)

Each tree has **2 branches**. Each branch has 3 tiers of about 3 nodes, then a capstone.
There are three kinds of node:

- **Active:** unlocks an ability for your slots.
- **Passive:** always on (for example, +10% damage to staggered targets).
- **Upgrade:** changes an ability you've unlocked (shorter cooldown, adds a slow, and so on).

You get 1 point per level. With a level cap of 20 (19 points) and about 13 points per
branch, you can max one branch and dip into the other, but you can't max both. **Respecs are
free and can be done at any time**, so trying out builds costs nothing.

### Roster at a glance

| Class | Range | Role | Weapons | Wing focus |
|---|---|---|---|---|
| Fighter | Melee | Tank / DPS | Broadsword, Spear, Dual Axes | Hitting harder, staying alive |
| Ranger | Ranged | DPS | Longbow, Crossbow, Firebolts | Creating distance (roll upgrades) |
| Assassin | Melee (+ short ranged) | DPS | Throwing Knives, Dual Talons | Distractions, fast repositioning |
| Juggernaut | Melee | Tank | Halberd, Greataxe, War Hammer | Knockback, crowd control |
| Mage | Ranged | DPS / Healer | Great Staff, Gauntlet | Magic power, crowd control |
| Paladin | Melee | Tank / Healer | Dual Shortstaffs, Great Staff* | Defensive wings, cleansing |

\* The Mage and Paladin both list a Great Staff, but one is a ranged caster and the other
is a melee tank, so the Paladin's is the **Longstaff** (a melee quarterstaff).

### Ability tags

Each ability below is tagged with the engine systems it needs. That shows what has to be
built before the ability can exist:

- `PROJ`: projectiles (every ranged weapon). Most projectiles
  (arrows, bolts, knives, Firebolts) are **feather-shaped**: that's the game's visual
  signature.
- `STATUS`: buffs and debuffs with durations (bleed, burn, slow, root, stun, silence, damage reduction)
- `DASH`: the caster moves themselves (lunge, leap, blink)
- `FORCE`: moves other players (knockback, pull, knock-up)
- `AREA`: a ground effect that lasts after the cast
- `ALLY`: targets or affects teammates (heals, shields, cleanse). Needs parties.
- `SUMMON`: spawns an entity (decoy, trap, barrier)
- `STEALTH`: hides the player. Built as visual only (drawn faint, no nameplate); the
  position is still in snapshots, so a modified client could read it.

---

## Fighter

Melee, Tank / DPS hybrid. A flexible front-liner: the Broadsword leans defensive, the Dual
Axes lean all-in, and the Spear sits in between with reach.

### Broadsword (one-hand + shield)
Balanced, can block, reliable. The baseline weapon everything else is measured against.
- **Branch: Vanguard.** Blocking, shield bashes, guarding allies. *Capstone:* a perfectly
  timed block staggers the attacker.
- **Branch: Keen Edge.** Damage, bleeds, combo strings. *Capstone:* the third light attack
  in a chain always crits.

| Ability | Effect | Tags |
|---|---|---|
| Rising Cut | Upward slash. Staggers, and launches a staggered target slightly. | FORCE |
| Shield Charge | Charge forward. The first enemy hit is staggered. | DASH |
| Riposte | Short parry stance. A hit taken during it is negated and answered with a counter. | |
| Whirlwind Edge | Spin that hits everything around you. | |
| Shield Wall | Block stance that also covers allies directly behind you. | ALLY |
| Opening Strike | Heavy thrust that applies Exposed (target takes +damage). | STATUS |

### Spear
Reach and control. Fights at the end of its range and punishes enemies who close in.
- **Branch: Lancer.** Reach, sweeps, zone control. *Capstone:* enemies who move into your
  reach while you hold block are automatically poked and slowed.
- **Branch: Impaler.** Armor piercing, bleeds, finishers. *Capstone:* damage ramps up
  against targets below 30% health.

| Ability | Effect | Tags |
|---|---|---|
| Lunge | Dash forward with a long-reach thrust. | DASH |
| Low Sweep | Wide low arc that knocks down. | FORCE |
| Skewer | Pins the target in place (root) briefly. | STATUS |
| Javelin Cast | Throws a conjured spear that slows on hit. | PROJ, STATUS |
| Vault | Uses the spear to vault backward out of melee. | DASH |
| Perforate | Rapid multi-thrust that stacks bleed. | STATUS |

### Dual Axes
Fast and aggressive with weak defense. Rewards staying in the fight.
- **Branch: Berserker.** The lower your health, the more damage you deal; lifesteal.
  *Capstone:* once per fight, dropping below 20% health grants a few seconds of heavy
  lifesteal.
- **Branch: Reaver.** Cleave and bleeds. *Capstone:* bleeds spread to nearby enemies when
  the target dies.

| Ability | Effect | Tags |
|---|---|---|
| Frenzy | A flurry of four quick chops. | |
| Boomerang Axe | Throws one axe, which returns. Hits on the way out and back. | PROJ |
| Bloodlust | Your next several hits apply bleed. | STATUS |
| Crashing Leap | Jumps to a target point and slams. | DASH |
| Hamstring | Slows the target. | STATUS |
| Rampage | Attack speed buff while above 50% stamina. | STATUS |

### Fighter Wings: force and survival
- **Branch: Bulwark.** Survivability. *Capstone:* Ember Mantle also heals for some of the
  damage it blocked.
- **Branch: Fury.** Raw force. *Capstone:* Wingbeat Surge's empowered hits also stagger.

| Ability | Effect | Tags |
|---|---|---|
| Ember Mantle | Wings wrap around you: heavy damage reduction for a few seconds. | STATUS |
| Wingbeat Surge | Your next several attacks deal bonus damage. | STATUS |
| Pyre Heart | Burns Ember to heal over time. | STATUS |
| Diving Strike | A wing-assisted leap that slams down on a target. | DASH |

---

## Ranger

Ranged DPS. Wants space and has tools to keep it. Their Wings mostly upgrade the combat
roll.

### Longbow
Long range, charged shots, rewards precision.
- **Branch: Marksman.** Charged and precision shots; bonus for headshots or weak points.
  *Capstone:* a fully charged shot pierces through every target in a line.
- **Branch: Skirmisher.** Quick shots and moving while you shoot. *Capstone:* no movement
  slowdown while drawing.

| Ability | Effect | Tags |
|---|---|---|
| Piercing Shot | Arrow passes through several targets. | PROJ |
| Arrow Rain | Volley on a target area. | PROJ, AREA |
| Snare Arrow | Roots the first target hit. | PROJ, STATUS |
| Backstep Shot | Hop backward and fire. | DASH, PROJ |
| Hunter's Mark | Marked target takes extra damage from you and is visible to your party. | STATUS |
| Rapid Nock | Next 3 shots fire without charge time. | STATUS |

### Crossbow
Medium range with heavy hits and reloads. Burst, then a vulnerable window.
- **Branch: Siege.** Big bolts, knockback, armor break. *Capstone:* the first bolt after a
  reload deals double damage.
- **Branch: Trapper.** Traps and zone denial. *Capstone:* traps re-arm once after
  triggering.

| Ability | Effect | Tags |
|---|---|---|
| Concussive Bolt | Knocks the target back. | PROJ, FORCE |
| Bolt Barrage | Empties the magazine in a quick burst. | PROJ |
| Tripwire | Places a trap that roots the first enemy to cross it. | SUMMON, STATUS |
| Scatter Bolt | Short-range cone of bolts. | PROJ |
| Smoke Bolt | Creates a cloud that blocks enemy targeting and vision. | AREA |
| Quick Reload | Instant reload, and the next bolt slows. | STATUS |

### Firebolts
Hand-fired, rapid-fire burning feathers at short-to-mid range. Built around stacking burn.
- **Branch: Kindling.** Builds burn stacks. *Capstone:* burn can stack twice as high.
- **Branch: Flashfire.** Cashes out stacks for burst. *Capstone:* Ignite refunds Ember for
  each stack it consumes.

| Ability | Effect | Tags |
|---|---|---|
| Scatterflame | Short cone of fire. | PROJ |
| Ignite | Detonates all burn stacks on the target for burst damage. | STATUS |
| Flare | Bright bolt that briefly blinds (enemy attacks miss) on hit. | PROJ, STATUS |
| Fire Trail | Your next rolls leave burning ground. | AREA |
| Seeker Spark | A slow bolt that homes in on the target. | PROJ |
| Overheat | Faster fire rate for a few seconds, then a short lockout. | STATUS |

### Ranger Wings: creating distance
- **Branch: Windrider.** Roll range, roll charges, stamina cost. *Capstone:* a second roll
  charge.
- **Branch: Parting Shot.** Rewards rolling away. *Capstone:* every roll empowers your next
  shot.

| Ability | Effect | Tags |
|---|---|---|
| Gust Roll | For a short time your roll becomes a long wing-assisted glide. | DASH, STATUS |
| Backdraft | Wing blast that knocks nearby enemies away from you. | FORCE |
| Updraft | Launches you upward and lets you hover briefly while shooting. | DASH |
| Tailwind | Movement speed buff; rolling refunds stamina. | STATUS |

> Updraft needs vertical movement that the current controller doesn't have (hovering,
> controlled descent). It's the most expensive item on this list. A cheaper version would
> just be a high jump.

---

## Assassin

Melee DPS with a short-range ranged option. Wins by being somewhere unexpected. Their Wings
are about misdirection and repositioning.

### Throwing Knives
Short-to-mid range. Fast and cheap, with poison and slows. Made to pair with the Talons:
soften a target, then close in.
- **Branch: Venom.** Poison and debuffs. *Capstone:* poisoned targets heal for less.
- **Branch: Flurry.** Volume of throws. *Capstone:* every 5th knife is a free Fan of
  Knives.

| Ability | Effect | Tags |
|---|---|---|
| Fan of Knives | Short cone of knives. | PROJ |
| Pinning Knife | Slows the target. | PROJ, STATUS |
| Marked Blade | Marks the target. Your next hit on it from melee deals bonus damage. | PROJ, STATUS |
| Venom Coat | Your next several knives apply poison. | STATUS |
| Ricochet | Knife bounces between up to 3 targets. | PROJ |
| Recall | Pulls stuck knives back to you, hitting anything in between. | PROJ |

### Dual Talons
Phoenix-claw fist weapons. The fastest attacks in the game, built around combos and attacks
from behind.
- **Branch: Predator.** Backstabs and crits from behind or on unaware targets. *Capstone:*
  hits from behind ignore block.
- **Branch: Tempest.** Combo chains and attack speed. *Capstone:* each hit in an unbroken
  combo adds attack speed, up to a cap.

| Ability | Effect | Tags |
|---|---|---|
| Pounce | Leaps onto a target. | DASH |
| Rending Talons | Cross-slash that applies bleed. | STATUS |
| Eviscerate | Finisher that deals more damage the lower the target's health. | |
| Talon Spin | Spinning flurry around you. | |
| Feint | A fake attack: if the target blocks or dodges, your next hit is a guaranteed crit. | |
| Hook Talon | Short grapple that pulls the target a step toward you. | FORCE |

### Assassin Wings: distraction and repositioning
- **Branch: Trickster.** Decoys and confusion. *Capstone:* decoys copy your last attack
  when they're hit.
- **Branch: Phantom.** Blinks and positioning. *Capstone:* Ashstep gets a second charge.

| Ability | Effect | Tags |
|---|---|---|
| Ember Double | Leaves a burning decoy where you stood and makes you hard to see for a moment. | SUMMON, STEALTH |
| Ashstep | Short blink in your movement direction. | DASH |
| Plumage Flash | A burst of feathers in a cone that disorients (enemy aim and turn speed reduced). | STATUS |
| Shadow Swap | Swaps places with your decoy (only while it's out). | DASH |

> Stealth (even "hard to see") leaks if the server keeps sending the hidden player's
> position. Start with a visual-only version (translucent, no nameplate). Make it truly
> invisible later only if that turns out to matter.

---

## Juggernaut

Melee tank. Controls the fight by moving enemies around. Slow and heavy-hitting, hard to
move.

### Halberd
Reach plus axe-head sweeps. Controls lanes.
- **Branch: Warden.** Pulls and zone control. *Capstone:* hitting a target you've hooked
  staggers it.
- **Branch: Headsman.** Big overhead finishers. *Capstone:* heavy attacks on staggered
  targets crit.

| Ability | Effect | Tags |
|---|---|---|
| Hooking Pull | Hooks the target and drags it to you. | FORCE |
| Wide Reap | Huge horizontal sweep. | |
| Pole Vault | Vaults forward and lands with a short-range knockback. | DASH, FORCE |
| Brace | Plants the halberd: immune to knockback, and enemies who charge you are staggered. | STATUS |
| Cleaving Arc | Overhead chop that applies Exposed. | STATUS |
| Crowd Sweep | Pushes everything in front of you back a few meters. | FORCE |

### Greataxe
Heavy cleave. Pulls enemies in, then punishes the clump.
- **Branch: Maelstrom.** Gathers enemies together. *Capstone:* Vortex pulls from twice as
  far.
- **Branch: Bloodied.** Damage that ramps over a fight. *Capstone:* each hit landed raises
  damage until you stop hitting.

| Ability | Effect | Tags |
|---|---|---|
| Vortex | Spin that pulls nearby enemies inward. | FORCE |
| Charging Chop | Runs forward and finishes with a chop. | DASH |
| Grounding Blow | Slam that slows everything around you. | STATUS |
| Executioner's Swing | Bonus damage on targets below 30% health. | |
| Iron Hide | Damage reduction that scales with enemies nearby. | STATUS |
| Hurl | Throws the axe; the target is slowed until you pick it up again. | PROJ, STATUS |

### War Hammer
Slow, crushing. Best stagger and stun weapon.
- **Branch: Earthshaker.** Area stuns and knockdowns. *Capstone:* every 3rd heavy attack
  sends out a shockwave.
- **Branch: Breaker.** Armor break and block break. *Capstone:* heavy attacks break block.

| Ability | Effect | Tags |
|---|---|---|
| Seismic Slam | Cone that knocks enemies down. | FORCE |
| Clout | Single target stun. | STATUS |
| Shatter | Armor break: the target takes increased damage. | STATUS |
| Upheaval | Knocks enemies around you up into the air. | FORCE |
| Shockwave | Ground-travelling wave that staggers. | PROJ |
| Steadfast | Immune to stagger and knockback for a few seconds. | STATUS |

### Juggernaut Wings: knockback and crowd control
- **Branch: Tempest Wings.** Knockback strength and range. *Capstone:* enemies knocked into
  walls are stunned.
- **Branch: Anchor.** Control and taunt. *Capstone:* Challenger's Roar also grants you
  damage reduction for each enemy taunted.

| Ability | Effect | Tags |
|---|---|---|
| Gale Burst | Wings beat outward: knocks everything around you back. | FORCE |
| Meteor Drop | Jumps up and crashes down, knocking up everything where you land. | DASH, FORCE |
| Challenger's Roar | Taunt: nearby enemies are slowed, and AI enemies target you. | STATUS |
| Unbowed | Immune to crowd control for a few seconds. | STATUS |

---

## Mage

Ranged DPS / Healer hybrid. The Great Staff deals damage, the Gauntlet heals and drains, and
the Wings add raw power and lockdowns. The Mage heals **at range**; the Paladin heals **up
close**.

### Great Staff (casting)
Area damage and big spells. Fire-themed to match the phoenix.
- **Branch: Conflagration.** Area of effect and burns. *Capstone:* your burning ground
  spreads to adjacent ground over time.
- **Branch: Focus.** Single target and charged spells. *Capstone:* fully charged casts cost
  no Ember.

| Ability | Effect | Tags |
|---|---|---|
| Firebrand | Fast bolt that applies burn. | PROJ, STATUS |
| Meteor Fall | Delayed large blast at a target point. | AREA |
| Flame Wall | A line of fire that damages anyone who crosses it. | AREA |
| Searing Ray | Channeled beam, damage ramps up over the channel. | |
| Blink | Short teleport. | DASH |
| Pyroclasm | Point-blank explosion that knocks enemies away. | FORCE |

### Gauntlet (life magic)
Mid range. Healing and draining, with some damage of its own.
- **Branch: Lifeweaver.** Direct heals and shields. *Capstone:* overhealing becomes a shield.
- **Branch: Siphon.** Damage that heals. *Capstone:* Siphon heals nearby allies, not only
  you.

| Ability | Effect | Tags |
|---|---|---|
| Mending Beam | Channeled heal on one ally. | ALLY |
| Renewal Pulse | Healing burst around a target point. | ALLY, AREA |
| Siphon | Damage beam on an enemy that heals you. | |
| Ward | Puts a damage-absorbing shield on an ally. | ALLY, STATUS |
| Life Spore | Places an orb that heals the first ally to touch it. | SUMMON, ALLY |
| Withering Touch | Close-range blast that reduces healing on the target. | STATUS |

### Mage Wings: magic power and crowd control
- **Branch: Ascendant.** Spell power. *Capstone:* Phoenix Aura also refunds part of your
  ability cooldowns.
- **Branch: Binder.** Lockdown. *Capstone:* Binding Embers silence as well as root.

| Ability | Effect | Tags |
|---|---|---|
| Phoenix Aura | Your spells deal more damage and heal more for a few seconds. | STATUS |
| Binding Embers | Roots enemies in an area. | AREA, STATUS |
| Searing Glare | Silences a target (no abilities). | STATUS |
| Wingfall | Pushes enemies back in a wide frontal arc. | FORCE |

---

## Paladin

Melee Tank / Healer hybrid. Heals by being in the fight, uses their wings as shields and
cleanses teammates.

### Dual Shortstaffs
Fast twin staves. Hitting enemies heals allies nearby.
- **Branch: Devotion.** Healing through hits. *Capstone:* every 4th hit pulses a heal around
  you.
- **Branch: Discipline.** Parries and defense. *Capstone:* a successful parry heals you and
  the ally closest to you.

| Ability | Effect | Tags |
|---|---|---|
| Consecrating Strikes | For a few seconds, your hits heal allies near you. | ALLY, STATUS |
| Twin Guard | Parry stance: blocks from the front and counters. | |
| Uplifting Blow | A strike that heals the lowest-health ally nearby. | ALLY |
| Spinning Staves | Spin that hits everything around you and deflects projectiles. | PROJ |
| Rush to Aid | Dash to an ally and shield them briefly. | DASH, ALLY |
| Rebuke | Strike that interrupts the target's attack. | |

### Longstaff (the Paladin's Great Staff, melee)
Reach and sweeps. Protects an area.
- **Branch: Sanctuary.** Areas that protect and heal. *Capstone:* allies in your consecrated
  ground take less damage.
- **Branch: Judgment.** Punishes attackers. *Capstone:* enemies who hit an ally inside your
  ground are marked for bonus damage.

| Ability | Effect | Tags |
|---|---|---|
| Sanctified Ground | Plants the staff: an area that heals allies and burns enemies. | AREA, ALLY |
| Sweeping Rebuke | Wide sweep that knocks enemies back. | FORCE |
| Guardian's Leap | Leaps to an ally's side. | DASH, ALLY |
| Staff Spin | Spins the staff in front of you to block projectiles while moving. | |
| Smite | Overhead blow that stuns. | STATUS |
| Benediction | Big heal on yourself and nearby allies; long cooldown. | ALLY |

### Paladin Wings: defensive wings and cleansing
- **Branch: Aegis.** Protecting others. *Capstone:* Sheltering Wings reflect projectiles.
- **Branch: Purifier.** Cleansing and Rebirth support. Passives in this branch:
  - Cleansing Flame also takes 30 s off the Rebirth cooldown of each ally it touches.
  - Allies near you need 10 less Ember to Rebirth.

  *Capstone:* Phoenix Blessing also refills the Ember of each ally it touches to at least 50.

| Ability | Effect | Tags |
|---|---|---|
| Sheltering Wings | Spreads the wings into a frontal barrier that stops projectiles for you and allies behind you. | SUMMON |
| Cleansing Flame | Removes debuffs from you and allies nearby. | ALLY, STATUS |
| Guardian Wing | Links to an ally; you take part of their damage. | ALLY, STATUS |
| Phoenix Blessing | For 30 s, allies nearby get one extra Rebirth that ignores the cooldown. Long cooldown. | ALLY, STATUS |
| Kindle Life | Channel on a fallen ally to Rebirth them, even if their Rebirth is on cooldown or they're short on Ember. | ALLY |

---

## Implementation notes (as built)

How each class beyond the Fighter was built: data files, the `World` helper blocks,
server-side rules, counters and models. Read the class's section before changing its
weapons or Wings. The shared systems (combat model, statuses, Ember, zones,
projectiles) and the Fighter's mechanics are in `CLAUDE.md`. Where a design above and
these notes disagree, these notes describe the code.

### Juggernaut (Halberd, Greataxe, War Hammer)

`data/class_juggernaut.cfg` (`--class=juggernaut`, `-Class juggernaut` for the run and
smoke scripts). Heavier and slower than the Fighter's weapons (turn_speed 540, longer
windups/recoveries, bigger numbers). Placeholder models are built in code in
`player.gd` (`_build_halberd_greataxe`, poses in `_halberd_pose` / `_greataxe_pose`).
Every new mechanic is server-only (no new `to_array()` fields); the `World` helpers sit
in one block, "Juggernaut: Halberd and Greataxe mechanics", and the bot needs nothing
special (it slots self-buffs, statuses and Hurl like any weapon).

- **War Hammer** (Juggernaut, `data/weapon_war_hammer.cfg`, model "war_hammer"): slow
  and heavy (light 95 dmg 0.2 s stagger; heavy 240 dmg 0.7 s stagger, 0.75 s windup,
  `breaks_block=false`; turn speed 420°/s). Abilities: Seismic Slam (90° cone 4 m,
  stagger 0.8 s, knockback 2 m), Clout (one target, Stun 1.5 s), Shatter (Shattered),
  Upheaval (3 m radial launch 1.5 m), Shockwave (projectile "shockwave": a low, flat,
  piercing wave, 14 m/s, ~10 m, stagger 0.6 s, a guard doesn't stop it), Steadfast
  (self). Tree `mastery_war_hammer.cfg`: Earthshaker (Slam, Upheaval, Shockwave) and
  Breaker (Clout, Shatter, Steadfast); default slots Slam, Clout, Upheaval. Capstones
  (server, `World._with_hammer_capstones`, every live heavy tick): **Earthshaker**
  (`heavy_shockwave`: `Player.heavy_counter` (`HeavyCounter`, by `attack_serial`) starts
  a `ShockRing` around the user every `amount`-th heavy (`World._spawn_shock_ring`,
  `ring_*` keys in `[ability_aftershock]`: 12 m/s to 6 m, 1 m band, feet ≤ 0.8 m up;
  `_step_shock_rings` after projectiles; each target once via `resolve_strike` /
  `strike_enemy` from the ring centre; clients `_receive_shock_ring`) and **Breaker**
  (`heavy_breaks_block`: the heavy's hits use `AttackParams.copy()` with
  `breaks_block=true`, made after `damage_multiplier`, which tells heavies apart by
  identity). Counted on the `SUMMARY juggernaut` line (aftershocks, wall_stuns,
  roar_guards; not checked).
- **Halberd** (`weapon_halberd.cfg`, tree `mastery_halberd.cfg`: Warden / Headsman).
  Light = reaching sweep (3 m × 2 m), heavy = overhead chop (3.4 m). Hooking Pull (5.5 m
  line, `max_targets` 1, pull 4.5 m, marks **Hooked**), Wide Reap (3.6 × 6 m sweep),
  Pole Vault (6 m dash + 1.6 m cosmetic leap, 2.3 m radial landing, knockback 2.5 m),
  Brace (self-buff **Braced**), Cleaving Arc (overhead chop, Exposed), Crowd Sweep
  (3 × 4.5 m box, push 4 m). Defaults: all six learned, Q/E/R = Hooking Pull, Wide Reap,
  Crowd Sweep.
- **Greataxe** (`weapon_greataxe.cfg`, tree `mastery_greataxe.cfg`: Maelstrom /
  Bloodied). Light = wide diagonal cleave (2.2 × 2.8 m), heavy = big chop. Vortex (3
  radial windows of 3.5 m, each pulling in; the body spins like Whirlwind Edge),
  Charging Chop (6 m dash, chop at the end), Grounding Blow (3.2 m slam, Slow 3 s),
  Executioner's Swing (attack-level execute: +150% at 0 health from 30%), Iron Hide
  (self-buff), Hurl (`[projectile_greataxe]`, ~15 m, stops at the first target, Slow
  5 s; the model leaves the hands in flight via `set_axe_thrown`). **Choice:** no
  pickup: "slowed until you pick the axe up" is a fixed 5 s slow. Defaults: all six
  learned, Q/E/R = Vortex, Charging Chop, Grounding Blow.
- **Brace** (`charge_stagger` 1 s, `charge_window` 1 s on `status_braced`): a melee hit
  (`_strike_player`, not projectiles) that lands on a Braced player (damaged, blocked or
  guard broken) staggers the attacker if it's a **charge**: the attacking player was
  mid-dash (`PlayerState.is_dashing`), or the hit landed within the first second of
  Braced (`StatusEffects.charge_stagger_ticks`, using the entry's `elapsed`). Enemies
  get `brain.stagger`; immunities apply. `World._brace_counter`.
- **Iron Hide** (`status_iron_hide`: `crowd_damage_taken` −0.08 per hostile within
  `crowd_radius` 5 m, at most `crowd_max` 5 → −40%, 6 s): `World._crowd_multiplier`
  counts living enemies and non-allied players around the target and multiplies the
  damage taken in `resolve_strike`, `_covered_hit` and damage over time
  (`StatusEffects.crowd_damage_taken_multiplier`).
- **Hyper armor** (Greataxe/War Hammer heavies and big abilities: Vortex, Charging Chop,
  Executioner's Swing, Seismic Slam, Clout, Upheaval, Shockwave): keys `armor_start` /
  `armor_end` (s; -1 = through the last hit window) → `PlayerState.has_hyper_armor` from
  the timeline (predicted, nothing synced). Refuses hit and guard-break staggers
  (`apply_stagger(..., through_armor)`) and forced movement (`is_force_immune`); stuns,
  roots and damage still land; the Halberd's Brace counter pierces it. Server:
  `World._hyper_armor_holds` → wire-only `HIT_UNSHAKEN` (10, "Unshaken -N"),
  `armor_absorbed=` on `SUMMARY juggernaut`. A bronze sheen while armored. Greataxe and
  War Hammer lights/heavies are ~25% slower (heavy windup 0.75 s, recovery 0.88 s).
- **Crits** (`[crit] damage_multiplier` 1.5 in combat.cfg, `PlayerParams.
  crit_damage_multiplier`): the Headsman capstone **Headsman's Verdict**
  (`effect="crit_staggered"`, `applies_to="heavy"`): a covered attack on a target that
  was staggered *before* the hit crits (`Player.crit_multiplier` →
  `MasteryTree.crit_multiplier`; `World._crit_multiplier` in `resolve_strike` /
  `strike_enemy`). Clients get `HIT_CRITICAL` (8) instead of `HIT_DAMAGED` (only on the
  wire; server results stay `HIT_DAMAGED`) and show "Critical! -N". Gear crit chance
  can reuse the multiplier.
- **Caught on the Hook** (Warden capstone, `effect="hook_stagger"`, `applies_to="hooked"`,
  `amount` 0.8 s): Hooking Pull applies **Hooked** only if the hooker has this capstone
  (`CharacterBuild.applies_mark` via `World._mark_learned`) (2.5 s debuff, no effect of its
  own; `Entry.source` = the hooker). With the node (Halberd out), the hooker's next
  damaging hit on that target staggers ≥ 0.8 s and removes the mark
  (`World._with_hook_stagger`; players via `PlayerState.remove_status`, a server event).
- **Maelstrom** (`effect="ability_range"`, `applies_to="vortex"`, `amount` 2): the
  server tests the ability's hitbox with `range` × amount (`AttackParams.range_copy`,
  `World._with_range_upgrade` in `_on_attack_stepped`), so Vortex hits and pulls from
  7 m. F3 still draws the base 3.5 m.
- **Red Tide** (Bloodied capstone, `effect="ramp_on_hit"`, `applies_to="bloodied"`): each
  step a melee attack/ability connects (`_on_player_attack_connected`) gives the attacker
  a stack of **Bloodied** (+3% damage dealt per stack, max 8, 2.5 s, refreshed per hit).
  Projectile hits don't add stacks.
- Counters: `SUMMARY juggernaut crits= hook_staggers= brace_staggers= bloodied_stacks=`
  (server, no smoke check).

### Assassin (Dual Talons, Throwing Knives)

`data/class_assassin.cfg` (`--class=assassin`, `-Class assassin`). Placeholder models
built in code in `player.gd` (`_build_assassin_models`: a three-blade claw on each fist,
or a knife in each hand), swung with the Dual Axes' poses (`_axe_pitches`). Every new
mechanic is server-only (no new `to_array()` fields); the `World` helpers sit in two
blocks, "Assassin: Dual Talons mechanics" and "Assassin: Throwing Knives mechanics".
Counters: `SUMMARY assassin backstabs= primed_crits= feint_reads= marked_hits=
flurry_fans= heal_cuts=` (no smoke check; `backstabs` counts every class's hits from
behind, bonus or not).

- **Dual Talons** (`weapon_dual_talons.cfg`, tree `mastery_dual_talons.cfg`: Predator /
  Tempest). The fastest light (38 dmg, 0.28 s), heavy 120. Pounce (5 m dash + 1 m
  cosmetic hop, hit at the landing), Rending Talons (bleed ×2), Eviscerate
  (attack-level execute: +100% at 0 health from 35%), Talon Spin (3 radial windows,
  2.4 m; spins the body), Feint (a weak poke with `read_status`, below), Hook Talon
  (3.5 m line, `max_targets` 1, pull 2 m). Defaults: all six learned, Q/E/R = Pounce,
  Rending Talons, Feint. The heavy has a 0 m knockback the smoke test turns on.
- **Backstabs** (`[backstab]` in combat.cfg, `World._is_backstab`): a player's hit
  from within `rear_arc` (180°) behind the target's facing (players: `state.yaw`,
  enemies: `brain.yaw`; a projectile's attacker position is back along its path), or
  on an enemy whose `brain.target_id` isn't the attacker (idle, or fighting someone
  else; `unaware_enemies`). Tree effects: `backstab_damage` (+amount on backstabs,
  `MasteryTree.backstab_multiplier` → `World._backstab_scale`, in `resolve_strike` /
  `strike_enemy`) and the Predator capstone **Unseen Strike** (`crit_backstab`:
  backstabs crit, `MasteryTree.crit_multiplier`'s `backstab` argument). **Choice:** the
  design's "hits from behind ignore block" was already true (the block arc is 120° in
  front), so the capstone crits backstabs instead.
- **Feint** (`read_status="primed"`, `AttackParams.read_status`): in `_hit_targets`, a
  player result `HIT_BLOCKED` / `HIT_GUARD_BROKEN` / `HIT_EVADED`, or an enemy in
  `EnemyBrain.Mode.ATTACK` when it lands, gives the attacker **Primed** once per step
  (`World._feint_read`). Primed (`next_hit_crits`): `World._crit_multiplier` crits the
  next hit that the tree doesn't already crit and removes it (`remove_status`, a
  server event). **Choice:** enemies never block or dodge, so "mid-swing" is their read.
- **Talon Storm** (Tempest capstone, `ramp_on_hit` with `applies_to="talon_storm"`):
  the Greataxe's Red Tide path with a *sim* status: each connecting step adds a stack
  of +4% attack speed (max 8, 1.5 s). Stacking attack speed: each stack adds
  `attack_speed - 1`, capped at `StatusEffects.MAX_ATTACK_SPEED` (2). Applied by the
  server, so it's a server event (no counted corrections). Counted in
  `bloodied_stacks=` on the juggernaut line.
- **Throwing Knives** (`weapon_throwing_knives.cfg`, tree `mastery_throwing_knives.cfg`:
  Venom / Flurry). Every attack throws `[projectile_knife]` (feather, 30 m/s, ~15 m,
  stops at the first target or a guard): light 1 knife (32), heavy 3 fanned 16° (42
  each). Fan of Knives (5 over 50°), Pinning Knife (Slow 3 s), Marked Blade (Marked),
  Venom Coat (self: next 5 hits poison, like Bloodlust). Defaults: all four learned,
  Q/E/R = Fan of Knives, Pinning Knife, Venom Coat. Ricochet (`[projectile_knife_ricochet]`,
  2 bounces within 7 m) and Recall (rips out embedded knives, see "Projectiles" in `CLAUDE.md`) are
  Flurry tier 2. **Magazine** (`[weapon] ammo` 6, `reload_time` 1.5 s when empty,
  `refill_delay` 2 s without throwing; per attack `ammo_cost`: light 1, heavy 3): a throw
  without ammo can't start (buffered); synced `to_array()` 36; HUD pips left of Q.
- **Marked** (`marked_bonus` 0.5, `StatusEffects.mark_from(defs, source)`): the
  marker's next *melee* hit (an attack without `projectile`) on the target deals +50%
  and removes the mark (`World._marked_scale`, players via `remove_status`).
- **Venom capstone Festering Wounds** (`heal_cut`, `applies_to="poison"`, 0.5): healing
  on a player carrying your poison is cut by half, whichever of your weapons is out
  (`World._heal_cut` in `_heal_player`).
- **Flurry capstone Endless Flurry** (`knife_flurry`, amount 5, `applies_to=
  "fan_of_knives"`): `World._knife_flurry` on `projectile_released` counts light/heavy
  throws (`Player.throw_counter`, a `HeavyCounter` by `attack_serial`); every 5th also
  fires Fan of Knives via `ProjectileSystem.server_fire_attack` (no cooldown used).
- **Assassin Wings** (`wings_assassin.cfg`, tree `mastery_wings_assassin.cfg`: Phantom /
  Trickster, 12 points): Ashstep (15 Ember, 6 s: a 4.5 m teleport the way you move, forward with none, i-frames)
  and Plumage Flash (20 Ember, 12 s: 6 m 70° cone, 20 damage, **Dazzled** −25% damage
  dealt 4 s + Slow 2.5 s), Ember Double (20 Ember, 14 s: a 4 s burning decoy, 15
  damage per 0.5 s around it, and **Veiled** 2 s) and Shadow Swap (15, 10 s, Trickster
  tier 3, requires Ember Double: trade
  places with your decoy; only while it's out). Defaults Z
  Ashstep, C Plumage Flash. Capstones: **Mirror Image** (`decoy_burst`: the decoy
  bursts as it ends, 80 damage + Dazzled within 3 m) and **Second Step**
  (`extra_charge`, applies_to ashstep: see "Charges" under Ranger). Wing Enhancement item: Ashen Vanes.
  Weapon items: Iron Talons, Iron Knives.

### Ranger (Longbow, Crossbow, Firebolts)

`data/class_ranger.cfg` (`--class=ranger`, `-Class ranger`; default loadout Longbow +
Firebolts). Every attack fires projectiles (`[projectile_arrow]`, `arrow_piercing`,
`arrow_rain`, `bolt`, `bolt_scatter`, `firebolt`, `flare`); the damage is the
projectile's hit. Placeholder models in `player.gd` (`_build_ranger_models`: a bow on
the left hand and a crossbow carried pointing down and raised level while attacking,
glowing ember wraps on both hands). World helpers: "Ranger: Longbow, Crossbow and
Firebolts mechanics". Counters: `SUMMARY ranger ignites= ignited_stacks= loaded_shots=
piercing_heavies= parting_shots= hunted_hits=` (no smoke check).

- **Longbow** (Marksman / Skirmisher): light quick shot (45), heavy full draw (0.6 s,
  140). Piercing Shot (pierce 4), Arrow Rain (a zone 12 m ahead: 35 damage every
  0.5 s for 2.5 s), Snare Arrow (Root 1.5 s),
  Backstep Shot (3.5 m `dash_direction="back"` + arrow), Hunter's Mark (**Hunted**:
  `damage_taken_from_source` +15% from the marker, `World._hunted_scale`), Rapid Nock
  (self attack speed 1.7, 4 s). Capstones: **True Flight** (`heavy_pierce`: heavy arrows
  pierce 20, `World.release_mods`) and **Running Shot** (`free_draw`, below).
- **Skirmisher's Running Shot is in the sim**: `CharacterBuild.free_move_mask()` (bit
  per weapon slot whose tree has `free_draw`) → `PlayerState.set_free_move` (server
  event) in `apply_to_state`, synced as `free_move_mask` in the packed header;
  `PlayerMovement` skips the attack's `move_multiplier` while `moves_freely()` (light
  or heavy with that slot out). The one tree effect that reaches the sim.
- **Crossbow** (Siege / Trapper): light bolt (70) with a 0.55 s recovery (the reload),
  heavy bolt (160, breaks blocks). Concussive Bolt (knockback 3 m), Bolt Barrage (4
  bolts, 8°), Scatter Bolt (6 short bolts, 45°), Quick Reload (self: attack speed 1.5
  and the next hit slows, `on_hit_status` + `consume_on_hit`). Siege capstone
  **Loaded Chamber** (`loaded_chamber`: a light/heavy shot ≥ `threshold` 2 s after
  your previous one deals ×2; `Player.last_release_tick`, `World.release_mods`, which
  `ProjectileSystem.server_fire_attack` calls once per release to scale
  `damage_scale` and raise `pierce_left`). Tripwire (a trap at your feet) and Smoke
  Bolt (a cloud where the bolt stops), Trapper tier 2; the Trapper capstone **Rearm**
  (`trap_rearm` 1: traps re-arm once).
- **Firebolts** (Kindling / Flashfire): light firebolt (26, 0.4 s; Overheat's ×1.6 brings it to 0.27 s, +1 **Burn**),
  heavy 3 bolts (60 each, Burn). Burn: 6 dps per stack, max 6, 4 s. Scatterflame (5
  bolts, 40°, Burn), **Ignite** (`detonates_status="burn"`, `detonate_damage` 35: on a
  hit, every Burn stack is removed for +35 base damage each, `World._detonate`, before
  the damage scales), Flare (**Flared**: `blind` 0.85, 2 s), Overheat (self attack speed
  1.6, 4 s; no lockout). Capstones: **Inferno** (`status_cap`: Burn you apply stacks to
  max_stacks × 2, `World._stack_cap` → `StatusEffects.apply(..., max_stacks)`) and
  **Cinder Return** (`ignite_ember`: 3 Ember per stack Ignite uses). Fire Trail
  (Kindling tier 2: your next 3 rolls leave burning ground), Seeker Spark (Flashfire
  tier 2: `[projectile_seeker_spark]`, 14 m/s, turns 220°/s toward the nearest hostile
  in front within 16 m, Burn ×2).
- **Ranger Wings** (Windrider / Parting Shot, 12 points): Gust Roll (15 Ember: rolls
  1.8× as fast for 5 s, so 1.8× as far: `dodge_speed_multiplier`), Tailwind (20:
  `move_multiplier` 1.3 haste + `dodge_cost_multiplier` 0.5, 6 s; `PlayerState.
  dodge_cost`), Backdraft (20: 4 m radial knockback 3 m), Updraft (25: a real jump,
  `launch_height` 3.5 m at `launch_time`, `PlayerMovement._self_launch_speed`, then
  **Updraft** `max_fall_speed` 0.4 m/s for 2.5 s: a hover, sinking slowly).
  Defaults Z Gust Roll, C Backdraft. Capstones: **Parting Gift** (`roll_empower`:
  `Player.dodged` (server) → `World._parting_shot` gives **Parting Shot**, +30%
  damage dealt consumed by the next hit) and **Second Wind** (`extra_charge`, applies_to
  roll: see "Charges" under Ranger).
- **Charges** (sim): a Wing-tree node `extra_charge` (`applies_to` "roll" or a Wing
  ability id) → `CharacterBuild.charge_mask` → `PlayerState.set_charge_mask` (server
  event, in `apply_to_state` like `free_draw`), synced with `spare_charges` in the packed
  header. A spare lets a roll (bit 0) or that Wing ability (bit 1 + pool index) be used
  again while its cooldown runs (a Wing spare doesn't restart the cooldown); it comes
  back when the cooldown is 0 (`_refill_charges` in `step`). Items: Ashwood Longbow, Iron Crossbow, Cinder Wraps,
  Galeborn Plumes.

### Mage (Great Staff, Gauntlet)

`data/class_mage.cfg` (`--class=mage`, `-Class mage`): no mana, so **weapon abilities
cost Ember** (`ember_cost`, predicted like Wing costs), and `[class] ember_gain` 2.0
doubles every Ember gain (`World._give_ember`, `ClassDef.ember_gain`). Placeholder
models in `player.gd` (a staff with an orb, carried like the crossbow; a glowing
gauntlet). World helpers: "Mage: heals, shields, channels". Counters: `SUMMARY mage
ally_supports= shields= absorbed= focus_refunds= aura_refunds=` (no checks).

- **Great Staff** (Conflagration / Focus): light fire bolt (40), heavy charged fireball
  (120, Burn ×2). Firebrand (5 Ember: Burn ×2), Meteor Fall (30: zone `meteor` 10 m
  ahead, one 220 blast after 1.2 s), Flame Wall (20: zone `flame_wall`, a 6 m box of fire
  5 m ahead, not solid: 20 + Burn every 0.5 s), Searing Ray (15: a 10 m beam, 6 windows,
  `window_ramp` 0.3: window i deals ×(1 + 0.3 i), applied to `damage_scale` in
  `_on_attack_stepped`), Blink (10: a 7 m teleport the way you move, forward with none, i-frames),
  Pyroclasm (20: 3.5 m radial, knockback 4 m). Capstones: **Wildfire Spread**
  (`zone_grow`, applies_to burn: your Burn-applying pulse zones grow 15% per pulse up
  to 2×, `World.zone_growth` → `Zone.scale`, `_receive_zone_scaled`) and **Clear Mind**
  (`focus_refund`: an ability started within 3 s of landing a heavy refunds its Ember,
  `Player.last_heavy_hit_tick`, `World._mage_ability_started`).
- **Gauntlet** (Lifeweaver / Siphon): light life bolt (35), heavy 8 m drain beam (90,
  `lifesteal` 0.3). Mending Beam (15: 10 m beam, 6 windows, `ally_heal` 30 per window,
  `allies_only`), Renewal Pulse (25: zone `renewal_pulse`, 160 to your side in a 3 m
  circle 6 m ahead), Siphon (10: 8 m beam, 5 windows of 30, `lifesteal` 0.5), Ward (20:
  `ally_shield` 150 to you and allies in a 10 m beam, `allies_only`), Life Spore (15:
  zone `life_spore`, an ally trap: heals the first ally to touch it 200), Withering
  Touch (10: Withered, `healing_taken` −0.5). Capstones: **Overflowing Life**
  (`overheal_shield`: healing past max becomes Ward, `World._overheal_shield` in
  `_heal_player`) and **Shared Vitality** (`siphon_share`: lifesteal also heals allies
  within 8 m).
- **Heals and shields** (server): `World._ally_support` heals/shields allies the hitbox
  touches once per window (they're never struck); `_lifesteal` after a damaging hit;
  **Ward** = the `absorbs` status + `Player.absorb` (the pool, server only):
  `World._absorb` takes hits from it in `resolve_strike` (after armor and block, not
  damage over time or zones) and removes the status when it's empty; a fully absorbed
  hit shows "Absorbed" (`HIT_ABSORBED` 9, wire only). `_heal_player` multiplies by the
  target's `healing_taken` and the healer's `healing_dealt` statuses.
- **Mage Wings** (Ascendant / Binder, 12 points): Phoenix Aura (25: +20% damage and
  healing 6 s), Binding Embers (25: zone `binding_embers`, Root 2 s in a 3.5 m circle 8
  m ahead), Searing Glare (20: 10 m line, 40 damage, **Silenced** 3 s), Wingfall (20:
  120° 5 m cone, knockback 4 m). Defaults Z Phoenix Aura, C Binding Embers. Capstones:
  **Rekindle** (`aura_refund`: Phoenix Aura halves what's left of your weapon ability
  cooldowns, `PlayerState.reduce_ability_cooldowns`, a server event) and **Hushing
  Embers** (`bind_silence`: Binding Embers also silences, `World.zone_effect`).
- **Silence** (`silences`, sim, crowd control): `PlayerState` won't start a weapon or
  Wing ability while silenced (presses stay buffered). No effect on Husks (no abilities).
- Items: Emberwood Staff, Lifeweave Gauntlet, Sunfire Pinions.

### Paladin (Dual Shortstaffs, Longstaff)

`data/class_paladin.cfg` (`--class=paladin`, `-Class paladin`). Melee tank/healer; no
projectiles (the smoke test skips its projectile check for a class whose weapons throw
nothing). Placeholder models in `player.gd` (a short staff in each hand, or one long
staff, swung like the axes). World helpers: "Paladin: healing hits, deflection,
sharing, blessings". Counters: `SUMMARY paladin heal_pulses= cleanses= blessings=
deflections= reflections= shared_damage= kindled= judgments=` (no checks).

- **Support keys** (attack/ability, server; `World._ally_support` → `_support_one`,
  and once for the user at the attack's first live step): `self_heal`, `ally_status`
  (allies only, never the user), `cleanses` (`PlayerState.cleanse`), `grants_rebirth`
  + `blessing_time` (an extra Rebirth via `grant_rebirth_charge`; `Player.
  blessing_until_tick`, taken back unused by `remove_rebirth_charge` in the server
  tick), `revives` (the last hit window raises fallen allies it touches:
  `World._kindle_life` → `_rebirth`, no Ember or cooldown needed), plus the Mage's
  `ally_heal`/`ally_shield`/`allies_only`. `heals_lowest_ally` + `heal_radius`: a
  connecting step heals the lowest-health ally (the user included).
- **Dual Shortstaffs** (Devotion / Discipline): light 45 (0.34 s), heavy 130 (breaks
  blocks). Consecrating Strikes (self **Consecrating**: `hit_heal` 15 within 6 m per
  connecting step, 6 s), Twin Guard (parry 140° + internal `twin_guard_counter`),
  Uplifting Blow (80 to the lowest ally within 10 m), Spinning Staves (3 radial
  windows, `deflects`), Rush to Aid (7 m dash, Ward 100 to your side at the end),
  Rebuke (0.8 s stagger). Capstones: **Radiant Rhythm** (`hit_pulse_heal`: every
  `count` 4th attack that connects heals 50 within 6 m; `Player.hit_counter`, a
  `HeavyCounter`; `MasteryNode.count`) and **Guarded Grace** (`parry_heal` 120 to you
  and your nearest ally, `World._parry_heal` from `_try_parry`).
- **Longstaff** (Sanctuary / Judgment): light 60 sweep (2.8 m), heavy 160. Sanctified
  Ground (zone `sanctified_ground`, `affects="both"`: allies healed 12 per 0.5 s,
  hostiles 10 + Burn; 4 m, 8 s), Sweeping Rebuke (5 m wide, knockback 3.5 m),
  Guardian's Leap (7 m leap, 60 damage around the landing, Ward 80 to allies there),
  Staff Spin (5 windows while walking, `deflects`), Smite (Stun 1.2 s), Benediction
  (200 to you and allies within 8 m, 40 s). Capstones: **Sanctuary**
  (`zone_ally_status`: allies on your ground get **Sanctified**, −15% damage taken)
  and **Judgment** (`judgment_mark`: an enemy whose swing reaches an ally on your
  ground is **Judged**, +20% damage taken 5 s; `World._judgment`,
  `ZoneSystem.zones_at`).
- **Deflection** (`deflects`, `World.deflects` from `ProjectileSystem._hit_player`):
  while such an ability is in its windup or hit windows, a hostile projectile reaching
  the user stops (0-damage `HIT_BLOCKED`).
- **Paladin Wings** (Aegis / Purifier, 12 points): Sheltering Wings (20 Ember: zone
  `sheltering_wings`, a `solid` wall with `blocks_enemies=false`: projectiles stop,
  people pass, 4 s), Cleansing Flame (15: cleanses you and allies within 8 m),
  Guardian Wing (20: **Guardian Link** on allies in a 12 m line: `damage_share` 0.3 of
  each hit's damage goes to you, `World._guardian_share` in `resolve_strike`),
  Phoenix Blessing (40, 90 s: an extra Rebirth for you and allies within 8 m for 30 s),
  Kindle Life (30, 60 s: a 2 s channel that raises fallen allies within 3 m). Defaults
  Z Sheltering Wings, C Cleansing Flame. Passives `cleanse_rebirth` (30 s off each
  cleansed ally's Rebirth cooldown) and `rebirth_discount` (allies dying within 10 m
  need 10 less Ember: `World._rebirth_discount` → `start_rebirth(params, discount)`).
  Capstones: **Mirror Aegis** (`wall_reflect`: a projectile stopped by your Sheltering
  Wings flies back, now yours: `World.reflect_projectile` →
  `ProjectileSystem.server_fire_from`) and **Everflame** (`blessing_ember`: Phoenix
  Blessing refills Ember to ≥ 50).
- Items: Oakheart Shortstaffs, Dawnwood Longstaff, Halo Pinions.


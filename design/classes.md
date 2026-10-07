# Classes, Weapons, Abilities and Upgrade Trees

Design draft. Nothing here is built yet. Ability names are placeholders that are original
to this project. Numbers like "3 slots" and "20 levels" are starting points; once built,
the real values go in `data/*.cfg`.

## How the pieces fit

The brief (`newer-world-handoff.md`) says each character carries **two weapons with a swap
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
is a melee tank, so they play like two different weapons. This draft calls the Paladin's
the **Longstaff** (a melee quarterstaff) to keep them apart. See the open questions.

### Ability tags

Each ability below is tagged with the engine systems it needs. That shows what has to be
built before the ability can exist:

- `PROJ`: projectiles (none exist yet; every ranged weapon needs them). Most projectiles
  (arrows, bolts, knives, Firebolts) are **feather-shaped**: that's the game's visual
  signature.
- `STATUS`: buffs and debuffs with durations (bleed, burn, slow, root, stun, silence, damage reduction)
- `DASH`: the caster moves themselves (lunge, leap, blink)
- `FORCE`: moves other players (knockback, pull, knock-up)
- `AREA`: a ground effect that lasts after the cast
- `ALLY`: targets or affects teammates (heals, shields, cleanse). Needs parties.
- `SUMMON`: spawns an entity (decoy, trap, barrier)
- `STEALTH`: hides the player. The server must stop sending their position, otherwise
  players could read it from snapshots.

---

## Fighter

Melee, Tank / DPS hybrid. A flexible front-liner: the Broadsword leans defensive, the Dual
Axes lean all-in, and the Spear sits in between with reach. The current sword is a
Broadsword prototype.

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
| Shadow Swap | Swaps places with your decoy, or with a target hit by Marked Blade. | DASH |

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

## Build order

Every class depends on systems that don't exist yet. The work is split into waves. Tasks
within a wave run in parallel on separate branches. A wave starts only once the one
before it has been merged and tested.

**Wave 1** (milestone 4: second weapon and weapon swap)
- **1A. Ability framework + weapon swap + the Fighter class.**
  - Ability slots, with cooldowns in ticks inside `PlayerState`.
  - One `data/weapon_<name>.cfg` per weapon.
  - Mastery tree logic, with free respecs.
  - Built with **Broadsword** (today's sword) and **Dual Axes**, using only abilities
    that need nothing new, or only `DASH`.
- **1B. Parties + ally rules** (`ALLY` foundation).
  - Invite, accept and leave, decided by the server.
  - Party members can't damage each other.
  - Party health frames on the HUD.
  - Doesn't touch `PlayerState`.

**Wave 2** (each one also adds the Fighter abilities that need it)
- **2A. Status effects** (`STATUS`). Durations in ticks. Effects that change movement or
  actions (slow, root, stun) live in `PlayerState`. Effects that only change damage
  (bleed, Exposed) can stay on the server.
- **2B. Forced movement** (`FORCE`): knockback and pull. These are server events, like
  stagger, so they don't count as corrections.
- **2C. Projectiles** (`PROJ`). Simulated on the server, drawn on clients, feather-shaped.
- **2D. Ember, Wing slots and Rebirth.** Rebirth plugs into the existing death and
  respawn flow.

**Wave 3**
- The Spear and the rest of the Fighter's Wing abilities.
- Enemy threat (needed for taunt).
- The Juggernaut.

**Later**
- Ground effects, summons and traps (`AREA`, `SUMMON`).
- Stealth.
- Updraft hover.

Class order after the Fighter: Juggernaut (melee only, mostly `FORCE`) → Assassin (Talons
first) → Ranger → Mage → Paladin.

## Decisions (2026-10-07)

- Class is fixed per character. Classes don't share weapons.
- Firebolts are a hand-fired weapon. Bolts, arrows, knives and most other projectiles are
  feather-shaped.
- Mages use Ember instead of mana.
- Rebirth is automatic: a 5 s animation, then you're back with 30% health. It needs and
  spends 50 Ember and has a 5 minute cooldown.
- No attributes for now. Phoenix/fire-themed ones may come later.
- PvE is the main focus; PvP is minor.
- Respecs are free at any time.

# Newer World: project handoff

"Newer World" is a working title. This file hands the project to a new Claude Code session that will start building it. Part 1 records the decisions already made. Part 2 is the conversation those decisions came from.

---

# Part 1: Project brief

## What we're building

A small online action RPG with combat, gathering, crafting, loot and movement modeled on New World: Aeternum, using low-poly graphics. The target is 10–50 players at once per server instance, with persistent characters.

It is deliberately not a true MMO. Out of scope: territory wars, a server-wide trading post economy, housing, and large-scale open-world events.

## Decisions already made

- **Engine:** Godot 4 (latest stable), GDScript. The client and a headless dedicated server build come from the same project.
- **Networking:** server-authoritative from milestone 1. The server resolves combat hits, loot rolls, inventory and crafting. Clients predict only their own movement. Adding networking later would mean rewriting combat, so it is not an option.
- **Persistence:** SQLite during development, accessed only through one persistence module so the move to Postgres before launch stays contained.
- **Art:** placeholder CC0 packs (Kenney, Quaternius) and Mixamo animations. Paid art waits until the game is fun with ugly art.
- **IP:** mechanics can be borrowed. Names, art, UI layouts and item names must be original.
- **Budget:** the developer's personal Claude Pro subscription. No paid services until an always-on server is needed.

## Systems in scope

- **Combat:** action combat, no tab-targeting. Light and heavy attacks, block, dodge roll with i-frames, stamina, hitbox-based melee hit detection.
- **Weapons:** two equipped weapons with a swap key. Each weapon has its own abilities on cooldowns and a mastery tree.
- **Attributes:** STR/DEX/INT/FOC/CON-style stats feeding damage formulas.
- **Loot:** loot tables with rarity tiers, rolled stats, perks and gear score ranges.
- **Inventory:** equipment slots, item weight, durability.
- **Gathering:** ore, wood, fiber and hide nodes with tool requirements and respawn timers.
- **Crafting:** tradeskill XP curves, refining chains, recipes, crafting stations.

## Build order

Don't start a milestone until the one before it works.

1. **Networked combat slice.** Third-person controller, one weapon (sword and shield), light/heavy/block/dodge, stamina, one enemy type, two players connected to a dedicated server. Done when fighting the enemy with a second player feels good.
2. **Loot loop.** Enemy drops with rarity and rolled stats, inventory, equipping gear that changes the player's numbers.
3. **Gathering and crafting.** Two or three node types, one refining step, one crafting station, tradeskill XP.
4. **Second weapon and weapon swap.** Abilities on cooldowns, a small mastery tree.
5. **Persistence.** Accounts, character saves, inventory surviving a server restart.
6. **One zone.** Mob camps, node spawns, a town with crafting stations. Then playtest with real people.

## How to work in this repo

- Use git from the first commit, with a private GitHub repo.
- Keep `CLAUDE.md` describing the architecture. Update `PROGRESS.md` at the end of every session with what was done, what's next and any known bugs. Each new session reads those two files before touching code, instead of re-exploring the codebase.
- Give each session one goal that can be tested. "Dodge roll with i-frames, tunable from one config file" is a good session. "Work on combat" is not.
- Put every tuning value (damage, timings, stamina costs, drop rates, respawn timers) in data files, not in code. The developer adjusts game feel by editing these files directly.
- Write tests (using a Godot test framework such as GUT) for systems that don't depend on feel: loot rolls, damage formulas, crafting outputs, inventory rules. Leave combat feel to manual playtesting.
- The developer is on Claude Pro, which has usage limits. Keep sessions focused and avoid broad, open-ended exploration.

## First session

1. Confirm Godot 4 is installed and which version it is.
2. Set up `git init`, a `.gitignore` for Godot, the project folder structure, `CLAUDE.md` and `PROGRESS.md`.
3. Add a dedicated server entry point that runs headless from a command-line flag, plus a client that connects to it.
4. Done when two clients running on one PC both connect to the local server and see each other move.

## Cost plan

| Stage | Cost |
|---|---|
| Building milestones 1–6 locally | $0 beyond Claude Pro ($20/mo) |
| Playing with friends | $0: host on the developer's PC and connect over Tailscale's free plan or a forwarded port |
| Always-on playtest server | Hetzner CX23, €5.49/mo, billed hourly and can be deleted after a playtest |
| Live, 50 players at once | about $70/mo: Hetzner CCX13 (€42.99) + DigitalOcean managed Postgres ($15.15) + backups |
| Steam release | $100 one time, refunded after $1,000 in revenue |

Prices are as of October 2026. Hetzner raised prices twice in 2026, so check them again before ordering.

---

# Part 2: Original conversation

Lightly edited: the cost answer originally assumed a Claude Max subscription. Development now happens on Claude Pro, so the Part 1 cost table replaces that line.

## Q1: What can I realistically accomplish with Claude Code?

> I want to create an MMO game that has similar weapon, farming, loot, movement mechanics to New World: Aeternum, but with much lighter graphics. What can I realistically accomplish with Claude Code?

The code is the part Claude Code can carry. What it can't carry is the "MMO" part, plus art and game feel. A small online action-RPG with New World's combat, gathering, crafting and loot is realistic. Hundreds of players sharing one persistent world is not, at least for a first build.

### Where Claude Code does most of the work

Most of what makes New World *New World* is data-driven systems, and Claude writes those well:

- Loot tables with rarity tiers, rolled stats, perks and gear score ranges
- Inventory, equipment slots, item weight and durability
- Gathering nodes (ore, wood, fiber, hides) with tool requirements and respawn timers
- Tradeskill XP curves, refining chains and crafting recipes
- Weapon swap with two equipped weapons, each with its own abilities, cooldowns and mastery tree
- Attribute scaling (STR/DEX/INT/FOC/CON-style) feeding damage formulas
- Server-side validation, save/load, database schema
- Balance tooling, like a script that simulates 50,000 loot drops and shows you the actual rarity distribution

It can also write the combat code: light and heavy attacks, blocking, dodge with i-frames, stamina, and hitbox-based melee instead of tab-targeting.

### Where you have to carry it

**Game feel.** Claude can implement a dodge roll but can't feel whether it's good. Hit-stop, animation cancel windows, how heavy a greatsword swing feels: all of that gets tuned by you playing it hundreds of times and reporting back. Expect most of your own time to go here.

**Art and animation.** Claude won't produce usable 3D models or animations. With lighter graphics this is solvable using free low-poly packs (Kenney, Quaternius) and Mixamo animations, or paid Synty packs if you want a consistent look. Budget real time for importing, rigging fixes and animation retargeting. Claude can help with the code side of that, but not the art side.

**Scale.** The features that make New World massive are territory wars, a server-wide trading post economy, and hundreds of players in one zone. They're mostly infrastructure and live-ops problems, and they're what to cut first. Aim for 10–50 players per server instance with persistent characters. That's still a real online game.

### The decision that matters most: build it networked from day one

The most common way projects like this die is building a fun single-player prototype and then trying to bolt multiplayer on. Action combat over a network needs a server-authoritative design, client-side prediction and lag compensation for hit detection. Retrofitting that means rewriting combat. Even if milestone 1 only supports two players on your own machine, the server should own the state from the start.

### Recommended stack

**Godot 4** for client and server, with a headless dedicated server build, plus SQLite at first and Postgres later. Scenes and scripts are plain text files, so Claude can read and edit everything directly instead of guiding you through editor clicks. It's free, handles low-poly 3D comfortably, and includes animation, physics and navmesh, which you'd otherwise build yourself.

Unity is a weaker fit because so much of the work happens in the editor. A browser build (Three.js plus a TypeScript server) would give you instant shareable playtests, but you'd spend months rebuilding what Godot ships with.

### A realistic build order

1. **Networked combat slice.** Third-person controller, one weapon (sword and shield), light/heavy/block/dodge, stamina, one enemy type, two players connected to a dedicated server. Don't move on until fighting the enemy is fun.
2. **The loot loop.** Enemy drops with rarity and rolled stats, inventory, equipping gear that changes your numbers.
3. **Gathering and crafting.** Two or three node types, one refining step, one crafting station, tradeskill XP.
4. **Second weapon and weapon swap.** Abilities on cooldowns, a small mastery tree.
5. **Persistence.** Accounts, character saves, inventory surviving a server restart.
6. **One zone.** Mob camps, node spawns, a town with crafting stations. Then playtest with real people.

Each step is a stretch of focused sessions with Claude, not a single prompt. Keep the project in git, keep a `CLAUDE.md` that describes the architecture, and add tests for the systems that aren't about feel (loot rolls, damage formulas, crafting outputs). Without those, a codebase this size drifts.

One legal point: mechanics like weapon swapping and gear score can't be owned, but names, art, UI layouts and item names can. Use your own for all of those.

## Q2: What will it cost to build and run?

> I'd love to get a cost breakdown from you on what this would cost to create (not including labor for graphic design / art dev) and maintain from a server perspective.

Hosting turns out to be the cheapest part of this project. At 10–50 players, a year of Claude subscription costs more than a year of servers. Your own time is still the biggest cost.

### Building it (assumes 12 months)

The original version of this answer assumed Claude Max 5x ($100/mo). Development now happens on Claude Pro ($20/mo), which brings a year of building to about $240 for Claude, plus the items below.

| Item | Cost | Notes |
|---|---|---|
| Godot, Blender, Mixamo | $0 | |
| Playtest server (Hetzner CX23) | €5.49/mo, about $75/yr | Shared vCPU, so the tick rate will jitter. Fine for playing with friends. |
| Domain | about $15/yr | |
| Steam Direct fee | $100, one time | Refunded once the game earns $1,000. |

Optional asset spend: Synty's All Access Pass is $30/mo, or about $360 for the year. Kenney and Quaternius packs are free. Start on the free packs and only pay once you know the art style you want.

### Running it live (50 players at once)

| Item | Monthly | Notes |
|---|---|---|
| Game server (Hetzner CCX13, dedicated vCPU) | €42.99 | Dedicated cores keep the tick rate steady. That matters more for action combat than raw power does. |
| Managed Postgres (DigitalOcean, smallest plan) | $15.15 | Includes automated backups. Losing player characters is the one failure players won't forgive, so this is worth paying for. |
| Backups and monitoring | a few dollars | |
| Claude Pro for maintenance | $20 | |
| **Total** | **about $90/mo** | Converted at roughly $1.15 per euro; check the rate when ordering. |

For closed playtests before launch, put the database on the CX23 alongside the game server. That's under $10/mo. Each extra shard or region (for example, adding an EU server next to US East) means another game server at about $50/mo. The database can be shared.

### Things that could change these numbers

**Hetzner raised prices twice in 2026.** The CCX13 went up 169% in June. Prices are now close enough that OVH's Rise-1 bare-metal server ($64/mo, game-focused DDoS protection) is a real alternative. If someone starts hitting the server with DDoS attacks, which happens to small online games more often than you'd expect, move to OVH.

**Bandwidth is an estimate, not a measured figure.** With sensible design (players only receive updates about things near them), each player uses roughly 10–30 KB/s. Fifty players online around the clock would come to about 2.6 TB a month. The real average player count will be far lower. That's well within Hetzner's European traffic allowance, but its US locations have historically included less traffic, so check before choosing Ashburn or Hillsboro. US servers are the right call if the players are in North America.

**Paid anti-cheat can be skipped.** Because the server decides every hit and every loot roll, there's much less to cheat with.

Sources:
- [Claude Max plan pricing (zenken)](https://ai.zenken.co.jp/en/post/claude-max-plan-guide/)
- [Hetzner June 2026 price increase (privatedevops)](https://privatedevops.com/news/hetzner-june-2026-cloud-price-increase-what-to-do)
- [Hetzner price increase analysis (wz-it)](https://wz-it.com/en/blog/hetzner-price-increase-june-2026-cpx-ccx-alternatives/)
- [DigitalOcean Managed PostgreSQL pricing (InfraTally)](https://infratally.com/articles/digitalocean-managed-postgres-deep-dive/)
- [OVHcloud game server prices](https://www.ovhcloud.com/en/bare-metal/game/prices/)
- [Steamworks app fee documentation](https://partner.steamgames.com/doc/gettingstarted/appfee)
- [Synty All Access Pass (gamefromscratch)](https://gamefromscratch.com/?p=28561)

## Q3: What can be done without paying for anything new?

> What parts can get done without committing to a long term paid investment? Assuming I use my current Claude subscription and work on this slowly over time.

You can build almost all of it without paying anything beyond your current Claude subscription. The first required cost is a server, and you only need one once other people want to play while your PC is off. Even then it's month-to-month and can be cancelled.

### Free the whole way

All six milestones can be built and tested on your own machine:

- **Engine and tools.** Godot is MIT-licensed, so there's no license fee and no royalties. Blender and Mixamo are free too.
- **Multiplayer testing.** The dedicated server and several game clients can all run on one PC. That's how you'll test networking most of the time anyway.
- **Database.** Use SQLite, which is just a local file, during development. Moving to Postgres later is a contained job if database access sits behind one module from the start.
- **Art.** Kenney and Quaternius packs are CC0 (free to use, no attribution needed), and Mixamo has animations. Expect placeholder quality, which is fine while you work out game feel.
- **Version control.** A private GitHub repo is free. Use it from day one, because it's how you undo a session that went wrong.

### Free, with some friction

**Playing with friends.** Host the server on your own PC and let friends connect through Tailscale's free plan, or by forwarding a port on your router. It works, but only while your PC is on, and your home upload speed limits how many players it can handle. For a handful of friends testing combat, that's enough.

### Where money actually starts

1. **An always-on server for testers you don't know personally.** That's the Hetzner CX23 at €5.49/mo. Hetzner bills by the hour up to that monthly cap, so a weekend playtest costs well under a dollar and you can delete the server afterward.
2. **The Steam fee ($100)**, only when you're ready to put up a store page.
3. **Paid art**, only if the free packs can't give you a consistent style. That decision can wait until the game is fun with ugly art.

### Making a limited subscription go further

Working slowly suits this project, because game feel needs playtime between coding sessions anyway. Some habits that make each session count:

- **Give every session one goal you can test.** "Dodge roll with i-frames, tunable from one config file" is a good session. "Work on combat" uses up your limit without finishing anything.
- **Keep a `CLAUDE.md` and a short `PROGRESS.md` in the repo.** Each new session then starts by reading two files instead of exploring the whole codebase again, which is where a lot of usage goes.
- **Put tuning values in data files.** Then adjusting a dodge's timing is something you edit yourself in seconds, without needing Claude.

Hold off paying for anything until milestone 1 (two players fighting an enemy over a network) feels good. If it never does, you'll have spent nothing.

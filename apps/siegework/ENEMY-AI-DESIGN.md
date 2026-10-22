# Enemy AI redesign: working notes

Status: **design complete 2026-10-22; implemented 2026-10-22** on
`nitin/siegework-patches` (see Implementation notes at the end). Local
notes, not upstream.

## Already built (local, uncommitted)

- `wave-interval` 300 → 600 ticks (`siege.sld`): waves every 60 s.
- Turrets have 0 reach: no sight, no wire reach (`world.sld` `kind-reach`).
- Turrets wire **only to pylons** (`joinable?` / `node-kind` in `world.sld`,
  used by `link` and by `in-reach?` in `colony.sld`).

## Decided

- **Decision per step.** Each enemy decides from:
  - its own position,
  - the hub position,
  - structures within 4 cells of it,
  - the full terrain map.
- **Knowledge (revised 2026-10-22).** Enemies know the whole terrain map.
  They know the hub's position always, but other structures only when
  within 4 cells of that enemy. (Replaces the earlier "discover terrain
  through sight" idea.)
- **Navigation.** Head for the hub on roughly the shortest path, with small
  per-enemy differences for variety.
- **Burrowing is a choice, not a flag (2026-10-22).** The `burrower` flag
  goes away. Every species can dig through rock, and chooses to:
  - with **low** probability normally,
  - with **medium** probability if digging gives a shorter path,
  - with **high** probability if there is no other path.
  - **When:** the choice is made once each time the enemy plans its route.
  - **Chances:** low = 5%. Shorter-path chance = 5% + x·n%, where n is how
    many cells digging saves and x is a tuning factor. So small savings
    barely raise the chance and there is no separate minimum.
  - **Dig speed is damage-based:** an enemy digs at its own attack damage.
    Different terrain has different health.
- **Aggression.** Each enemy has an aggression level. It decides whether the
  enemy attacks a structure within 4 cells or ignores it.
- **Attack chain.** Once an enemy attacks a structure in sight, it keeps
  attacking structures in sight until none are left, then goes back to
  heading for the hub.
- **Workers are targets (2026-10-22).** Workers within 4 cells count like
  structures for the aggression roll and the attack chain. Workers fight
  back.
- **Repeatable randomness.** Any randomness (aggression, path differences)
  comes from the enemy's id and the tick, because saves replay the order
  journal.

## Decided in the 2026-10-22 question round (enemy side)

- **Dig choice** is made once per route plan. Two candidate routes: the
  best walking route and the best route allowed to dig. Each cell of
  rock or wall on the digging route costs its dig time, which is that
  terrain's health divided by the enemy's dig rate.
  - n = seconds saved by the digging route, counting the dig time.
  - chance = min(100%, base + x·n%). If n ≤ 0, the chance is just the base.
  - No walking route means n is infinite, so the chance is 100%.
  - Normal enemies: base 5%, x = 2 (each second saved adds 2%). *(x chosen
    by Claude, to tune.)*
  - **Burrowers** come back as a flag: 5% of enemies. They dig 3× faster,
    and are more likely to dig: base 15%, x = 4. *(numbers chosen by
    Claude.)*
- **Terrain health:** rock 300, ice 200, water can't be dug. Walls 200 /
  250 / 300 by level (base 100 × 2 / 2.5 / 3).
- **Dig rate:** an enemy's rank damage per hit, with dig hits every 2 ticks;
  burrowers ×3.
- **Path variety:** a fixed left or right lean per enemy, plus random
  sideways steps that are not longer.
- **Sight:** 4 cells. Rock and walls do NOT block it.
- **Aggression:** rolled once for each structure or worker that comes into
  sight. Normal enemies roll 10–50%, raiders 30–90%, Beasts 10%. Raiders and
  Beasts are presets on top of that; raiders keep their speed and lower
  health.
- **No revenge.** Being shot doesn't make an enemy target the turret
  unless that turret is within its 4-cell sight anyway.
- **Attack mode:** the nearest structure or worker in sight. Skip anything
  unreachable (for example across water).

## Workers and the Portal (added 2026-10-22)

The doc now covers more than enemy AI: this section is colony-side.

### Decided

- **Workers are back, labour only.** Building, upgrading and repairing need
  a worker to walk to the site. Workers don't carry the cost or ore.
- **Workers:** 20 energy, 3 s to build, maximum 20, start with 3. They're
  built from a "Build worker" button on the hub, in the same queue as
  buildings, and they replace the hub's build slots.
  - Stats: 60 health, 6 damage per second, adjacent range only, a move
    every 5 ticks.
  - **No fleeing.** They fight back when hit or when an enemy is next to
    them, then resume work.
  - Jobs are taken automatically: oldest job first, nearest free worker.
  - A worker's death leaves the site's progress for the next worker.
  - Workers can't dig.
- **Portal is an upgrade on a pylon.** It's a separate upgrade choice on
  any built pylon (level 1–3), costing 60 energy and taking 4 s. The
  pylon keeps its pylon role: it carries power and powers turrets, with
  its current level's reach. Portals are linked: workers jump instantly
  between powered portals and the hub, then walk from whichever is
  closest to the job by walking route. They return to the nearest one.
  **A portal works only while powered** (revised: earlier notes said
  portals need no power).
- **Walls:** player-built terrain on open ground only, built and upgraded
  by workers.
  - Costs 10, then +10, then +15 energy, 2 s each. Health 200 / 250 / 300.
  - Enemies treat walls as terrain: they know them from the map and dig
    through them.
  - A wall carries power to any pylon that can see it (within the pylon's
    sight radius, no rock in the way). Power passes along chains of
    touching walls. Walls never power turrets directly. Walls block shots
    like rock, but not enemy sight.
  - Removing a wall refunds half its energy.
- **Hotkeys:** 4 wall, 5 portal (on top of 1–3 build and U upgrade).

### Practical

- Delete all existing Siegework saves.
- Tests need recalibrating to the new rules.
- Work on local branch `nitin/siegework-patches`; nothing pushed.

### Reference

The old worker system is in commit `bf828bc8`,
`apps/siegework/src/siegework/model.sld`. It was much bigger: workers
carried paid "kits", ore went through workers and depot freight, workers
were assembled at the hub, and routes avoided known threats. `#363`
replaced workers with the energy network and build slots.

### Open questions

None. Design is complete; implementation is next.

## Previous AI (replaced), for reference

As it was in `src/siegework/siege.sld` before the rewrite. Targets were revenge on a turret that hit
them, raiders picking exposed outposts more than 9 cells from the hub, and
otherwise the hub. Routes were distance fields over the full terrain.
Enemies stopped at the first building they bumped into.

## Implementation notes

Choices made while building this where the decisions above were silent
or open to reading. Each is small and easy to change.

### Enemies

- **Ice.** Ice stays walkable, as before, so its 200 dig health never
  comes into play: nothing ever has to dig ice. It is not in the code.
  If ice should block walkers until dug, that is a one-line change in
  `routes.sld` (`walkable?` and `enter-cost`).
- **Dig time in planning.** Rock and walls are planned at full health
  (300, or the wall's level health), even when partly dug. Each cell
  costs `period + 2 * ceil(health / dig damage)` ticks, so walking and
  digging routes compare in ticks; n is the whole seconds saved,
  `floor((walk - dig) / 10)`.
- **"Best digging route"** is the cheapest route that is *allowed* to
  dig. When digging saves nothing it is the walking route itself, so a
  base-chance roll then changes nothing visible; the base only acts as
  the floor of `base + x·n`.
- **Re-planning.** An enemy plans (and rolls its dig choice) when its
  goal changes or the terrain changes: rock opened, or a wall raised,
  upgraded or lost. Every terrain change therefore re-rolls every
  enemy's choice once.
- **Dig hits** come every other tick per enemy, staggered by id. Several
  enemies at one face all count; the old cap of two diggers is gone.
- **Route fields.** Fields to the hub are Dijkstra fields over the whole
  map, cached in the world per (step period, dig damage) and dropped on
  any terrain change. Fields to an attack target (always within four
  cells) are computed over a 17×17 window around the enemy and never
  cached, which also handles moving workers.
- **Reachable** means on the mainland, since water is the only thing that
  cannot be dug. A target that still cannot be reached inside the window
  is given up and the enemy heads for the hub.
- **Aggression level.** Each enemy draws one level at spawn, uniformly in
  its range (minions 10–50, raiders 30–90, beasts 10). Every structure or
  worker that comes into sight is rolled against it once, by id, ever.
- **Attack chain.** The hub is never a chain target; it is the default
  goal, struck from beside it. When a target falls the enemy strikes
  nothing until its next step, when it takes the next nearest thing in
  sight (structures listed before workers on ties, oldest first).
- **Walls are not targets.** Enemies never attack walls or wall sites;
  they only dig walls that lie on their planned route.
- **Lean and sideways steps.** Of the steps on a cheapest route, an enemy
  takes the one that heads most directly at its goal (smallest remaining
  distance on the longer axis), ties going to its lean, left or right,
  fixed from its id. One step in four is instead any of the cheapest
  steps at random: "sideways steps that are not longer". The old crowd
  spreading is gone.
- **Randomness.** Every chance is `hash(seed, key, a, b)` from the
  terrain's hash, with a distinct key per use (burrower, aggression level,
  aggression roll, dig choice, sideways step, lean) and the enemy's id
  with the tick or the sighted thing's id.
- **Buildings other than walls** still do not block walking.

### Colony

- **One worker per job**, one tick of progress per tick at the site. A
  worker labors from the site's cell or beside it (the hub from its
  footprint or beside it). Only powered (in-reach) jobs are assigned;
  unpowered ones wait unassigned. "Nearest" counts steps, including
  portal jumps. Assignment runs every tick; workers move every 5 ticks.
- **Idle workers** walk back to the nearest powered portal or hub cell.
- **Fighting.** While any enemy is beside a worker it neither moves nor
  labors, and it strikes the oldest adjacent enemy for 6 on the same
  once-a-second beat as enemy strikes.
- **Rush and the first extractor** still finish at once, no worker needed.
- **Hub repair** is now a worker job: priced as before, paid when ordered,
  2 s of labor, full health when done.
- **Worker training** is a queue at the hub; the first trains with no
  worker. The cap of 20 counts workers standing and in training. Rush at
  the hub finishes its oldest work and Cancel its newest. Upgrading the
  hub is refused ("The hub has no upgrades; it trains workers.").
- **Portal jumps.** A worker standing on the hub or a powered portal jumps
  to the node nearest its job when that saves more than two steps (so it
  never hops within the hub's footprint); elsewhere it walks to the
  nearest node first when that route is shorter. A portal's 60 counts in
  what scavenging the pylon returns.
- **Walls** need visible open ground but no wire reach, and no power to
  build or upgrade. They are network nodes: touching includes corners;
  a wall joins the hub as well as pylons that see it (the hub as the
  source of power); a pylon may be built off a powered wall; wires are
  drawn along walls. Walls block shots, not wires. A wall whose health is
  dug to 0 is destroyed and counts as a lost building.

### Other

- **Keys.** 4 and 5 were rush and close; rush stays on R, close on Escape
  and the close button. B builds a worker.
- **Schedule fixes.** `next-attack-tick` stepped by half the wave interval,
  which after the 600-tick waves skipped every wave and showed only
  bosses; it now steps by 15 s. Raids every 600 ticks would have replaced
  every wave; the raid interval is now 1200 so they replace every other.
- **How to play.** The opening banner's link pointed at the published
  online book, which still has the old rules until this branch ships. It
  now opens `public/guide.html`, shipped with the game: the README's
  guide section converted to HTML. It is a copy, so it must be updated
  whenever the README guide changes.
- **Saves** are stored under `siegework-v2`; the changed order schema
  would also refuse old journals.
- **Balance** (tests/balance.out): undefended hubs fall at ticks
  830–1090 (38–64 s after the first attack leaves), so the threshold
  moved from 1000 to 1200. A hub with one pylon, a ring of eight turrets,
  an upgraded extractor and spare pylons holds 3000 ticks on all eight
  seeds, at 544–600 health.
